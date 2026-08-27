import Foundation

/// Window Tidy's AutoGroupLayouts: grid layouts that share the same grid
/// dimensions AND whose cell regions are mutually disjoint merge into one pad —
/// the pad shows all regions on one mini screen, and the drop lands on
/// whichever region the cursor is inside. Overlapping layouts (Centre, Full
/// Screen) keep their own pad, as do fixed-size layouts.
///
/// Verified against the original app: [Centre, Left Half, Right Half, Full
/// Screen, 4 quarters] groups into exactly [Centre] [halves] [Full] [quarters].
public struct PadGroup: Sendable {
    public var layouts: [Layout]

    public init(layouts: [Layout]) {
        self.layouts = layouts
    }

    public var isGrouped: Bool { layouts.count > 1 }

    /// Grid dimensions shared by every member (nil for a single fixed layout).
    public var gridColumns: Int? {
        if case .grid(let spec) = layouts.first?.kind { return spec.normalized().columns }
        return nil
    }

    public var gridRows: Int? {
        if case .grid(let spec) = layouts.first?.kind { return spec.normalized().rows }
        return nil
    }
}

public enum PadGrouping {
    public static func groups(for layouts: [Layout], groupingEnabled: Bool) -> [PadGroup] {
        guard groupingEnabled else { return layouts.map { PadGroup(layouts: [$0]) } }
        var result: [PadGroup] = []
        for layout in layouts {
            guard case .grid(let raw) = layout.kind else {
                result.append(PadGroup(layouts: [layout]))
                continue
            }
            let spec = raw.normalized()
            // Greedy: join the first existing group with identical grid
            // dimensions where the new region overlaps none of the members.
            if let index = result.firstIndex(where: { canJoin($0, spec) }) {
                result[index].layouts.append(layout)
            } else {
                result.append(PadGroup(layouts: [layout]))
            }
        }
        return result
    }

    private static func canJoin(_ group: PadGroup, _ spec: Layout.GridSpec) -> Bool {
        guard group.gridColumns == spec.columns, group.gridRows == spec.rows else { return false }
        for member in group.layouts {
            guard case .grid(let memberRaw) = member.kind else { return false }
            if overlaps(memberRaw.normalized(), spec) { return false }
        }
        return true
    }

    private static func overlaps(_ a: Layout.GridSpec, _ b: Layout.GridSpec) -> Bool {
        a.cellX < b.cellX + b.cellW && b.cellX < a.cellX + a.cellW &&
        a.cellY < b.cellY + b.cellH && b.cellY < a.cellY + a.cellH
    }
}
