import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(DocumentLibrary.self) private var library
    @State private var selectedID: LibraryItem.ID?
    @State private var isImporterPresented = false
    @State private var itemPendingDelete: LibraryItem?

    var body: some View {
        @Bindable var library = library

        NavigationSplitView {
            documentList
                .navigationTitle("Library")
                .searchable(text: $library.searchText, prompt: "Search filenames")
                .toolbar { libraryToolbar }
                .refreshable { library.refresh() }
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
        } detail: {
            if let selectedID, let item = library.item(id: selectedID) {
                PDFViewerScreen(itemID: item.id)
            } else {
                ContentUnavailableView(
                    "Select a Document",
                    systemImage: "doc.richtext",
                    description: Text("Import a PDF or open the sample page to start marking up.")
                )
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                var lastImported: LibraryItem?
                for url in urls {
                    lastImported = library.importPDF(from: url) ?? lastImported
                }
                if let lastImported {
                    selectedID = lastImported.id
                }
            case .failure(let error):
                library.errorMessage = error.localizedDescription
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { if !$0 { library.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { library.errorMessage = nil }
        } message: {
            Text(library.errorMessage ?? "")
        }
        .confirmationDialog(
            "Delete this document from the library? Annotations are removed too.",
            isPresented: Binding(
                get: { itemPendingDelete != nil },
                set: { if !$0 { itemPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let item = itemPendingDelete {
                    if selectedID == item.id {
                        selectedID = nil
                    }
                    library.delete(item)
                }
                itemPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                itemPendingDelete = nil
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: library.lastImportedID) { _, id in
            if let id {
                selectedID = id
            }
        }
    }

    @ViewBuilder
    private var documentList: some View {
        let rows = library.filteredItems
        if rows.isEmpty {
            emptyState
        } else {
            List(selection: $selectedID) {
                Section(library.usesICloud ? "iCloud sync on" : "Saved on this device only") {
                    ForEach(rows) { item in
                        LibraryRow(item: item)
                            .tag(item.id)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    itemPendingDelete = item
                                }
                            }
                            .disabled(item.isDownloading)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                library.searchText.isEmpty ? "No PDFs yet" : "No matching filenames",
                systemImage: library.searchText.isEmpty ? "doc.badge.plus" : "magnifyingglass"
            )
        } description: {
            Text(
                library.searchText.isEmpty
                    ? "Import a PDF from Files, share one into this app, or add the sample page. \(library.usesICloud ? "iCloud sync is on." : "Documents stay on this device until iCloud is enabled.")"
                    : "Try a different filename."
            )
        } actions: {
            if library.searchText.isEmpty {
                Button("Import PDF") { isImporterPresented = true }
                Button("Add Sample PDF") {
                    if let item = library.addSampleDocument() {
                        selectedID = item.id
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Import PDF…", systemImage: "square.and.arrow.down") {
                    isImporterPresented = true
                }
                Button("Add Sample PDF", systemImage: "doc.badge.plus") {
                    if let item = library.addSampleDocument() {
                        selectedID = item.id
                    }
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .accessibilityLabel("Add document")
        }
    }
}

private struct LibraryRow: View {
    let item: LibraryItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.isDownloading ? "icloud.and.arrow.down" : "doc.richtext")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text(item.isDownloading ? "Waiting for iCloud…" : lastOpenedLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var lastOpenedLabel: String {
        "Last opened \(Self.relative.localizedString(for: item.lastOpenedAt, relativeTo: Date()))"
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
