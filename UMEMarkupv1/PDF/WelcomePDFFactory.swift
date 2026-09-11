import UIKit

enum WelcomePDFFactory {
    static func makeSamplePDF() -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { context in
            renderPage1(context, bounds: bounds)
            renderPage2(context, bounds: bounds)
            renderPage3(context, bounds: bounds)
        }
    }

    private static func renderPage1(_ context: UIGraphicsPDFRendererContext, bounds: CGRect) {
        context.beginPage()
        let page = bounds.insetBy(dx: 54, dy: 64)

        drawTitle("UME Markupv1", at: page.origin)
        drawSubtitle("PDF viewer and annotator — sample page 1 of 3", at: CGPoint(x: page.minX, y: page.minY + 40))

        let body = """
        Import your own PDFs from Files or the share sheet, then mark them up while you review work or study.

        Select a tool in the bottom toolbar first.

        Tools in this version
        • Scroll — pan and pinch the PDF with a finger.
        • Highlight — paint a translucent stroke with Apple Pencil. Cover any span of a letter or word; this is not text selection.
        • Underline — drag a finger or Pencil across a passage (selection-based).
        • Ink — write with Apple Pencil. Finger still scrolls the page.
        • Note — tap a spot (finger is fine), type a short comment, and save.
        • Eraser — rub out ink or highlight strokes with Pencil, or tap an old underline/note.
        • Bookmark — star the current page, then jump back from the bookmark menu.

        On iPad, Ink, Highlight, and Eraser accept Apple Pencil only. A resting hand or finger pans the PDF instead of leaving marks.

        Annotations and bookmarks are stored next to each imported PDF. Leave this document and reopen it: your marks should still be here.
        """
        drawBody(body, in: CGRect(x: page.minX, y: page.minY + 78, width: page.width, height: page.height - 120))
        drawFooter(in: page)
    }

    private static func renderPage2(_ context: UIGraphicsPDFRendererContext, bounds: CGRect) {
        context.beginPage()
        let page = bounds.insetBy(dx: 54, dy: 64)

        drawTitle("Freehand highlight", at: page.origin)
        drawSubtitle("Paint any span — not whole words", at: CGPoint(x: page.minX, y: page.minY + 40))

        let body = """
        Select Highlight, then drag Apple Pencil across only part of this sentence. You should be able to mark “part of this” without snapping to the whole line.

        Try a short stroke over a single letter, then a longer stroke across several words. The wash is a highlighter brush, not a selection rectangle.

        Switch to Ink and write a word. Finger-drag on this page should scroll, not draw.

        Switch to Eraser and rub the highlight stroke. It should disappear. Leave and reopen: remaining ink and highlights persist.
        """
        drawBody(body, in: CGRect(x: page.minX, y: page.minY + 78, width: page.width, height: page.height - 120))
        drawFooter(in: page)
    }

    private static func renderPage3(_ context: UIGraphicsPDFRendererContext, bounds: CGRect) {
        context.beginPage()
        let page = bounds.insetBy(dx: 54, dy: 64)

        drawTitle("Page bookmarks", at: page.origin)
        drawSubtitle("Mark a page, jump back later", at: CGPoint(x: page.minX, y: page.minY + 40))

        let body = """
        Tap the bookmark icon in the toolbar, then choose Bookmark This Page. The icon fills when this page is saved.

        Scroll to page 1 or 2, open the bookmark menu, and jump back here.

        Remove the bookmark the same way. Close the document and reopen: bookmarked pages are listed again. They live in markup.json next to the PDF.

        This sample is a generated placeholder. It does not contain personal documents.
        """
        drawBody(body, in: CGRect(x: page.minX, y: page.minY + 78, width: page.width, height: page.height - 120))
        drawFooter(in: page)
    }

    private static func drawTitle(_ title: String, at point: CGPoint) {
        title.draw(
            at: point,
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 28, weight: .semibold),
                .foregroundColor: UIColor.black
            ]
        )
    }

    private static func drawSubtitle(_ subtitle: String, at point: CGPoint) {
        subtitle.draw(
            at: point,
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: UIColor.darkGray
            ]
        )
    }

    private static func drawBody(_ body: String, in rect: CGRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        body.draw(
            with: rect,
            options: [.usesLineFragmentOrigin],
            attributes: [
                .font: UIFont.systemFont(ofSize: 13),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph
            ],
            context: nil
        )
    }

    private static func drawFooter(in page: CGRect) {
        let footer = "UME Markupv1  ·  local-first  ·  iCloud Documents"
        footer.draw(
            at: CGPoint(x: page.minX, y: page.maxY - 18),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.gray
            ]
        )
    }
}
