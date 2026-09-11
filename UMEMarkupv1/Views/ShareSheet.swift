import SwiftUI
import UIKit

struct SharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

/// iOS share sheet. Configures the iPad popover source so presentation does not crash.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        if let popover = controller.popoverPresentationController {
            popover.sourceView = controller.view
            let bounds = controller.view.bounds
            popover.sourceRect = CGRect(x: bounds.midX, y: 8, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
    }
}
