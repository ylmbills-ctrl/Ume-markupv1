import UIKit

enum WelcomePDFFactory {
    static func makeSamplePDF() -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { context in
            context.beginPage()
            let page = bounds.insetBy(dx: 54, dy: 64)

            let title = "UME Markupv1"
            title.draw(
                at: CGPoint(x: page.minX, y: page.minY),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 28, weight: .semibold),
                    .foregroundColor: UIColor.black
                ]
            )

            let subtitle = "PDF viewer and annotator — sample page"
            subtitle.draw(
                at: CGPoint(x: page.minX, y: page.minY + 40),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                    .foregroundColor: UIColor.darkGray
                ]
            )

            let body = """
            Import your own PDFs from Files or the share sheet, then mark them up while you review work or study.

            Select a tool in the bottom toolbar first. Scroll does not mark the page.

            Tools in this version
            • Scroll — pan and pinch the PDF. Apple Pencil will not write in this mode.
            • Highlight — drag Pencil or finger over text (or any region) to mark a passage.
            • Underline — same gesture, with an underline instead of a wash.
            • Ink — draw with Apple Pencil or a finger. Switch back to Scroll to pan.
            • Note — tap a spot on the page, type a short comment, and save.
            • Eraser — tap a highlight, underline, or note to remove it, or rub out ink.

            Annotations are stored next to each imported PDF. Leave this document and reopen it: your marks should still be here.

            When iCloud is enabled for this app, the same library and annotations appear on iPhone and iPad signed into the same Apple ID.

            This sample is a generated placeholder. It does not contain personal documents.
            """

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 5
            body.draw(
                with: CGRect(x: page.minX, y: page.minY + 78, width: page.width, height: page.height - 120),
                options: [.usesLineFragmentOrigin],
                attributes: [
                    .font: UIFont.systemFont(ofSize: 13),
                    .foregroundColor: UIColor.black,
                    .paragraphStyle: paragraph
                ],
                context: nil
            )

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
}
