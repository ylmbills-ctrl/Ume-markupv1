import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class DocumentLibrary {
    private(set) var items: [LibraryItem] = []
    private(set) var usesICloud = false
    private(set) var storageRoot: URL
    var searchText = ""
    var errorMessage: String?
    var lastImportedID: UUID?

    @ObservationIgnored
    private var metadataQuery: NSMetadataQuery?
    @ObservationIgnored
    private var didStartWatchers = false

    var filteredItems: [LibraryItem] {
        let sorted = items.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sorted }
        return sorted.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    init() {
        let resolved = StorageRoot.resolve()
        storageRoot = resolved.root
        usesICloud = resolved.usesICloud
        refresh()
        startWatchers()
    }

    func refresh() {
        let resolved = StorageRoot.resolve()
        storageRoot = resolved.root
        usesICloud = resolved.usesICloud

        let fileManager = FileManager.default
        guard let folders = try? fileManager.contentsOfDirectory(
            at: storageRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isUbiquitousItemKey],
            options: [.skipsHiddenFiles]
        ) else {
            items = []
            return
        }

        var scanned: [LibraryItem] = []
        for folder in folders {
            let isDirectory = (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { continue }
            requestDownloadIfNeeded(folder)

            let metaURL = folder.appendingPathComponent(DocumentFile.meta, isDirectory: false)
            let pdfURL = folder.appendingPathComponent(DocumentFile.document, isDirectory: false)
            let pdfReady = fileManager.fileExists(atPath: pdfURL.path)

            guard let meta = MarkupStore.loadMeta(at: metaURL) ?? inferredMeta(from: folder, pdfReady: pdfReady) else {
                continue
            }

            if !pdfReady {
                try? fileManager.startDownloadingUbiquitousItem(at: pdfURL)
            }

            scanned.append(
                LibraryItem(
                    id: meta.id,
                    displayName: meta.displayName,
                    importedAt: meta.importedAt,
                    lastOpenedAt: meta.lastOpenedAt,
                    folderURL: folder,
                    isDownloading: !pdfReady
                )
            )
        }
        items = scanned
    }

    @discardableResult
    func importPDF(from incoming: URL, displayName: String? = nil) -> LibraryItem? {
        do {
            let item = try copyIntoLibrary(from: incoming, displayName: displayName)
            if !items.contains(where: { $0.id == item.id }) {
                items.append(item)
            }
            errorMessage = nil
            lastImportedID = item.id
            return item
        } catch {
            errorMessage = "Could not import that PDF. \(error.localizedDescription)"
            return nil
        }
    }

    func importFromExternalURL(_ url: URL) {
        guard isPDF(url) else { return }
        importPDF(from: url)
    }

    func importInboxIfNeeded() {
        let inbox = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Inbox", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for file in files where isPDF(file) {
            importPDF(from: file)
            try? FileManager.default.removeItem(at: file)
        }
    }

    @discardableResult
    func addSampleDocument() -> LibraryItem? {
        do {
            let data = WelcomePDFFactory.makeSamplePDF()
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("UME Markupv1 Sample.pdf")
            try data.write(to: temp, options: [.atomic])
            let item = importPDF(from: temp, displayName: "UME Markupv1 Sample.pdf")
            try? FileManager.default.removeItem(at: temp)
            return item
        } catch {
            errorMessage = "Could not create the sample PDF. \(error.localizedDescription)"
            return nil
        }
    }

    func delete(_ item: LibraryItem) {
        do {
            if FileManager.default.fileExists(atPath: item.folderURL.path) {
                try FileManager.default.removeItem(at: item.folderURL)
            }
            items.removeAll { $0.id == item.id }
        } catch {
            errorMessage = "Could not delete that document. \(error.localizedDescription)"
        }
    }

    func markOpened(_ item: LibraryItem) {
        let meta = DocumentMeta(
            id: item.id,
            displayName: item.displayName,
            importedAt: item.importedAt,
            lastOpenedAt: Date()
        )
        do {
            try MarkupStore.saveMeta(meta, to: item.metaURL)
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].lastOpenedAt = meta.lastOpenedAt
            }
        } catch {
            errorMessage = "Could not update last opened time."
        }
    }

    func item(id: UUID) -> LibraryItem? {
        items.first { $0.id == id }
    }

    private func copyIntoLibrary(from incoming: URL, displayName: String?) throws -> LibraryItem {
        let scoped = incoming.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                incoming.stopAccessingSecurityScopedResource()
            }
        }

        requestDownloadIfNeeded(incoming)
        let data = try Data(contentsOf: incoming)
        guard !data.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let id = UUID()
        let folder = storageRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let pdfURL = folder.appendingPathComponent(DocumentFile.document, isDirectory: false)
        try data.write(to: pdfURL, options: [.atomic])

        let name = sanitizedFileName(displayName ?? incoming.lastPathComponent)
        let now = Date()
        let meta = DocumentMeta(id: id, displayName: name, importedAt: now, lastOpenedAt: now)
        try MarkupStore.saveMeta(meta, to: folder.appendingPathComponent(DocumentFile.meta))
        try MarkupStore.saveMarkup(.empty, to: folder.appendingPathComponent(DocumentFile.markup))

        return LibraryItem(
            id: id,
            displayName: name,
            importedAt: now,
            lastOpenedAt: now,
            folderURL: folder,
            isDownloading: false
        )
    }

    private func sanitizedFileName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Document.pdf" : trimmed
        return name.replacingOccurrences(of: "/", with: "-")
    }

    private func isPDF(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "pdf" { return true }
        if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .pdf) {
            return true
        }
        return false
    }

    private func inferredMeta(from folder: URL, pdfReady: Bool) -> DocumentMeta? {
        guard let id = UUID(uuidString: folder.lastPathComponent), pdfReady else { return nil }
        let values = try? folder.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        let created = values?.creationDate ?? Date()
        return DocumentMeta(
            id: id,
            displayName: "Document.pdf",
            importedAt: created,
            lastOpenedAt: values?.contentModificationDate ?? created
        )
    }

    private func requestDownloadIfNeeded(_ url: URL) {
        let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ])
        guard values?.isUbiquitousItem == true else { return }
        if values?.ubiquitousItemDownloadingStatus != URLUbiquitousItemDownloadingStatus.current {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
    }

    private func startWatchers() {
        guard !didStartWatchers else { return }
        didStartWatchers = true

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, "*")
        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        query.start()
        metadataQuery = query
    }
}
