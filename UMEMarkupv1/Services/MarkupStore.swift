import Foundation

enum MarkupStore {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func loadMarkup(at url: URL) -> MarkupDocument {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let document = try? decoder.decode(MarkupDocument.self, from: data)
        else {
            return .empty
        }
        return document
    }

    static func saveMarkup(_ markup: MarkupDocument, to url: URL) throws {
        var payload = markup
        payload.version = MarkupDocument.currentVersion
        let data = try encoder.encode(payload)
        try atomicallyWrite(data, to: url)
    }

    static func loadMeta(at url: URL) -> DocumentMeta? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(DocumentMeta.self, from: data)
    }

    static func saveMeta(_ meta: DocumentMeta, to url: URL) throws {
        let data = try encoder.encode(meta)
        try atomicallyWrite(data, to: url)
    }

    static func atomicallyWrite(_ data: Data, to url: URL) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let temp = folder.appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: temp, options: [.atomic])
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: url)
        }
    }
}
