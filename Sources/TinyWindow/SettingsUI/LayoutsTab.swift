import SwiftUI
import TinyWindowCore

struct LayoutsTab: View {
    @ObservedObject var model: SettingsModel
    @State private var selection: UUID?

    var body: some View {
        HSplitView {
            layoutList
                .frame(minWidth: 230, idealWidth: 250, maxWidth: 320)
            editorPane
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { selection = selection ?? model.layouts.first?.id }
    }

    private var layoutList: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(model.layouts) { layout in
                    HStack(spacing: 8) {
                        LayoutGlyphView(layout: layout)
                            .frame(width: 30, height: 20)
                        if let binding = model.binding(for: layout.id) {
                            TextField("名称", text: binding.name)
                                .textFieldStyle(.plain)
                        } else {
                            Text(layout.name)
                        }
                        Spacer()
                        if case .fixed = layout.kind {
                            Text("固定尺寸")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                    .tag(layout.id)
                }
                .onMove { model.moveLayouts(from: $0, to: $1) }
            }
            Divider()
            HStack(spacing: 4) {
                Button {
                    selection = model.addLayout()
                } label: {
                    Image(systemName: "plus")
                }
                Button {
                    if let selection { model.deleteLayouts(ids: [selection]) }
                    selection = model.layouts.first?.id
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selection == nil)
                Spacer()
                Text("拖动可排序，顺序即 pad 顺序")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
    }

    @ViewBuilder
    private var editorPane: some View {
        if let selection, let binding = model.binding(for: selection) {
            LayoutEditor(layout: binding)
                .padding()
        } else {
            ContentUnavailableView("选择一个布局", systemImage: "rectangle.3.group",
                                   description: Text("在左侧选择布局进行编辑，或点 + 新建。"))
        }
    }
}

// MARK: - Editor for one layout

struct LayoutEditor: View {
    @Binding var layout: Layout

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch layout.kind {
            case .grid(let spec):
                GridRangeEditor(spec: Binding(
                    get: { spec },
                    set: { layout.kind = .grid($0) }))
            case .fixed(let spec):
                VStack(alignment: .leading, spacing: 8) {
                    Label("固定尺寸布局（导入自 Window Tidy）", systemImage: "square.dashed")
                        .font(.headline)
                    Text("尺寸 \(Int(spec.width)) × \(Int(spec.height)) pt · " +
                         (spec.centerX ? "水平居中" : "距左 \(Int(spec.positionX)) pt") + " · " +
                         (spec.centerY ? "垂直居中" : "距顶 \(Int(spec.positionY)) pt"))
                        .foregroundStyle(.secondary)
                    Text("v1 支持重命名、排序和删除；几何编辑将在后续版本提供。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Grid cell-range editor

struct GridRangeEditor: View {
    @Binding var spec: Layout.GridSpec
    /// Live selection during a drag; committed to the binding on release so we
    /// don't persist to disk on every pointer tick.
    @State private var draft: Layout.GridSpec?
    @State private var dragAnchor: (column: Int, row: Int)?

    private var display: Layout.GridSpec { draft ?? spec }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 20) {
                Stepper("列：\(display.columns)",
                        value: Binding(get: { spec.columns },
                                       set: { spec = adjusted(spec, columns: $0) }),
                        in: 1...12)
                Stepper("行：\(display.rows)",
                        value: Binding(get: { spec.rows },
                                       set: { spec = adjusted(spec, rows: $0) }),
                        in: 1...12)
            }

            GeometryReader { geo in
                grid(in: geo.size)
            }
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .frame(maxWidth: 420)

            HStack(spacing: 16) {
                Text("拖选格子设定窗口区域")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(pointSizeLabel)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 420)
        }
    }

    private func grid(in size: CGSize) -> some View {
        let s = display.normalized()
        let cellW = size.width / CGFloat(s.columns)
        let cellH = size.height / CGFloat(s.rows)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary.opacity(0.5))
            ForEach(0..<s.rows, id: \.self) { row in
                ForEach(0..<s.columns, id: \.self) { column in
                    let selected = column >= s.cellX && column < s.cellX + s.cellW
                        && row >= s.cellY && row < s.cellY + s.cellH
                    RoundedRectangle(cornerRadius: 3)
                        .fill(selected ? AnyShapeStyle(Color.accentColor.opacity(0.85))
                                       : AnyShapeStyle(.quaternary))
                        .frame(width: max(1, cellW - 3), height: max(1, cellH - 3))
                        .offset(x: CGFloat(column) * cellW + 1.5,
                                y: CGFloat(row) * cellH + 1.5)
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let cell = cellAt(value.location, size: size)
                    if dragAnchor == nil { dragAnchor = cell }
                    guard let anchor = dragAnchor else { return }
                    let minC = min(anchor.column, cell.column)
                    let maxC = max(anchor.column, cell.column)
                    let minR = min(anchor.row, cell.row)
                    let maxR = max(anchor.row, cell.row)
                    draft = Layout.GridSpec(columns: spec.columns, rows: spec.rows,
                                            cellX: minC, cellY: minR,
                                            cellW: maxC - minC + 1, cellH: maxR - minR + 1)
                }
                .onEnded { _ in
                    if let draft { spec = draft }
                    draft = nil
                    dragAnchor = nil
                })
    }

    private func cellAt(_ point: CGPoint, size: CGSize) -> (column: Int, row: Int) {
        let s = display.normalized()
        let column = min(max(0, Int(point.x / (size.width / CGFloat(s.columns)))), s.columns - 1)
        let row = min(max(0, Int(point.y / (size.height / CGFloat(s.rows)))), s.rows - 1)
        return (column, row)
    }

    /// Changing the grid density keeps the selected range clamped inside it.
    private func adjusted(_ spec: Layout.GridSpec, columns: Int? = nil, rows: Int? = nil) -> Layout.GridSpec {
        var next = spec
        if let columns { next.columns = columns }
        if let rows { next.rows = rows }
        return next.normalized()
    }

    private var pointSizeLabel: String {
        guard let screen = NSScreen.main else { return "" }
        let rect = GridMath.rect(for: display, in: CGRect(origin: .zero, size: screen.visibleFrame.size))
        return "主屏上 ≈ \(Int(rect.width)) × \(Int(rect.height)) pt"
    }
}

// MARK: - Shared glyph (same GlyphRenderer as the overlay pads)

struct LayoutGlyphView: View {
    let layout: Layout

    var body: some View {
        Canvas { context, size in
            context.withCGContext { cg in
                let accent = NSColor.controlAccentColor
                let style = GlyphStyle(
                    screenFill: NSColor.labelColor.withAlphaComponent(0.08).cgColor,
                    screenStroke: NSColor.labelColor.withAlphaComponent(0.4).cgColor,
                    regionFill: accent.withAlphaComponent(0.85).cgColor,
                    regionStroke: accent.cgColor,
                    cornerRadius: 3)
                GlyphRenderer.draw(layout, in: cg, rect: CGRect(origin: .zero, size: size),
                                   style: style)
            }
        }
    }
}
