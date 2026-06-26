import Foundation

enum StorageError: Error, LocalizedError {
    case iCloudUnavailable
    case directoryCreationFailed
    case fileWriteFailed
    case fileReadFailed
    case fileDeleteFailed
    case fileNotFound
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
        case .atomicWriteFailed: return "Atomic write failed"
        case .invalidData: return "Invalid data"
        }
    }
}

protocol VaultStorage {
    var isAvailable: Bool { get }
    var containerURL: URL? { get }

    func initializeVault() async throws
    func loadManifest() throws -> VaultManifest?
    func saveManifest(_ manifest: VaultManifest) throws

    // MARK: - 加密笔记文件（notes/ 与 trash/ 通用）

    func listNoteFiles() throws -> [URL]
    func loadNoteFile(at url: URL) throws -> EncryptedNoteFile
    func saveNoteFile(_ file: EncryptedNoteFile, at url: URL) throws

    // MARK: - 明文笔记文件（notes/ 与 trash/ 通用）

    func listPlainNoteFiles() throws -> [URL]
    func loadPlainNoteFile(at url: URL) throws -> PlainNoteFile
    func savePlainNoteFile(_ file: PlainNoteFile, at url: URL) throws

    // MARK: - 冲突与永久删除

    func createConflictCopy(for url: URL) throws -> URL
    func createPlainConflictCopy(for url: URL) throws -> URL
    /// 永久删除指定文件（不进入回收站）。
    func permanentlyDeleteFile(at url: URL) throws
}

extension VaultStorage {
    func createPlainConflictCopy(for url: URL) throws -> URL {
        guard let container = containerURL else {
            throw StorageError.iCloudUnavailable
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = url.deletingPathExtension().lastPathComponent
        let conflictFilename = "\(filename)-conflict-\(timestamp).bkwplain.json"
        let conflictURL = container.appendingPathComponent("notes").appendingPathComponent(conflictFilename)

        let fm = FileManager.default
        try fm.copyItem(at: url, to: conflictURL)
        return conflictURL
    }
}

extension VaultStorage {
    // MARK: - notes/ 路径

    func noteFileURL(for noteId: String) -> URL? {
        guard let container = containerURL else { return nil }
        return container.appendingPathComponent("notes").appendingPathComponent("\(noteId).bkwenc.json")
    }

    func plainNoteFileURL(for noteId: String) -> URL? {
        guard let container = containerURL else { return nil }
        return container.appendingPathComponent("notes").appendingPathComponent("\(noteId).bkwplain.json")
    }

    var vaultManifestURL: URL? {
        containerURL?.appendingPathComponent("vault.json")
    }

    // MARK: - trash/ 路径

    func trashNoteFileURL(for noteId: String) -> URL? {
        guard let container = containerURL else { return nil }
        return container.appendingPathComponent("trash").appendingPathComponent("\(noteId).bkwenc.json")
    }

    func trashPlainNoteFileURL(for noteId: String) -> URL? {
        guard let container = containerURL else { return nil }
        return container.appendingPathComponent("trash").appendingPathComponent("\(noteId).bkwplain.json")
    }

    // MARK: - trash/ 列举（默认实现）

    func listTrashNoteFiles() throws -> [URL] {
        try listFiles(in: "trash", suffix: ".bkwenc.json")
    }

    func listTrashPlainNoteFiles() throws -> [URL] {
        try listFiles(in: "trash", suffix: ".bkwplain.json")
    }

    /// 清空 `trash/` 目录下所有文件。
    func emptyTrash() throws {
        guard let trashURL = containerURL?.appendingPathComponent("trash") else {
            throw StorageError.iCloudUnavailable
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: trashURL.path) else { return }
        let contents = try fm.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        for file in contents {
            try? fm.removeItem(at: file)
        }
    }

    /// 永久删除指定文件（默认实现）。
    func permanentlyDeleteFile(at url: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw StorageError.fileNotFound
        }
        try fm.removeItem(at: url)
    }

    /// 列举某子目录下指定后缀的文件，按修改时间倒序。
    private func listFiles(in subdirectory: String, suffix: String) throws -> [URL] {
        guard let dirURL = containerURL?.appendingPathComponent(subdirectory) else {
            throw StorageError.iCloudUnavailable
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: dirURL.path) else { return [] }

        let contents = try fm.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return contents
            .filter { $0.lastPathComponent.hasSuffix(suffix) }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return date1 > date2
            }
    }
}
