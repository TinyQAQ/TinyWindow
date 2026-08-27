import SwiftUI
import TinyWindowCore

struct ImportTab: View {
    @ObservedObject var model: SettingsModel
    @State private var preview: WTImportResult?
    @State private var previewError: String?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.wtDataExists {
                ContentUnavailableView(
                    "未找到 Window Tidy 数据",
                    systemImage: "magnifyingglass",
                    description: Text("没有在 ~/Library/Application Support/Window Tidy/ 找到 Layouts.data。"))
            } else if let preview {
                Label("找到 \(preview.layouts.count) 个 Window Tidy 布局",
                      systemImage: "checkmark.circle")
                    .font(.headline)

                if model.lastImportHash == preview.sourceHash {
                    Text("当前数据此前已导入过；重复导入不会产生变化。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)],
                              alignment: .leading, spacing: 10) {
                        ForEach(preview.layouts) { layout in
                            VStack(spacing: 4) {
                                LayoutGlyphView(layout: layout)
                                    .frame(width: 64, height: 42)
                                Text(layout.name)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .padding(8)
                            .background(.quaternary.opacity(0.4),
                                        in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(2)
                }
                .frame(maxHeight: 240)

                HStack {
                    Button("导入并替换现有布局") { message = model.importWT(replace: true) }
                        .buttonStyle(.borderedProminent)
                    Button("追加到现有布局") { message = model.importWT(replace: false) }
                }
                if let message {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Label("无法解析 Window Tidy 数据", systemImage: "exclamationmark.triangle")
                if let previewError {
                    Text(previewError).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .onAppear {
            do {
                preview = try WindowTidyImporter.importFile()
            } catch {
                preview = nil
                previewError = String(describing: error)
            }
        }
    }
}
