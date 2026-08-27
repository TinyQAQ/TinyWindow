import Foundation

public enum LayoutStoreError: Error, Sendable {
    /// The file was written by a newer TinyWindow. Refuse to load or overwrite it.
    case newerSchema(found: Int, supported: Int)
    case corrupted(String)
    case ioFailure(String)
}

/// JSON persistence for layouts in ~/Library/Application Support/TinyWindow/.
/// Not thread-safe by design — call from one context (the app uses the main thread);
/// the engine receives immutable layout snapshots via EngineConfiguration instead.
public final class LayoutStore {
    public static let currentSchemaVersion = 1

    public let fileURL: URL
    /// Layout entries dropped by the lenient decoder on the last load
    /// (unknown kind from a future version, or corrupt entry).
    public private(set) var lastLoadSkippedCount = 0

    public static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TinyWindow", isDirectory: true)
    }

    public init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        self.fileURL = dir.appendingPathComponent("layouts.json")
    }

    /// Missing file is not an error — returns [] so first-run can seed defaults.
    public func load() throws -> [Layout] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            lastLoadSkippedCount = 0
            return []
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw LayoutStoreError.ioFailure(String(describing: error))
        }
        let envelope: DecodeEnvelope
        do {
            envelope = try JSONDecoder().decode(DecodeEnvelope.self, from: data)
        } catch {
            throw LayoutStoreError.corrupted(String(describing: error))
        }
        guard envelope.schemaVersion <= Self.currentSchemaVersion else {
            throw LayoutStoreError.newerSchema(found: envelope.schemaVersion,
                                               supported: Self.currentSchemaVersion)
        }
        if envelope.schemaVersion < Self.currentSchemaVersion {
            // Future migrations start by preserving the original.
            try? FileManager.default.copyItem(
                at: fileURL,
                to: fileURL.deletingPathExtension().appendingPathExtension("json.bak"))
        }
        let layouts = envelope.layouts.compactMap(\.layout)
        lastLoadSkippedCount = envelope.layouts.count - layouts.count
        return layouts
    }

    public func save(_ layouts: [Layout]) throws {
        // Never clobber a file written by a newer version.
        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let peek = try? JSONDecoder().decode(VersionPeek.self, from: data),
           peek.schemaVersion > Self.currentSchemaVersion {
            throw LayoutStoreError.newerSchema(found: peek.schemaVersion,
                                               supported: Self.currentSchemaVersion)
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(EncodeEnvelope(
                schemaVersion: Self.currentSchemaVersion, layouts: layouts))
            try data.write(to: fileURL, options: .atomic)
        } catch let error as LayoutStoreError {
            throw error
        } catch {
            throw LayoutStoreError.ioFailure(String(describing: error))
        }
    }

    // MARK: - Envelopes

    private struct EncodeEnvelope: Encodable {
        var schemaVersion: Int
        var layouts: [Layout]
    }

    private struct VersionPeek: Decodable {
        var schemaVersion: Int
    }

    private struct DecodeEnvelope: Decodable {
        var schemaVersion: Int
        var layouts: [LenientLayout]
    }

    /// Swallows individually corrupt/unknown entries instead of failing the file.
    private struct LenientLayout: Decodable {
        let layout: Layout?
        init(from decoder: Decoder) {
            layout = try? Layout(from: decoder)
        }
    }
}
