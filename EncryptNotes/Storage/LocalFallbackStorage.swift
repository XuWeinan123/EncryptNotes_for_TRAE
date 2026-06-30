import Foundation

final class LocalFallbackStorage: VaultStorage, @unchecked Sendable {
    static let shared = LocalFallbackStorage()

    private let _containerURL: URL?

    nonisolated var containerURL: URL? {
        _containerURL
    }

    nonisolated var isAvailable: Bool {
        true
    }

    private init() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        _containerURL = documentsURL.appendingPathComponent("BieKanWo")
    }

    func initializeVault() async throws {
        guard let container = containerURL else {
            throw StorageError.directoryCreationFailed
        }

        let directories = [
            container,
            container.appendingPathComponent("trash"),
            container.appendingPathComponent(".meta")
        ]

        for directory in directories {
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
    }

    func loadIndex() throws -> NoteIndex? {
        guard let url = notesIndexURL else {
            throw StorageError.directoryCreationFailed
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
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
        guard let container = containerURL else {
            throw StorageError.directoryCreationFailed
        }
        let dirURL = location == .notes ? container : container.appendingPathComponent(location.rawValue)
        return try listMarkdownFilesInDirectory(dirURL)
    }

    func loadMarkdownFile(at url: URL) throws -> MarkdownNoteFile {
        guard FileManager.default.fileExists(atPath: url.path) else {
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
        guard FileManager.default.fileExists(atPath: srcURL.path) else {
            throw StorageError.fileNotFound
        }
        let dstDir = dstURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dstDir.path) {
            try FileManager.default.createDirectory(at: dstDir, withIntermediateDirectories: true)
        }
        if FileManager.default.fileExists(atPath: dstURL.path) {
            try FileManager.default.removeItem(at: dstURL)
        }
        try FileManager.default.moveItem(at: srcURL, to: dstURL)
    }

    func permanentlyDeleteFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StorageError.fileNotFound
        }
        try FileManager.default.removeItem(at: url)
    }

    func createConflictCopy(for url: URL) throws -> URL {
        guard let container = containerURL else {
            throw StorageError.directoryCreationFailed
        }
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = url.deletingPathExtension().lastPathComponent
        let conflictFilename = "\(filename)-conflict-\(timestamp).md"
        let conflictURL = container.appendingPathComponent(conflictFilename)
        try FileManager.default.copyItem(at: url, to: conflictURL)
        return conflictURL
    }
}
