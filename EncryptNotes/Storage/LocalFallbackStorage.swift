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
        _containerURL = documentsURL.appendingPathComponent("Seal Note")
    }

    func initializeVault() async throws {
        guard let container = containerURL else {
            throw StorageError.directoryCreationFailed
        }

        let directories = [
            container,
            container.appendingPathComponent("trash"),
            container.appendingPathComponent("conflicts"),
            container.appendingPathComponent(".meta")
        ]

        for directory in directories {
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                MaintenanceLogStore.shared.record("storage_directory_created", fields: [
                    "path": directory.path,
                    "storage": "local"
                ])
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
        MaintenanceLogStore.shared.record("index_saved", fields: [
            "entries": index.entries.count,
            "file": url.lastPathComponent,
            "bytes": data.count,
            "storage": "local"
        ])
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
        MaintenanceLogStore.shared.record("markdown_saved", fields: [
            "note_id": file.noteId,
            "file": url.lastPathComponent,
            "updated_at": ISO8601DateFormatter().string(from: file.updatedAt),
            "bytes": data.count,
            "storage": "local"
        ])
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
        MaintenanceLogStore.shared.record("file_moved", fields: [
            "from": srcURL.lastPathComponent,
            "to": dstURL.lastPathComponent,
            "storage": "local"
        ])
    }

    func permanentlyDeleteFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StorageError.fileNotFound
        }
        try FileManager.default.removeItem(at: url)
        MaintenanceLogStore.shared.record("file_deleted", fields: [
            "file": url.lastPathComponent,
            "storage": "local"
        ])
    }

    func createConflictCopy(for url: URL) throws -> URL {
        guard let container = containerURL else {
            throw StorageError.directoryCreationFailed
        }
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = url.deletingPathExtension().lastPathComponent
        let conflictFilename = "\(filename)-conflict-\(timestamp).md"
        let conflictDir = container.appendingPathComponent("conflicts")
        if !FileManager.default.fileExists(atPath: conflictDir.path) {
            try FileManager.default.createDirectory(at: conflictDir, withIntermediateDirectories: true)
        }
        let conflictURL = conflictDir.appendingPathComponent(conflictFilename)
        try FileManager.default.copyItem(at: url, to: conflictURL)
        MaintenanceLogStore.shared.record("conflict_copy_created", fields: [
            "source": url.lastPathComponent,
            "conflict": conflictURL.lastPathComponent,
            "timestamp": timestamp,
            "storage": "local"
        ])
        return conflictURL
    }
}
