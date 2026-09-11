import Foundation

enum StorageRoot {
    static let iCloudContainerID = "iCloud.com.ume.markupv1"
    static let libraryFolderName = "Library"

    /// Resolves the document library folder. v1 defaults to Application Support
    /// so a Personal Team build needs no iCloud entitlement. If a paid team later
    /// adds the iCloud Documents capability and the OS vends a ubiquity container,
    /// that folder is used instead.
    static func resolve() -> (root: URL, usesICloud: Bool) {
        let fileManager = FileManager.default
        let local = localLibraryURL()
        try? fileManager.createDirectory(at: local, withIntermediateDirectories: true)

        if let ubiquity = fileManager.url(forUbiquityContainerIdentifier: iCloudContainerID) {
            let documents = ubiquity.appendingPathComponent("Documents", isDirectory: true)
            let library = documents.appendingPathComponent(libraryFolderName, isDirectory: true)
            try? fileManager.createDirectory(at: library, withIntermediateDirectories: true)
            migrateLocalIfNeeded(to: library)
            return (library, true)
        }

        return (local, false)
    }

    static func localLibraryURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UMEMarkupv1", isDirectory: true)
            .appendingPathComponent(libraryFolderName, isDirectory: true)
    }

    /// One-time copy of any locally saved documents into iCloud the first time
    /// the ubiquity container becomes available.
    private static func migrateLocalIfNeeded(to iCloudLibrary: URL) {
        let marker = iCloudLibrary.appendingPathComponent(".migrated-local", isDirectory: false)
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: marker.path) else { return }

        let local = localLibraryURL()
        guard fileManager.fileExists(atPath: local.path) else {
            fileManager.createFile(atPath: marker.path, contents: Data())
            return
        }

        if let folders = try? fileManager.contentsOfDirectory(
            at: local,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for folder in folders {
                let destination = iCloudLibrary.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
                if !fileManager.fileExists(atPath: destination.path) {
                    try? fileManager.copyItem(at: folder, to: destination)
                }
            }
        }
        fileManager.createFile(atPath: marker.path, contents: Data())
    }
}
