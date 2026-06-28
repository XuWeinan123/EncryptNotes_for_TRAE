import Foundation

final class ICloudVaultStorage: VaultStorage, @unchecked Sendable {
    static let shared = ICloudVaultStorage()

    private let containerIdentifier = "iCloud.com.biekanwo.EncryptNotes"
    private let fileManager = FileManager.default

    private var _containerURL: URL?

    var containerURL: URL? {
        _containerURL
    }

    var isAvailable: Bool {
        containerURL != nil
    }

    private init() {
        _containerURL = fileManager.url(forUbiquityContainerIdentifier: containerIdentifier)
    }

    func initializeVault() async throws {
        guard let container = containerURL else {
            throw StorageError.iCloudUnavailable
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
            throw StorageError.iCloudUnavailable
        }

        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder.default.decode(NoteIndex.self, from: data)
    }

    func saveIndex(_ index: NoteIndex) throws {
        guard let url = notesIndexURL else {
            throw StorageError.iCloudUnavailable
        }

        let data = try JSONEncoder.default.encode(index)
        try atomicWrite(data: data, to: url)
    }

    func listMarkdownFiles(in location: NoteFileLocation) throws -> [URL] {
        guard let dirURL = containerURL?.appendingPathComponent(location.rawValue) else {
            throw StorageError.iCloudUnavailable
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
        try atomicWrite(data: data, to: url)
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
            throw StorageError.iCloudUnavailable
        }
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = url.deletingPathExtension().lastPathComponent
        let conflictFilename = "\(filename)-conflict-\(timestamp).md"
        let conflictURL = container.appendingPathComponent("notes").appendingPathComponent(conflictFilename)
        try fileManager.copyItem(at: url, to: conflictURL)
        return conflictURL
    }

    private func atomicWrite(data: Data, to url: URL) throws {
        let tempURL = url.appendingPathExtension("tmp")
        try data.write(to: tempURL, options: .atomic)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.moveItem(at: tempURL, to: url)
    }
}
