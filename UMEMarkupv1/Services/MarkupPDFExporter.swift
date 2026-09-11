import Foundation
import PDFKit
import PencilKit
import UIKit

/// Writes a **copy** of a library PDF with visible markup baked in.
/// The imported `document.pdf` is never rewritten; live sidecar markup stays editable.
enum MarkupPDFExporter {
    enum ExportError: LocalizedError {
        case unreadablePDF
        case emptyDocument
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .unreadablePDF:
                return "Could not open the PDF to export."
            case .emptyDocument:
                return "This PDF has no pages to export."
            case .writeFailed:
                return "Could not write the marked-up PDF."
            }
        }
    }

    /// `Lecture.pdf` → `Lecture-marked.pdf`. Path-unsafe characters become `-`.
    static func markedFileName(displayName: String) -> String {
        var base = (displayName as NSString).lastPathComponent
        if base.lowercased().hasSuffix(".pdf") {
            base = String(base.dropLast(4))
        }
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        base = base.components(separatedBy: invalid).joined(separator: "-")
        base = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.contains("--") {
            base = base.replacingOccurrences(of: "--", with: "-")
        }
        if base.isEmpty {
            base = "Document"
        }
        return "\(base)-marked.pdf"
    }

    /// Flattens PDFKit annotations plus PencilKit ink / freehand highlight into a new file.
    @MainActor
    static func export(pdfURL: URL, markup: MarkupDocument, displayName: String) throws -> URL {
        let sourceData = try Data(contentsOf: pdfURL)
        guard let document = PDFDocument(data: sourceData) else {
            throw ExportError.unreadablePDF
        }
        guard document.pageCount > 0 else {
            throw ExportError.emptyDocument
        }

        MarkupRenderer.applyAll(markup, to: document)

        let destination = try makeDestinationURL(displayName: displayName)
        let data = try flattenedData(from: document, markup: markup)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private static func makeDestinationURL(displayName: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("UMEMarkupExport", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(markedFileName(displayName: displayName), isDirectory: false)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        return url
    }

    /// Replay each page (including PDFKit annotations) into a new PDF context, then
    /// composite PencilKit strokes in the same crop-box space the overlay canvas uses.
    private static func flattenedData(from document: PDFDocument, markup: MarkupDocument) throws -> Data {
        let output = NSMutableData()
        UIGraphicsBeginPDFContextToData(output, .zero, nil)
        defer { UIGraphicsEndPDFContext() }

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let crop = page.bounds(for: .cropBox)
            let pageBounds = CGRect(origin: .zero, size: displaySize(for: page, box: crop))
            guard pageBounds.width > 1, pageBounds.height > 1 else { continue }

            UIGraphicsBeginPDFPageWithInfo(pageBounds, nil)
            guard let context = UIGraphicsGetCurrentContext() else { continue }

            UIColor.white.setFill()
            context.fill(pageBounds)

            context.saveGState()
            // UIGraphics PDF contexts are UIKit-flipped. PDFPage.draw expects PDF space.
            context.translateBy(x: 0, y: pageBounds.height)
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: -crop.origin.x, y: -crop.origin.y)
            page.draw(with: .cropBox, to: context)
            context.restoreGState()

            drawPencilKitOverlay(markup, pageIndex: pageIndex, in: pageBounds)
        }

        guard output.length > 0 else {
            throw ExportError.writeFailed
        }
        return output as Data
    }

    private static func drawPencilKitOverlay(_ markup: MarkupDocument, pageIndex: Int, in pageBounds: CGRect) {
        let drawing = combinedDrawing(markup, pageIndex: pageIndex)
        guard !drawing.strokes.isEmpty else { return }
        let canvasRect = CGRect(origin: .zero, size: pageBounds.size)
        let image = drawing.image(from: canvasRect, scale: drawingScale(for: pageBounds.size))
        image.draw(in: pageBounds)
    }

    private static func combinedDrawing(_ markup: MarkupDocument, pageIndex: Int) -> PKDrawing {
        var combined = PKDrawing()
        if let data = markup.drawingData(for: pageIndex),
           let ink = try? PKDrawing(data: data) {
            combined = combined.appending(ink)
        }
        if let data = markup.highlightData(for: pageIndex),
           let highlight = try? PKDrawing(data: data) {
            combined = combined.appending(highlight)
        }
        return combined
    }

    /// Overlay canvases match the displayed page, which swaps width/height at 90° / 270°.
    private static func displaySize(for page: PDFPage, box: CGRect) -> CGSize {
        switch page.rotation {
        case 90, 270:
            return CGSize(width: box.height, height: box.width)
        default:
            return box.size
        }
    }

    /// Cap bitmap size so a large lecture page does not allocate a huge image.
    private static func drawingScale(for size: CGSize) -> CGFloat {
        let longest = max(size.width, size.height)
        guard longest > 0 else { return 2 }
        return min(2.5, max(1.5, 4096 / longest))
    }
}
