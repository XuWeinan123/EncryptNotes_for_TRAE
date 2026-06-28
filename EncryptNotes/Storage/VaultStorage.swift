import Foundation

enum StorageError: Error, LocalizedError {
    case iCloudUnavailable
    case directoryCreationFailed
    case fileWriteFailed
    case fileReadFailed
    case fileDeleteFailed
    case fileNotFound
    case fileMoveFailed
    case atomicWriteFailed
    case invalidData

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
        }
    }
}

protocol VaultStorage: Sendable {
    var isAvailable: Bool { get }
    var containerURL: URL? { get }

    func initializeVault() async throws

    func loadIndex() throws -> NoteIndex?
    func saveIndex(_ index: NoteIndex) throws

    func listMarkdownFiles(in location: NoteFileLocation) throws -> [URL]
    func loadMarkdownFile(at url: URL) throws -> MarkdownNoteFile
    func saveMarkdownFile(_ file: MarkdownNoteFile, at url: URL) throws

    func moveFile(from srcURL: URL, to dstURL: URL) throws
    func permanentlyDeleteFile(at url: URL) throws

    func createConflictCopy(for url: URL) throws -> URL
    func emptyTrash() throws
}

extension VaultStorage {
    func noteFileURL(for noteId: String) -> URL? {
        guard let container = containerURL else { return nil }
        return container.appendingPathComponent("notes").appendingPathComponent("\(noteId).md")
    }

    func trashFileURL(for noteId: String) -> URL? {
        guard let container = containerURL else { return nil }
        return container.appendingPathComponent("trash").appendingPathComponent("\(noteId).md")
    }

    var notesIndexURL: URL? {
        containerURL?.appendingPathComponent("notes.json")
    }

    func listMarkdownFiles(in location: NoteFileLocation) throws -> [URL] {
        guard let dirURL = containerURL?.appendingPathComponent(location.rawValue) else {
            throw StorageError.iCloudUnavailable
        }
        return try listMarkdownFilesInDirectory(dirURL)
    }

    func permanentlyDeleteFile(at url: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw StorageError.fileNotFound
        }
        try fm.removeItem(at: url)
    }

    func moveFile(from srcURL: URL, to dstURL: URL) throws {
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
    }

    func emptyTrash() throws {
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
    }

    func createConflictCopy(for url: URL) throws -> URL {
        guard let container = containerURL else {
            throw StorageError.iCloudUnavailable
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = url.deletingPathExtension().lastPathComponent
        let conflictFilename = "\(filename)-conflict-\(timestamp).md"
        let conflictURL = container.appendingPathComponent("notes").appendingPathComponent(conflictFilename)

        let fm = FileManager.default
        try fm.copyItem(at: url, to: conflictURL)
        return conflictURL
    }

    internal func listMarkdownFilesInDirectory(_ dirURL: URL) throws -> [URL] {
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
