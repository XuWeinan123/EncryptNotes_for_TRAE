import Foundation
import SwiftUI
import Combine
import CryptoKit

enum VaultState: Equatable {
    case noVault
    case locked(encryptedFiles: [EncryptedNoteInfo])
    case unlocking(progress: UnlockProgress)
    case unlocked
    case error(message: String)

    static func == (lhs: VaultState, rhs: VaultState) -> Bool {
        switch (lhs, rhs) {
        case (.noVault, .noVault): return true
        case (.locked(let l), .locked(let r)): return l == r
        case (.unlocking(let l), .unlocking(let r)): return l == r
        case (.unlocked, .unlocked): return true
        case (.error(let l), .error(let r)): return l == r
        default: return false
        }
    }
}

struct EncryptedNoteInfo: Identifiable, Equatable {
    let id: String
    let url: URL
    let ciphertextPreview: String
    let fileSize: Int
    let updatedAt: Date
}

struct UnlockProgress: Equatable {
    let current: Int
    let total: Int
}

@MainActor
final class VaultStore: ObservableObject {
    static let shared = VaultStore()

    @Published private(set) var state: VaultState = .noVault
    @Published private(set) var notes: [Note] = []
    @Published var searchText: String = ""
    @Published var selectedTag: String?

    private let storage: VaultStorage
    private let cryptoService = CryptoService.shared
    private let keychainStore = KeychainStore.shared
    private let keyManager = VaultKeyManager.shared
    let purchaseStore = PurchaseStore.shared

    private var currentVaultId: String?
    private var currentKey: CryptoKit.SymmetricKey?

    var filteredNotes: [Note] {
        var result = notes

        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.body.localizedCaseInsensitiveContains(searchText)
            }
        }

        if let tag = selectedTag {
            result = result.filter { $0.tags.contains(tag) }
        }

        return result
    }

    var allTags: [String] {
        Array(Set(notes.flatMap { $0.tags })).sorted()
    }

    var isUnlocked: Bool {
        if case .unlocked = state { return true }
        return false
    }

    init(storage: VaultStorage? = nil) {
        self.storage = storage ?? (ICloudVaultStorage.shared.isAvailable ? ICloudVaultStorage.shared : LocalFallbackStorage.shared)
    }

    func initialize() async {
        do {
            try await storage.initializeVault()

            if let manifest = try storage.loadManifest() {
                currentVaultId = manifest.vaultId

                if keychainStore.hasKey(forVaultId: manifest.vaultId) {
                    await tryUnlockWithKeychain(manifest: manifest)
                } else {
                    await loadEncryptedFiles()
                }
            } else {
                await createNewVault()
            }
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }

    private func createNewVault() async {
        let vaultId = UUID().uuidString
        let key = keyManager.generateKey()
        let keyMaterial = keyManager.keyToBase64(key)
        let now = Date()

        let manifest = VaultManifest(
            version: 1,
            app: "BieKanWo",
            type: "vault",
            vaultId: vaultId,
            createdAt: now,
            updatedAt: now,
            keyVersion: 1
        )

        do {
            try storage.saveManifest(manifest)
            try keychainStore.saveKey(keyMaterial, forVaultId: vaultId)

            currentVaultId = vaultId
            currentKey = key
            notes = []
            state = .unlocked
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }

    private func loadEncryptedFiles() async {
        do {
            let noteURLs = try storage.listNoteFiles()
            let encryptedInfos = try noteURLs.map { url -> EncryptedNoteInfo in
                let file = try storage.loadNoteFile(at: url)
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                let size = attrs[.size] as? Int ?? 0
                let preview = String(file.payload.ciphertext.prefix(50))
                return EncryptedNoteInfo(
                    id: file.noteId,
                    url: url,
                    ciphertextPreview: preview,
                    fileSize: size,
                    updatedAt: file.updatedAt
                )
            }
            state = .locked(encryptedFiles: encryptedInfos)
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }

    func importKeyFile(from url: URL) async throws -> Bool {
        guard let vaultId = currentVaultId else {
            throw StorageError.iCloudUnavailable
        }

        let data = try Data(contentsOf: url)
        let vaultKey = try JSONDecoder.default.decode(VaultKey.self, from: data)

        guard keyManager.validateVaultKey(vaultKey) else {
            throw CryptoError.keyValidationFailed
        }

        guard vaultKey.vaultId == vaultId else {
            throw CryptoError.keyValidationFailed
        }

        let key = try keyManager.extractKey(vaultKey)
        let keyMaterial = vaultKey.keyMaterial

        try keychainStore.saveKey(keyMaterial, forVaultId: vaultId)

        currentKey = key
        await decryptAllNotes()
        return true
    }

    private func tryUnlockWithKeychain(manifest: VaultManifest) async {
        do {
            let keyMaterial = try keychainStore.loadKey(forVaultId: manifest.vaultId)
            let key = try keyManager.keyFromBase64(keyMaterial)

            currentKey = key
            await decryptAllNotes()
        } catch {
            await loadEncryptedFiles()
        }
    }

    private func decryptAllNotes() async {
        guard let vaultId = currentVaultId else { return }

        do {
            let noteURLs = try storage.listNoteFiles()
            let total = noteURLs.count
            var decryptedNotes: [Note] = []
            var failedCount = 0

            for (index, url) in noteURLs.enumerated() {
                state = .unlocking(progress: UnlockProgress(current: index, total: total))

                do {
                    let file = try storage.loadNoteFile(at: url)
                    let note = try cryptoService.decryptNote(file: file, using: currentKey!)
                    decryptedNotes.append(note)
                } catch {
                    failedCount += 1
                }
            }

            notes = decryptedNotes
            state = .unlocked
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }

    func createNote(title: String, body: String, tags: [String] = []) async throws {
        guard isUnlocked else { return }
        guard let vaultId = currentVaultId, let key = currentKey else { return }

        if !purchaseStore.isPro && notes.count >= 20 {
            throw VaultError.freeLimitReached
        }

        let noteId = UUID().uuidString
        let now = Date()
        let finalTitle = title.isEmpty ? String(body.prefix(50)) : title

        let payload = PlainNotePayload(
            title: finalTitle,
            body: body,
            tags: tags,
            createdAt: now,
            updatedAt: now
        )

        let noteFile = try cryptoService.encryptToNoteFile(
            noteId: noteId,
            vaultId: vaultId,
            payload: payload,
            key: key
        )

        guard let url = storage.noteFileURL(for: noteId) else {
            throw StorageError.iCloudUnavailable
        }

        try storage.saveNoteFile(noteFile, at: url)

        let note = Note(
            id: noteId,
            vaultId: vaultId,
            title: finalTitle,
            body: body,
            tags: tags,
            createdAt: now,
            updatedAt: now
        )

        notes.insert(note, at: 0)
    }

    func updateNote(_ note: Note, title: String, body: String, tags: [String]) async throws {
        guard isUnlocked else { return }
        guard let vaultId = currentVaultId, let key = currentKey else { return }

        let now = Date()
        let finalTitle = title.isEmpty ? String(body.prefix(50)) : title

        let payload = PlainNotePayload(
            title: finalTitle,
            body: body,
            tags: tags,
            createdAt: note.createdAt,
            updatedAt: now
        )

        let noteFile = try cryptoService.encryptToNoteFile(
            noteId: note.id,
            vaultId: vaultId,
            payload: payload,
            key: key
        )

        guard let url = storage.noteFileURL(for: note.id) else {
            throw StorageError.iCloudUnavailable
        }

        if let diskFile = try? storage.loadNoteFile(at: url), diskFile.updatedAt > note.updatedAt {
            _ = try storage.createConflictCopy(for: url)
        }

        try storage.saveNoteFile(noteFile, at: url)

        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = Note(
                id: note.id,
                vaultId: vaultId,
                title: finalTitle,
                body: body,
                tags: tags,
                createdAt: note.createdAt,
                updatedAt: now
            )
        }
    }

    func deleteNote(_ note: Note) async throws {
        guard let url = storage.noteFileURL(for: note.id) else { return }

        try storage.deleteNoteFile(at: url)
        notes.removeAll { $0.id == note.id }
    }

    func lock() {
        currentKey = nil
        notes = []
        searchText = ""
        selectedTag = nil

        Task {
            await loadEncryptedFiles()
        }
    }

    func exportKeyFile() throws -> URL {
        guard let vaultId = currentVaultId,
              let keyMaterial = try? keychainStore.loadKey(forVaultId: vaultId) else {
            throw KeychainError.notFound
        }

        let key = try keyManager.keyFromBase64(keyMaterial)
        let vaultKey = keyManager.generateVaultKey(vaultId: vaultId, key: key)

        let data = try JSONEncoder.default.encode(vaultKey)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(vaultId).bkwkey")
        try data.write(to: tempURL)

        return tempURL
    }

    func resetVault() async throws {
        guard let vaultId = currentVaultId else { return }

        try keychainStore.deleteKey(forVaultId: vaultId)

        let noteURLs = try storage.listNoteFiles()
        for url in noteURLs {
            try? storage.deleteNoteFile(at: url)
        }

        currentKey = nil
        notes = []
        currentVaultId = nil

        await createNewVault()
    }
}

enum VaultError: Error, LocalizedError {
    case freeLimitReached
    case notUnlocked

    var errorDescription: String? {
        switch self {
        case .freeLimitReached: return "Free limit reached. Upgrade to Pro for unlimited notes."
        case .notUnlocked: return "Vault is not unlocked"
        }
    }
}
