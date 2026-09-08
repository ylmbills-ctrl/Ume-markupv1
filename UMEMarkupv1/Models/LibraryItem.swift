import Foundation

struct LibraryItem: Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var importedAt: Date
    var lastOpenedAt: Date
    var folderURL: URL
    var isDownloading: Bool

    var pdfURL: URL {
        folderURL.appendingPathComponent(DocumentFile.document, isDirectory: false)
    }

    var markupURL: URL {
        folderURL.appendingPathComponent(DocumentFile.markup, isDirectory: false)
    }

    var metaURL: URL {
        folderURL.appendingPathComponent(DocumentFile.meta, isDirectory: false)
    }
}

enum DocumentFile {
    static let document = "document.pdf"
    static let markup = "markup.json"
    static let meta = "meta.json"
}
