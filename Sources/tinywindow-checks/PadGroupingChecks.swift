import TinyWindowCore

func runPadGroupingChecks() {
    print("— PadGrouping")

    func grid(_ name: String, _ x: Int, _ y: Int, _ w: Int, _ h: Int,
              columns: Int = 6, rows: Int = 6) -> Layout {
        Layout(name: name, kind: .grid(.init(columns: columns, rows: rows,
                                             cellX: x, cellY: y, cellW: w, cellH: h)))
    }

    // The user's real Window Tidy set, in import order — must group exactly as
    // the original app shows: [Centre] [halves] [Full Screen] [quarters].
    let wtSet = [
        grid("Centre", 1, 1, 4, 4),
        grid("Left Half", 0, 0, 3, 6),
        grid("Right Half", 3, 0, 3, 6),
        grid("Full Screen", 0, 0, 6, 6),
        grid("Q1", 0, 0, 3, 3),
        grid("Q2", 3, 0, 3, 3),
        grid("Q3", 0, 3, 3, 3),
        grid("Q4", 3, 3, 3, 3),
    ]
    let groups = PadGrouping.groups(for: wtSet, groupingEnabled: true)
    expect(groups.count == 4, "WT set groups into 4 pads, got \(groups.count)")
    if groups.count == 4 {
        expect(groups[0].layouts.map(\.name) == ["Centre"], "pad 1 = Centre alone")
        expect(groups[1].layouts.map(\.name) == ["Left Half", "Right Half"], "pad 2 = halves")
        expect(groups[2].layouts.map(\.name) == ["Full Screen"], "pad 3 = Full Screen alone")
        expect(groups[3].layouts.map(\.name) == ["Q1", "Q2", "Q3", "Q4"], "pad 4 = quarters")
        expect(groups[1].isGrouped && groups[3].isGrouped, "halves and quarters are grouped")
        expect(!groups[0].isGrouped && !groups[2].isGrouped, "Centre and Full stay single")
        expect(groups[3].gridColumns == 6 && groups[3].gridRows == 6, "group carries grid dims")
    }

    // Grouping disabled → one pad per layout.
    expect(PadGrouping.groups(for: wtSet, groupingEnabled: false).count == wtSet.count,
           "grouping disabled → singles")

    // Different grid dimensions never merge, even when regions are disjoint.
    let mixedDims = [grid("A", 0, 0, 1, 2, columns: 2, rows: 2),
                     grid("B", 2, 0, 2, 4, columns: 4, rows: 4)]
    expect(PadGrouping.groups(for: mixedDims, groupingEnabled: true).count == 2,
           "different grid dims stay separate")

    // Fixed layouts always get their own pad.
    let withFixed = [grid("L", 0, 0, 3, 6),
                     Layout(name: "F", kind: .fixed(.init(width: 800, height: 600,
                                                          centerX: true, centerY: true))),
                     grid("R", 3, 0, 3, 6)]
    let fixedGroups = PadGrouping.groups(for: withFixed, groupingEnabled: true)
    expect(fixedGroups.count == 2, "fixed splits its own pad; halves still merge")
    expect(fixedGroups[1].layouts.map(\.name) == ["F"], "fixed pad is single")

    // Edge-touching regions (shared boundary) count as disjoint.
    let touching = [grid("T1", 0, 0, 3, 6), grid("T2", 3, 0, 3, 6)]
    expect(PadGrouping.groups(for: touching, groupingEnabled: true).count == 1,
           "shared-edge regions group together")
}
