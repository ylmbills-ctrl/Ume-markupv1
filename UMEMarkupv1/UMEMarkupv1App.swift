import SwiftUI

@main
struct UMEMarkupv1App: App {
    @State private var library = DocumentLibrary()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(library)
                .onOpenURL { url in
                    library.importFromExternalURL(url)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                library.refresh()
                library.importInboxIfNeeded()
            case .inactive, .background:
                NotificationCenter.default.post(name: .umeSaveMarkupNow, object: nil)
            @unknown default:
                break
            }
        }
    }
}

extension Notification.Name {
    static let umeSaveMarkupNow = Notification.Name("ume.saveMarkupNow")
}
