import Foundation
import SwiftUI
import PDFKit

struct CodableRect: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct CodablePoint: Codable, Hashable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

enum MarkupKind: String, Codable, Hashable {
    case highlight
    case underline
    case note
}

struct MarkupRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var pageIndex: Int
    var kind: MarkupKind
    var colorHex: String
    var rects: [CodableRect]
    var text: String?
    var anchor: CodablePoint?

    init(
        id: UUID = UUID(),
        pageIndex: Int,
        kind: MarkupKind,
        colorHex: String,
        rects: [CodableRect] = [],
        text: String? = nil,
        anchor: CodablePoint? = nil
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.kind = kind
        self.colorHex = colorHex
        self.rects = rects
        self.text = text
        self.anchor = anchor
    }
}

struct InkPage: Codable, Hashable {
    var pageIndex: Int
    var drawingBase64: String
}

struct MarkupDocument: Codable, Hashable {
    var version: Int
    var annotations: [MarkupRecord]
    var inkPages: [InkPage]
    /// Freehand highlighter strokes (`PKInkingTool.marker`), stored apart from pen ink.
    var highlightPages: [InkPage]
    /// 0-based PDF page indices the reader bookmarked.
    var bookmarkedPages: [Int]

    static let currentVersion = 2

    static var empty: MarkupDocument {
        MarkupDocument(
            version: currentVersion,
            annotations: [],
            inkPages: [],
            highlightPages: [],
            bookmarkedPages: []
        )
    }

    enum CodingKeys: String, CodingKey {
        case version
        case annotations
        case inkPages
        case highlightPages
        case bookmarkedPages
    }

    init(
        version: Int,
        annotations: [MarkupRecord],
        inkPages: [InkPage],
        highlightPages: [InkPage] = [],
        bookmarkedPages: [Int] = []
    ) {
        self.version = version
        self.annotations = annotations
        self.inkPages = inkPages
        self.highlightPages = highlightPages
        self.bookmarkedPages = bookmarkedPages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        annotations = try container.decodeIfPresent([MarkupRecord].self, forKey: .annotations) ?? []
        inkPages = try container.decodeIfPresent([InkPage].self, forKey: .inkPages) ?? []
        highlightPages = try container.decodeIfPresent([InkPage].self, forKey: .highlightPages) ?? []
        let rawBookmarks = try container.decodeIfPresent([Int].self, forKey: .bookmarkedPages) ?? []
        bookmarkedPages = Self.normalizedBookmarks(rawBookmarks)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(annotations, forKey: .annotations)
        try container.encode(inkPages, forKey: .inkPages)
        try container.encode(highlightPages, forKey: .highlightPages)
        try container.encode(Self.normalizedBookmarks(bookmarkedPages), forKey: .bookmarkedPages)
    }

    mutating func upsertInk(pageIndex: Int, drawingData: Data) {
        upsert(pageIndex: pageIndex, drawingData: drawingData, into: &inkPages)
    }

    mutating func upsertHighlight(pageIndex: Int, drawingData: Data) {
        upsert(pageIndex: pageIndex, drawingData: drawingData, into: &highlightPages)
    }

    func drawingData(for pageIndex: Int) -> Data? {
        data(in: inkPages, pageIndex: pageIndex)
    }

    func highlightData(for pageIndex: Int) -> Data? {
        data(in: highlightPages, pageIndex: pageIndex)
    }

    func isPageBookmarked(_ pageIndex: Int) -> Bool {
        bookmarkedPages.contains(pageIndex)
    }

    mutating func toggleBookmark(pageIndex: Int) {
        guard pageIndex >= 0 else { return }
        if let existing = bookmarkedPages.firstIndex(of: pageIndex) {
            bookmarkedPages.remove(at: existing)
        } else {
            bookmarkedPages.append(pageIndex)
        }
        bookmarkedPages = Self.normalizedBookmarks(bookmarkedPages)
    }

    private mutating func upsert(pageIndex: Int, drawingData: Data, into pages: inout [InkPage]) {
        pages.removeAll { $0.pageIndex == pageIndex }
        if !drawingData.isEmpty {
            pages.append(InkPage(pageIndex: pageIndex, drawingBase64: drawingData.base64EncodedString()))
        }
    }

    private func data(in pages: [InkPage], pageIndex: Int) -> Data? {
        guard let page = pages.first(where: { $0.pageIndex == pageIndex }) else { return nil }
        return Data(base64Encoded: page.drawingBase64)
    }

    private static func normalizedBookmarks(_ pages: [Int]) -> [Int] {
        Array(Set(pages.filter { $0 >= 0 })).sorted()
    }
}

struct DocumentMeta: Codable, Hashable {
    var id: UUID
    var displayName: String
    var importedAt: Date
    var lastOpenedAt: Date
}

enum MarkupRenderer {
    static func apply(_ record: MarkupRecord, to page: PDFPage) {
        let color = UIColor(hex: record.colorHex)

        switch record.kind {
        case .highlight, .underline:
            let type: PDFAnnotationSubtype = record.kind == .highlight ? .highlight : .underline
            for rect in record.rects.map(\.cgRect) where !rect.isNull && !rect.isEmpty {
                let annotation = PDFAnnotation(bounds: rect, forType: type, withProperties: nil)
                annotation.color = record.kind == .highlight ? color.withAlphaComponent(0.45) : color
                annotation.userName = record.id.uuidString
                page.addAnnotation(annotation)
            }
        case .note:
            let point = record.anchor?.cgPoint ?? .zero
            let bounds = CGRect(x: point.x - 12, y: point.y - 10, width: 24, height: 24)
            let annotation = PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil)
            annotation.contents = record.text ?? ""
            annotation.color = color
            annotation.userName = record.id.uuidString
            page.addAnnotation(annotation)
        }
    }

    static func remove(id: UUID, from page: PDFPage) {
        let token = id.uuidString
        for annotation in page.annotations where annotation.userName == token {
            page.removeAnnotation(annotation)
        }
    }

    static func applyAll(_ markup: MarkupDocument, to document: PDFDocument) {
        for record in markup.annotations {
            guard record.pageIndex >= 0, record.pageIndex < document.pageCount,
                  let page = document.page(at: record.pageIndex) else { continue }
            apply(record, to: page)
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let r, g, b, a: Double
        switch cleaned.count {
        case 8:
            r = Double((value & 0xFF00_0000) >> 24) / 255
            g = Double((value & 0x00FF_0000) >> 16) / 255
            b = Double((value & 0x0000_FF00) >> 8) / 255
            a = Double(value & 0x0000_00FF) / 255
        case 6:
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
            a = 1
        default:
            r = 1; g = 0.92; b = 0.23; a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    func hexString() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return "FFEB3B" }
        return String(
            format: "%02X%02X%02X",
            Int((r * 255).rounded()),
            Int((g * 255).rounded()),
            Int((b * 255).rounded())
        )
    }
}

extension UIColor {
    convenience init(hex: String) {
        self.init(Color(hex: hex))
    }
}
