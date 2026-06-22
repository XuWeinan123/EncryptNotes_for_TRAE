import Foundation

final class ICloudVaultStorage: VaultStorage {
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

    func loadManifest() throws -> VaultManifest? {
        guard let url = vaultManifestURL else {
            throw StorageError.iCloudUnavailable
        }

        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder.default.decode(VaultManifest.self, from: data)
    }

    func saveManifest(_ manifest: VaultManifest) throws {
        guard let url = vaultManifestURL else {
            throw StorageError.iCloudUnavailable
        }

        let data = try JSONEncoder.default.encode(manifest)
        try atomicWrite(data: data, to: url)
    }

    func listNoteFiles() throws -> [URL] {
        guard let notesURL = containerURL?.appendingPathComponent("notes") else {
            throw StorageError.iCloudUnavailable
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
        try atomicWrite(data: data, to: url)
    }

    func deleteNoteFile(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw StorageError.fileNotFound
        }

        guard let container = containerURL else {
            throw StorageError.iCloudUnavailable
        }

        let trashURL = container.appendingPathComponent("trash").appendingPathComponent(url.lastPathComponent)

        do {
            try fileManager.moveItem(at: url, to: trashURL)
        } catch {
            try fileManager.removeItem(at: url)
        }
    }

    func createConflictCopy(for url: URL) throws -> URL {
        guard let container = containerURL else {
            throw StorageError.iCloudUnavailable
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
            throw StorageError.iCloudUnavailable
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
        try atomicWrite(data: data, to: url)
    }

    func deletePlainNoteFile(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw StorageError.fileNotFound
        }

        guard let container = containerURL else {
            throw StorageError.iCloudUnavailable
        }

        let trashURL = container.appendingPathComponent("trash").appendingPathComponent(url.lastPathComponent)

        do {
            try fileManager.moveItem(at: url, to: trashURL)
        } catch {
            try fileManager.removeItem(at: url)
        }
    }

    private func atomicWrite(data: Data, to url: URL) throws {
        let tempURL = url.appendingPathExtension("tmp")
        try data.write(to: tempURL, options: .atomic)
        // 目标文件已存在时先删除再移动，避免 moveItem 失败
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.moveItem(at: tempURL, to: url)
    }
}
