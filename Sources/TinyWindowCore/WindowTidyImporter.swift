import Foundation
import CryptoKit

public enum WTImportError: Error, Sendable {
    case fileNotFound(String)
    case unreadable(String)
    case malformed(String)
}

/// Global preferences recovered from a Window Tidy data file, mapped onto
/// TinyWindow settings. nil = the legacy file didn't specify it.
public struct WTImportedPreferences: Equatable, Sendable {
    public var enabled: Bool?
    public var padVisibilityMode: PadVisibilityMode?
    public var showPadTitles: Bool?
    public var groupPads: Bool?
}

public struct WTImportResult: Sendable {
    public var layouts: [Layout]
    public var preferences: WTImportedPreferences
    /// SHA-256 of the source file, for import idempotence.
    public var sourceHash: String
    /// Entries that could not be mapped (missing required fields).
    public var skippedEntryCount: Int
}

public enum WindowTidyImporter {
    public static func defaultDataURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Window Tidy/Layouts.data")
    }

    public static func dataFileExists(at url: URL? = nil) -> Bool {
        FileManager.default.fileExists(atPath: (url ?? defaultDataURL()).path)
    }

    public static func importFile(at url: URL? = nil) throws -> WTImportResult {
        let fileURL = url ?? defaultDataURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw WTImportError.fileNotFound(fileURL.path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw WTImportError.unreadable(String(describing: error))
        }
        let document: WTLegacyDocument
        do {
            document = try PropertyListDecoder().decode(WTLegacyDocument.self, from: data)
        } catch {
            throw WTImportError.malformed(String(describing: error))
        }

        var layouts: [Layout] = []
        var skipped = 0
        for (index, entry) in document.layouts.enumerated() {
            if let layout = layout(from: entry, index: index) {
                layouts.append(layout)
            } else {
                skipped += 1
            }
        }

        // OptionButton semantics verified against the real app: pads appear on
        // a plain drag; the Option key temporarily HIDES them (1). It is never
        // a hold-to-show gate.
        let preferences = WTImportedPreferences(
            enabled: document.enabled,
            padVisibilityMode: document.optionButton.flatMap { button in
                switch button {
                case 0: .always
                case 1: .optionHides
                default: nil
                }
            },
            showPadTitles: document.showTitles,
            groupPads: document.autoGroupLayouts)

        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return WTImportResult(layouts: layouts, preferences: preferences,
                              sourceHash: hash, skippedEntryCount: skipped)
    }

    // MARK: - Entry mapping

    static func layout(from entry: WTLegacyDocument.Entry, index: Int) -> Layout? {
        let legacy = legacyFields(from: entry)
        let type = entry.layoutType ?? 0
        if type == 0 {
            guard let gx = entry.gridX, let gy = entry.gridY,
                  let sx = entry.startX, let sy = entry.startY,
                  let ex = entry.endX, let ey = entry.endY,
                  gx > 0, gy > 0, ex > sx, ey > sy else { return nil }
            let spec = Layout.GridSpec(columns: gx, rows: gy,
                                       cellX: sx, cellY: sy,
                                       cellW: ex - sx, cellH: ey - sy).normalized()
            let name = normalizedName(entry.name) ?? synthesizedName(for: spec, index: index)
            return Layout(name: name, kind: .grid(spec), origin: .wtImport, legacy: legacy)
        } else {
            guard let w = entry.width, let h = entry.height, w > 0, h > 0 else { return nil }
            let spec = Layout.FixedSpec(width: CGFloat(w), height: CGFloat(h),
                                        centerX: entry.centreX ?? false,
                                        centerY: entry.centreY ?? false,
                                        positionX: CGFloat(entry.positionX ?? 0),
                                        positionY: CGFloat(entry.positionY ?? 0))
            let name = normalizedName(entry.name) ?? "Imported Layout \(index + 1)"
            return Layout(name: name, kind: .fixed(spec), origin: .wtImport, legacy: legacy)
        }
    }

    private static func normalizedName(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func legacyFields(from entry: WTLegacyDocument.Entry) -> LegacyWTFields? {
        guard entry.quickLayoutKeyCode != nil || entry.quickLayoutKeyFlags != nil
                || entry.screenID != nil else { return nil }
        return LegacyWTFields(quickLayoutKeyCode: entry.quickLayoutKeyCode ?? -1,
                              quickLayoutKeyFlags: entry.quickLayoutKeyFlags ?? 0,
                              screenID: entry.screenID ?? 0)
    }

    /// Geometric name synthesis for entries with empty names (the newer-format
    /// Window Tidy entries in real files often have "").
    public static func synthesizedName(for spec: Layout.GridSpec, index: Int) -> String {
        let s = spec.normalized()
        let c = s.columns, r = s.rows
        let x = s.cellX, y = s.cellY, w = s.cellW, h = s.cellH
        let fullW = w == c, fullH = h == r
        let atLeft = x == 0, atTop = y == 0
        let atRight = x + w == c, atBottom = y + h == r

        if fullW && fullH { return "Full Screen" }
        // Halves
        if fullH && 2 * w == c { return atLeft ? "Left Half" : atRight ? "Right Half" : "Center Vertical Half" }
        if fullW && 2 * h == r { return atTop ? "Top Half" : atBottom ? "Bottom Half" : "Center Horizontal Half" }
        // Quarters
        if 2 * w == c && 2 * h == r && (atLeft || atRight) && (atTop || atBottom) {
            return "\(atTop ? "Top" : "Bottom") \(atLeft ? "Left" : "Right") Quarter"
        }
        // Vertical thirds
        if fullH && 3 * w == c {
            if atLeft { return "Left Third" }
            if atRight { return "Right Third" }
            if 3 * x == c { return "Middle Third" }
        }
        if fullH && 3 * w == 2 * c {
            if atLeft { return "Left Two Thirds" }
            if atRight { return "Right Two Thirds" }
        }
        // Centered inset region
        if !atLeft && !atTop && !atRight && !atBottom && c - w == 2 * x && r - h == 2 * y {
            return "Centre"
        }
        return "Imported Layout \(index + 1)"
    }
}
