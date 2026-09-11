import SwiftUI

struct PDFViewerScreen: View {
    let itemID: UUID

    @Environment(DocumentLibrary.self) private var library
    @Environment(\.scenePhase) private var scenePhase

    @State private var markup = MarkupDocument.empty
    @State private var tool: MarkupTool = .hand
    @State private var color = MarkupPalette.defaultHighlight
    @State private var currentPage = 1
    @State private var pageCount = 1
    @State private var noteDraft = ""
    @State private var pendingNote: (pageIndex: Int, anchor: CGPoint)?
    @State private var didLoad = false
    @State private var bridge = MarkupBridge()
    @State private var sharePayload: SharePayload?
    @State private var isExporting = false

    private var item: LibraryItem? {
        library.item(id: itemID)
    }

    var body: some View {
        Group {
            if let item {
                if item.isDownloading {
                    ContentUnavailableView(
                        "Downloading from iCloud",
                        systemImage: "icloud.and.arrow.down",
                        description: Text("This PDF is still arriving. Pull to refresh the library in a moment.")
                    )
                } else {
                    viewer(for: item)
                }
            } else {
                ContentUnavailableView(
                    "Document Unavailable",
                    systemImage: "doc.questionmark",
                    description: Text("It may have been deleted or is still syncing.")
                )
            }
        }
        .navigationTitle(item?.displayName ?? "Document")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    shareMarkedPDF()
                } label: {
                    if isExporting {
                        ProgressView()
                    } else {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(item == nil || item?.isDownloading == true || isExporting)
                .accessibilityLabel("Share marked PDF")
            }
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(url: payload.url)
        }
        .onAppear(perform: loadIfNeeded)
        .onChange(of: itemID) { _, _ in
            didLoad = false
            markup = .empty
            loadIfNeeded()
        }
        .onDisappear(perform: persist)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                persist()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .umeSaveMarkupNow)) { _ in
            persist()
        }
        .sheet(isPresented: Binding(
            get: { pendingNote != nil },
            set: { if !$0 { pendingNote = nil } }
        )) {
            NoteEditorView(
                text: $noteDraft,
                onCancel: {
                    pendingNote = nil
                    noteDraft = ""
                },
                onSave: saveNote
            )
        }
    }

    private func viewer(for item: LibraryItem) -> some View {
        VStack(spacing: 0) {
            PDFMarkupView(
                pdfURL: item.pdfURL,
                markup: $markup,
                tool: $tool,
                color: $color,
                currentPage: $currentPage,
                pageCount: $pageCount,
                onRequestNote: { pageIndex, point in
                    noteDraft = ""
                    pendingNote = (pageIndex, point)
                },
                onMarkupChanged: persist,
                bridge: bridge
            )
            .ignoresSafeArea(edges: .bottom)

            MarkupToolbar(
                tool: $tool,
                color: $color,
                pageLabel: "Page \(currentPage) of \(max(pageCount, 1))",
                isCurrentPageBookmarked: markup.isPageBookmarked(currentPage - 1),
                bookmarkedPageNumbers: markup.bookmarkedPages.map { $0 + 1 },
                onToggleBookmark: toggleCurrentPageBookmark,
                onJumpToBookmark: jumpToBookmarkedPage,
                onUndo: undo
            )
        }
        .onChange(of: tool) { _, newTool in
            if newTool == .ink, color.hexString() == MarkupPalette.defaultHighlight.hexString() {
                color = MarkupPalette.defaultInk
            }
            if newTool == .highlight, color.hexString() == MarkupPalette.defaultInk.hexString() {
                color = MarkupPalette.defaultHighlight
            }
        }
    }

    private func loadIfNeeded() {
        guard !didLoad, let item else { return }
        didLoad = true
        markup = MarkupStore.loadMarkup(at: item.markupURL)
        library.markOpened(item)
    }

    private func persist() {
        guard let item else { return }
        bridge.captureInk()
        do {
            try MarkupStore.saveMarkup(markup, to: item.markupURL)
        } catch {
            library.errorMessage = "Could not save annotations. \(error.localizedDescription)"
        }
    }

    private func saveNote() {
        let text = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pendingNote, !text.isEmpty else { return }
        bridge.addNote(text: text, pageIndex: pendingNote.pageIndex, anchor: pendingNote.anchor)
        self.pendingNote = nil
        noteDraft = ""
    }

    private func undo() {
        bridge.undo()
    }

    private func toggleCurrentPageBookmark() {
        guard pageCount > 0, currentPage >= 1 else { return }
        markup.toggleBookmark(pageIndex: currentPage - 1)
        persist()
    }

    private func jumpToBookmarkedPage(_ pageNumber: Int) {
        bridge.goToPage(pageNumber - 1)
    }

    private func shareMarkedPDF() {
        guard let item, !isExporting else { return }
        persist()
        isExporting = true
        do {
            let url = try MarkupPDFExporter.export(
                pdfURL: item.pdfURL,
                markup: markup,
                displayName: item.displayName
            )
            sharePayload = SharePayload(url: url)
        } catch {
            library.errorMessage = error.localizedDescription
        }
        isExporting = false
    }
}
