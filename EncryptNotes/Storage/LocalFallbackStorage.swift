import Foundation

final class LocalFallbackStorage: VaultStorage, @unchecked Sendable {
    static let shared = LocalFallbackStorage()

    private let fileManager = FileManager.default

    private var _containerURL: URL?

    var containerURL: URL? {
        _containerURL
    }

    var isAvailable: Bool {
        true
    }

    private init() {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        _containerURL = documentsURL.appendingPathComponent("BieKanWo")
    }

    func initializeVault() async throws {
        guard let container = containerURL else {
            throw StorageError.directoryCreationFailed
        }

        let directories = [
            container,
            container.appendingPathComponent("notes"),
            container.appendingPathComponent("trash"),
            container.appendingPathComponent("meta")
        ]

        for directory in directories {
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
    }

    func loadIndex() throws -> NoteIndex? {
        guard let url = notesIndexURL else {
            throw StorageError.directoryCreationFailed
        }

        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder.default.decode(NoteIndex.self, from: data)
    }

    func saveIndex(_ index: NoteIndex) throws {
        guard let url = notesIndexURL else {
            throw StorageError.directoryCreationFailed
        }

        let data = try JSONEncoder.default.encode(index)
        try data.write(to: url, options: .atomic)
    }

    func listMarkdownFiles(in location: NoteFileLocation) throws -> [URL] {
        guard let dirURL = containerURL?.appendingPathComponent(location.rawValue) else {
            throw StorageError.directoryCreationFailed
        }
        return try listMarkdownFilesInDirectory(dirURL)
    }

    func loadMarkdownFile(at url: URL) throws -> MarkdownNoteFile {
        guard fileManager.fileExists(atPath: url.path) else {
            throw StorageError.fileNotFound
        }
        let data = try Data(contentsOf: url)
        return try MarkdownNoteFile.parse(from: data)
    }

    func saveMarkdownFile(_ file: MarkdownNoteFile, at url: URL) throws {
        let data = try file.render()
        try data.write(to: url, options: .atomic)
    }

    func moveFile(from srcURL: URL, to dstURL: URL) throws {
        guard fileManager.fileExists(atPath: srcURL.path) else {
            throw StorageError.fileNotFound
        }
        let dstDir = dstURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dstDir.path) {
            try fileManager.createDirectory(at: dstDir, withIntermediateDirectories: true)
        }
        if fileManager.fileExists(atPath: dstURL.path) {
            try fileManager.removeItem(at: dstURL)
        }
        try fileManager.moveItem(at: srcURL, to: dstURL)
    }

    func permanentlyDeleteFile(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw StorageError.fileNotFound
        }
        try fileManager.removeItem(at: url)
    }

    func createConflictCopy(for url: URL) throws -> URL {
        guard let container = containerURL else {
            throw StorageError.directoryCreationFailed
        }
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = url.deletingPathExtension().lastPathComponent
        let conflictFilename = "\(filename)-conflict-\(timestamp).md"
        let conflictURL = container.appendingPathComponent("notes").appendingPathComponent(conflictFilename)
        try fileManager.copyItem(at: url, to: conflictURL)
        return conflictURL
    }
}
