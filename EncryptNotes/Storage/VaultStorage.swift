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

    func listNoteFiles() throws -> [URL]
    func loadNoteFile(at url: URL) throws -> EncryptedNoteFile
    func saveNoteFile(_ file: EncryptedNoteFile, at url: URL) throws
    func deleteNoteFile(at url: URL) throws

    func createConflictCopy(for url: URL) throws -> URL
}

extension VaultStorage {
    func noteFileURL(for noteId: String) -> URL? {
        guard let container = containerURL else { return nil }
        return container.appendingPathComponent("notes").appendingPathComponent("\(noteId).bkwenc.json")
    }

    var vaultManifestURL: URL? {
        containerURL?.appendingPathComponent("vault.json")
    }
}
