import Foundation

extension Notification.Name {
    nonisolated static var vaultStorageDidMutate: Notification.Name {
        Notification.Name("SealNoteVaultStorageDidMutate")
    }
}

nonisolated func postVaultStorageMutation(at url: URL) {
    NotificationCenter.default.post(
        name: .vaultStorageDidMutate,
        object: nil,
        userInfo: ["path": url.path]
    )
}

nonisolated enum StorageError: Error, LocalizedError {
    case iCloudUnavailable
    case directoryCreationFailed
    case fileWriteFailed
    case fileReadFailed
    case fileDeleteFailed
    case fileNotFound
    case fileMoveFailed
    case atomicWriteFailed
    case invalidData
    case iCloudDownloadPending

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable: return "iCloud is not available"
        case .directoryCreationFailed: return "Failed to create directory"
        case .fileWriteFailed: return "Failed to write file"
        case .fileReadFailed: return "Failed to read file"
        case .fileDeleteFailed: return "Failed to delete file"
        case .fileNotFound: return "File not found"
        case .fileMoveFailed: return "Failed to move file"
        case .atomicWriteFailed: return "Atomic write failed"
        case .invalidData: return "Invalid data"
        case .iCloudDownloadPending: return "iCloud file is still downloading"
        }
    }
}

protocol VaultStorage: Sendable {
    nonisolated var isAvailable: Bool { get }
    nonisolated var containerURL: URL? { get }

    nonisolated func initializeVault() async throws

    nonisolated func loadIndex() throws -> NoteIndex?
    nonisolated func saveIndex(_ index: NoteIndex) throws

    nonisolated func listMarkdownFiles(in location: NoteFileLocation) throws -> [URL]
    nonisolated func loadMarkdownFile(at url: URL) throws -> MarkdownNoteFile
    nonisolated func saveMarkdownFile(_ file: MarkdownNoteFile, at url: URL) throws

    nonisolated func moveFile(from srcURL: URL, to dstURL: URL) throws
    nonisolated func permanentlyDeleteFile(at url: URL) throws

    nonisolated func createConflictCopy(for url: URL) throws -> URL
    nonisolated func emptyTrash() throws
}

extension VaultStorage {
    nonisolated func noteFileURL(for noteId: String) -> URL? {
        guard let container = containerURL else { return nil }
        return container.appendingPathComponent("\(noteId).md")
    }

    nonisolated func trashFileURL(for noteId: String) -> URL? {
        guard let container = containerURL else { return nil }
        return container.appendingPathComponent("trash").appendingPathComponent("\(noteId).md")
    }

    nonisolated var notesIndexURL: URL? {
        containerURL?.appendingPathComponent("notes.json")
    }

    nonisolated func listMarkdownFiles(in location: NoteFileLocation) throws -> [URL] {
        guard let container = containerURL else {
            throw StorageError.iCloudUnavailable
        }
        let dirURL = location == .notes ? container : container.appendingPathComponent(location.rawValue)
        return try listMarkdownFilesInDirectory(dirURL)
    }

    nonisolated func permanentlyDeleteFile(at url: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw StorageError.fileNotFound
        }
        try fm.removeItem(at: url)
        postVaultStorageMutation(at: url)
    }

    nonisolated func moveFile(from srcURL: URL, to dstURL: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: srcURL.path) else {
            throw StorageError.fileNotFound
        }
        if fm.fileExists(atPath: dstURL.path) {
            try? fm.removeItem(at: dstURL)
        }
        let dstDir = dstURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: dstDir.path) {
            try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
        }
        try fm.moveItem(at: srcURL, to: dstURL)
        postVaultStorageMutation(at: dstURL)
    }

    nonisolated func emptyTrash() throws {
        guard let trashURL = containerURL?.appendingPathComponent("trash") else {
            throw StorageError.iCloudUnavailable
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: trashURL.path) else { return }
        let contents = try fm.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        for file in contents {
            if file.lastPathComponent.hasSuffix(".md") {
                try? fm.removeItem(at: file)
            }
        }
        postVaultStorageMutation(at: trashURL)
    }

    nonisolated func createConflictCopy(for url: URL) throws -> URL {
        guard let container = containerURL else {
            throw StorageError.iCloudUnavailable
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = url.deletingPathExtension().lastPathComponent
        let conflictFilename = "\(filename)-conflict-\(timestamp).md"
        let conflictDir = container.appendingPathComponent("conflicts")
        let conflictURL = conflictDir.appendingPathComponent(conflictFilename)

        let fm = FileManager.default
        if !fm.fileExists(atPath: conflictDir.path) {
            try fm.createDirectory(at: conflictDir, withIntermediateDirectories: true)
        }
        try fm.copyItem(at: url, to: conflictURL)
        postVaultStorageMutation(at: conflictURL)
        return conflictURL
    }

    nonisolated internal func listMarkdownFilesInDirectory(_ dirURL: URL) throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dirURL.path) else { return [] }

        let contents = try fm.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return contents
            .filter { $0.lastPathComponent.hasSuffix(".md") }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return date1 > date2
            }
    }
}
