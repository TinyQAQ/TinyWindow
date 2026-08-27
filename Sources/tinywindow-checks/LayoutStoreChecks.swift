import Foundation
import TinyWindowCore

func runLayoutStoreChecks() {
    print("— LayoutStore")

    func makeStore() -> (LayoutStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TinyWindowChecks-\(UUID().uuidString)", isDirectory: true)
        return (LayoutStore(directory: dir), dir)
    }

    // Save then load round-trips layouts exactly.
    do {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let layouts = LayoutDefaults.starterSet()
        try store.save(layouts)
        let loaded = try store.load()
        expect(loaded == layouts, "round-trip equality")
        expect(store.lastLoadSkippedCount == 0, "nothing skipped")
    } catch {
        fail("round-trip threw: \(error)")
    }

    // Missing file loads as empty, not an error.
    do {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let loaded = try store.load()
        expect(loaded == [], "missing file → []")
    } catch {
        fail("missing file threw: \(error)")
    }

    // A newer schemaVersion refuses to load AND refuses to overwrite.
    do {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let futureFile = #"{"schemaVersion": 999, "layouts": []}"#
        try Data(futureFile.utf8).write(to: store.fileURL)

        do { _ = try store.load(); fail("newer schema load should throw") }
        catch let error as LayoutStoreError {
            if case .newerSchema = error { Checks.passes += 1 } else { fail("expected newerSchema on load") }
        }
        do { try store.save([]); fail("newer schema save should throw") }
        catch let error as LayoutStoreError {
            if case .newerSchema = error { Checks.passes += 1 } else { fail("expected newerSchema on save") }
        }
        let onDisk = try String(contentsOf: store.fileURL, encoding: .utf8)
        expect(onDisk == futureFile, "newer file untouched")
    } catch {
        fail("newer-schema scenario threw: \(error)")
    }

    // Corrupt JSON throws corrupted.
    do {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{{{{".utf8).write(to: store.fileURL)
        do { _ = try store.load(); fail("corrupt file should throw") }
        catch let error as LayoutStoreError {
            if case .corrupted = error { Checks.passes += 1 } else { fail("expected corrupted, got \(error)") }
        }
    } catch {
        fail("corrupt scenario threw: \(error)")
    }

    // An entry with an unknown kind is skipped; the rest load.
    do {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let mixed = """
        {"schemaVersion": 1, "layouts": [
          {"id": "0B7B22F5-9E5B-4B41-9E7B-111111111111", "name": "Good", "origin": "user",
           "kind": {"type": "grid", "columns": 2, "rows": 2, "cellX": 0, "cellY": 0, "cellW": 1, "cellH": 2}},
          {"id": "0B7B22F5-9E5B-4B41-9E7B-222222222222", "name": "Future", "origin": "user",
           "kind": {"type": "spiral", "turns": 3}}
        ]}
        """
        try Data(mixed.utf8).write(to: store.fileURL)
        let loaded = try store.load()
        expect(loaded.count == 1 && loaded.first?.name == "Good", "unknown kind skipped, good entry kept")
        expect(store.lastLoadSkippedCount == 1, "skip counted")
    } catch {
        fail("lenient decoding threw: \(error)")
    }

    // Layout Codable round-trips through JSON, legacy fields included.
    do {
        let original = Layout(
            name: "测试布局",
            kind: .grid(.init(columns: 8, rows: 4, cellX: 2, cellY: 1, cellW: 4, cellH: 2)),
            origin: .wtImport,
            legacy: LegacyWTFields(quickLayoutKeyCode: 12, quickLayoutKeyFlags: 256, screenID: 2))
        let decoded = try JSONDecoder().decode(Layout.self, from: JSONEncoder().encode(original))
        expect(decoded == original, "grid layout Codable round-trip")

        let fixed = Layout(name: "F",
                           kind: .fixed(.init(width: 1024, height: 768, centerX: true, centerY: false,
                                              positionX: 5, positionY: 6)))
        let fixedDecoded = try JSONDecoder().decode(Layout.self, from: JSONEncoder().encode(fixed))
        expect(fixedDecoded == fixed, "fixed layout Codable round-trip")
    } catch {
        fail("Codable round-trip threw: \(error)")
    }
}
