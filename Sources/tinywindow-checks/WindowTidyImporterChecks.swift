import Foundation
import TinyWindowCore

func runWindowTidyImporterChecks() {
    print("— WindowTidyImporter")

    guard let fixture = Bundle.module.url(forResource: "Layouts", withExtension: "data",
                                          subdirectory: "Fixtures") else {
        fail("fixture Layouts.data missing from bundle")
        return
    }

    do {
        let result = try WindowTidyImporter.importFile(at: fixture)

        // 8 grid layouts + 1 fixed, nothing skipped.
        expect(result.layouts.count == 9, "9 layouts imported, got \(result.layouts.count)")
        expect(result.skippedEntryCount == 0, "nothing skipped")
        expect(!result.sourceHash.isEmpty, "source hash present")

        // EndX/EndY are exclusive: Left Half maps to cellX 0, cellW 3.
        if let leftHalf = result.layouts.first(where: { $0.name == "Left Half" }),
           case .grid(let spec) = leftHalf.kind {
            expect(spec.columns == 6 && spec.rows == 6, "Left Half grid 6×6")
            expect(spec.cellX == 0 && spec.cellY == 0, "Left Half starts at 0,0")
            expect(spec.cellW == 3 && spec.cellH == 6, "exclusive End: cellW 3, cellH 6")
        } else {
            fail("Left Half missing or not grid")
        }
        if let full = result.layouts.first(where: { $0.name == "Full Screen" }),
           case .grid(let spec) = full.kind {
            expect(spec.cellW == 6 && spec.cellH == 6, "Full Screen covers the whole grid")
        } else {
            fail("Full Screen missing or not grid")
        }

        // Empty names get geometric synthesis: the four quarters.
        let names = result.layouts.map(\.name)
        for quarter in ["Top Left Quarter", "Top Right Quarter",
                        "Bottom Left Quarter", "Bottom Right Quarter"] {
            expect(names.contains(quarter), "synthesized name '\(quarter)' present")
        }

        // LayoutType 1 maps to a fixed layout with WT semantics.
        if let fixed = result.layouts.first(where: { $0.name == "Mail Size" }),
           case .fixed(let spec) = fixed.kind {
            expect(spec.width == 1200 && spec.height == 800, "fixed size preserved")
            expect(spec.centerX && !spec.centerY, "fixed centering flags preserved")
            expect(spec.positionY == 20, "fixed positionY preserved")
            expect(fixed.legacy?.quickLayoutKeyCode == -1, "legacy fields preserved")
        } else {
            fail("Mail Size missing or not fixed")
        }

        // Global preferences map onto TinyWindow settings. OptionButton=1 means
        // "⌥ temporarily hides the pads" (verified against the real app —
        // pads always appear on a plain drag).
        expect(result.preferences.padVisibilityMode == .optionHides, "OptionButton 1 → optionHides")
        expect(result.preferences.showPadTitles == true, "ShowTitles mapped")
        expect(result.preferences.enabled == true, "Enabled mapped")
        expect(result.preferences.groupPads == true, "AutoGroupLayouts mapped")

        // All imported layouts carry the wtImport origin.
        expect(result.layouts.allSatisfy { $0.origin == .wtImport }, "origin == wtImport")
    } catch {
        fail("fixture import threw: \(error)")
    }

    // Missing file throws fileNotFound.
    do {
        _ = try WindowTidyImporter.importFile(at: URL(fileURLWithPath: "/nonexistent/Layouts.data"))
        fail("missing file should throw")
    } catch let error as WTImportError {
        if case .fileNotFound = error { Checks.passes += 1 } else { fail("expected fileNotFound, got \(error)") }
    } catch {
        fail("unexpected error type: \(error)")
    }

    // Corrupt plist throws malformed.
    let corruptURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("corrupt-\(UUID().uuidString).data")
    do {
        try Data("not a plist at all".utf8).write(to: corruptURL)
        defer { try? FileManager.default.removeItem(at: corruptURL) }
        _ = try WindowTidyImporter.importFile(at: corruptURL)
        fail("corrupt file should throw")
    } catch let error as WTImportError {
        if case .malformed = error { Checks.passes += 1 } else { fail("expected malformed, got \(error)") }
    } catch {
        fail("unexpected error type: \(error)")
    }

    // Name synthesis table: halves, thirds, two-thirds, centre, fallback.
    typealias Spec = Layout.GridSpec
    let table: [(Spec, String)] = [
        (Spec(columns: 6, rows: 6, cellX: 0, cellY: 0, cellW: 6, cellH: 6), "Full Screen"),
        (Spec(columns: 6, rows: 6, cellX: 0, cellY: 0, cellW: 3, cellH: 6), "Left Half"),
        (Spec(columns: 6, rows: 6, cellX: 3, cellY: 0, cellW: 3, cellH: 6), "Right Half"),
        (Spec(columns: 6, rows: 6, cellX: 0, cellY: 0, cellW: 6, cellH: 3), "Top Half"),
        (Spec(columns: 6, rows: 6, cellX: 0, cellY: 3, cellW: 6, cellH: 3), "Bottom Half"),
        (Spec(columns: 6, rows: 6, cellX: 0, cellY: 0, cellW: 2, cellH: 6), "Left Third"),
        (Spec(columns: 6, rows: 6, cellX: 2, cellY: 0, cellW: 2, cellH: 6), "Middle Third"),
        (Spec(columns: 6, rows: 6, cellX: 4, cellY: 0, cellW: 2, cellH: 6), "Right Third"),
        (Spec(columns: 6, rows: 6, cellX: 0, cellY: 0, cellW: 4, cellH: 6), "Left Two Thirds"),
        (Spec(columns: 6, rows: 6, cellX: 2, cellY: 0, cellW: 4, cellH: 6), "Right Two Thirds"),
        (Spec(columns: 6, rows: 6, cellX: 1, cellY: 1, cellW: 4, cellH: 4), "Centre"),
    ]
    for (spec, expected) in table {
        let got = WindowTidyImporter.synthesizedName(for: spec, index: 0)
        expect(got == expected, "synthesis \(expected), got \(got)")
    }
    let odd = Spec(columns: 7, rows: 5, cellX: 1, cellY: 0, cellW: 3, cellH: 2)
    expect(WindowTidyImporter.synthesizedName(for: odd, index: 4) == "Imported Layout 5",
           "fallback name uses 1-based index")
}
