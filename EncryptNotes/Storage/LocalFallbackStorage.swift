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

    func loadManifest() throws -> VaultManifest? {
        guard let url = vaultManifestURL else {
            throw StorageError.directoryCreationFailed
        }

        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder.default.decode(VaultManifest.self, from: data)
    }

    func saveManifest(_ manifest: VaultManifest) throws {
        guard let url = vaultManifestURL else {
            throw StorageError.directoryCreationFailed
        }

        let data = try JSONEncoder.default.encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    func listNoteFiles() throws -> [URL] {
        guard let notesURL = containerURL?.appendingPathComponent("notes") else {
            throw StorageError.directoryCreationFailed
        }

        guard fileManager.fileExists(atPath: notesURL.path) else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(
            at: notesURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return contents
            .filter { $0.lastPathComponent.hasSuffix(".bkwenc.json") }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return date1 > date2
            }
    }

    func loadNoteFile(at url: URL) throws -> EncryptedNoteFile {
        guard fileManager.fileExists(atPath: url.path) else {
            throw StorageError.fileNotFound
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder.default.decode(EncryptedNoteFile.self, from: data)
    }

    func saveNoteFile(_ file: EncryptedNoteFile, at url: URL) throws {
        let data = try JSONEncoder.default.encode(file)
        try data.write(to: url, options: .atomic)
    }

    func createConflictCopy(for url: URL) throws -> URL {
        guard let container = containerURL else {
            throw StorageError.directoryCreationFailed
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = url.deletingPathExtension().lastPathComponent
        let conflictFilename = "\(filename)-conflict-\(timestamp).bkwenc.json"
        let conflictURL = container.appendingPathComponent("notes").appendingPathComponent(conflictFilename)

        try fileManager.copyItem(at: url, to: conflictURL)
        return conflictURL
    }

    // MARK: - Plain note files

    func listPlainNoteFiles() throws -> [URL] {
        guard let notesURL = containerURL?.appendingPathComponent("notes") else {
            throw StorageError.directoryCreationFailed
        }

        guard fileManager.fileExists(atPath: notesURL.path) else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(
            at: notesURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return contents
            .filter { $0.lastPathComponent.hasSuffix(".bkwplain.json") }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return date1 > date2
            }
    }

    func loadPlainNoteFile(at url: URL) throws -> PlainNoteFile {
        guard fileManager.fileExists(atPath: url.path) else {
            throw StorageError.fileNotFound
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder.default.decode(PlainNoteFile.self, from: data)
    }

    func savePlainNoteFile(_ file: PlainNoteFile, at url: URL) throws {
        let data = try JSONEncoder.default.encode(file)
        try data.write(to: url, options: .atomic)
    }
}
