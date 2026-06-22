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
    @Published private(set) var plainNotes: [Note] = []
    @Published var searchText: String = ""
    @Published var lastError: String?
    @Published var needsKeyExport: Bool = false

    private let storage: VaultStorage
    private let cryptoService = CryptoService.shared
    private let keychainStore = KeychainStore.shared
    private let keyManager = VaultKeyManager.shared
    let purchaseStore = PurchaseStore.shared

    private var currentVaultId: String?
    private var currentKey: CryptoKit.SymmetricKey?

    /// 合并加密笔记与明文笔记，按更新时间倒序返回。
    var filteredNotes: [Note] {
        var result = (notes + plainNotes)
            .sorted { $0.updatedAt > $1.updatedAt }

        if !searchText.isEmpty {
            result = result.filter {
                $0.body.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    /// 明文笔记 ID 集合，用于 UI 判断是否显示小锁标志。
    var plainNoteIds: Set<String> {
        Set(plainNotes.map { $0.id })
    }

    var isUnlocked: Bool {
        if case .unlocked = state { return true }
        return false
    }

    init(storage: VaultStorage? = nil) {
        self.storage = storage ?? (ICloudVaultStorage.shared.isAvailable ? ICloudVaultStorage.shared : LocalFallbackStorage.shared)
    }

    #if DEBUG
    func configureForTesting(state: VaultState, notes: [Note], plainNotes: [Note] = [], vaultId: String? = nil, key: CryptoKit.SymmetricKey? = nil) {
        self.state = state
        self.notes = notes
        self.plainNotes = plainNotes
        self.currentVaultId = vaultId
        self.currentKey = key
    }
    #endif

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
            // 首次创建 vault 后引导用户导出密钥文件
            needsKeyExport = true
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

            // 同时加载明文笔记，使其在锁定状态下也可见（显示为乱码）
            let loadedPlainNotes = try loadPlainNotesFromDisk()
            plainNotes = loadedPlainNotes

            state = .locked(encryptedFiles: encryptedInfos)
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }

    /// 从磁盘加载所有明文笔记，按更新时间倒序返回。
    private func loadPlainNotesFromDisk() throws -> [Note] {
        let plainURLs = try storage.listPlainNoteFiles()
        var loaded: [Note] = []
        for url in plainURLs {
            let file = try storage.loadPlainNoteFile(at: url)
            loaded.append(file.toNote())
        }
        return loaded.sorted { $0.updatedAt > $1.updatedAt }
    }

    func importKeyFile(from url: URL) async throws -> Bool {
        guard let vaultId = currentVaultId else {
            throw StorageError.iCloudUnavailable
        }

        let hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
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

        // 先验证密钥能否解密现有笔记，验证通过后才写入 Keychain
        let noteURLs = try storage.listNoteFiles()
        var decryptedNotes: [Note] = []

        for (index, url) in noteURLs.enumerated() {
            state = .unlocking(progress: UnlockProgress(current: index, total: noteURLs.count))
            let file = try storage.loadNoteFile(at: url)
            let note = try cryptoService.decryptNote(file: file, using: key)
            decryptedNotes.append(note)
        }

        // 解密全部成功后才持久化密钥
        let keyMaterial = vaultKey.keyMaterial
        try keychainStore.saveKey(keyMaterial, forVaultId: vaultId)

        currentKey = key
        notes = decryptedNotes
        // 导入密钥后也加载明文笔记，使其在解锁状态下可正常显示
        plainNotes = (try? loadPlainNotesFromDisk()) ?? []
        state = .unlocked
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
        guard currentVaultId != nil else {
            state = .error(message: "No vault available for decryption")
            return
        }

        guard let key = currentKey else {
            state = .error(message: "No key available for decryption")
            return
        }

        do {
            let noteURLs = try storage.listNoteFiles()
            let total = noteURLs.count
            var decryptedNotes: [Note] = []

            for (index, url) in noteURLs.enumerated() {
                state = .unlocking(progress: UnlockProgress(current: index, total: total))

                let file = try storage.loadNoteFile(at: url)
                let note = try cryptoService.decryptNote(file: file, using: key)
                decryptedNotes.append(note)
            }

            notes = decryptedNotes
            // 解锁后也加载明文笔记，使其在解锁状态下可正常显示
            plainNotes = (try? loadPlainNotesFromDisk()) ?? []
            state = .unlocked
        } catch {
            // 解密失败不应进入 unlocked 状态
            currentKey = nil
            state = .error(message: "解密失败：\(error.localizedDescription)")
        }
    }

    func createNote(body: String) async throws {
        guard let vaultId = currentVaultId else { throw VaultError.notUnlocked }

        let totalNoteCount = notes.count + plainNotes.count
        if !purchaseStore.isPro && totalNoteCount >= 20 {
            throw VaultError.freeLimitReached
        }

        let noteId = UUID().uuidString
        let now = Date()

        if let key = currentKey {
            // 已解锁：创建加密笔记
            let payload = PlainNotePayload(
                body: body,
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
                body: body,
                createdAt: now,
                updatedAt: now
            )

            notes.insert(note, at: 0)
        } else {
            // 未解锁（未导入密钥）：创建明文笔记，带小锁标志
            let plainFile = PlainNoteFile(
                noteId: noteId,
                vaultId: vaultId,
                createdAt: now,
                updatedAt: now,
                body: body
            )

            guard let url = storage.plainNoteFileURL(for: noteId) else {
                throw StorageError.iCloudUnavailable
            }

            try storage.savePlainNoteFile(plainFile, at: url)

            let note = Note(
                id: noteId,
                vaultId: vaultId,
                body: body,
                createdAt: now,
                updatedAt: now
            )

            plainNotes.insert(note, at: 0)
        }
    }

    func updateNote(_ note: Note, body: String) async throws {
        guard let vaultId = currentVaultId else { throw VaultError.notUnlocked }

        let now = Date()

        if let key = currentKey, notes.contains(where: { $0.id == note.id }) {
            // 更新加密笔记
            let payload = PlainNotePayload(
                body: body,
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
                    body: body,
                    createdAt: note.createdAt,
                    updatedAt: now
                )
            }
        } else if plainNotes.contains(where: { $0.id == note.id }) {
            // 更新明文笔记
            let plainFile = PlainNoteFile(
                noteId: note.id,
                vaultId: vaultId,
                createdAt: note.createdAt,
                updatedAt: now,
                body: body
            )

            guard let url = storage.plainNoteFileURL(for: note.id) else {
                throw StorageError.iCloudUnavailable
            }

            try storage.savePlainNoteFile(plainFile, at: url)

            if let index = plainNotes.firstIndex(where: { $0.id == note.id }) {
                plainNotes[index] = Note(
                    id: note.id,
                    vaultId: vaultId,
                    body: body,
                    createdAt: note.createdAt,
                    updatedAt: now
                )
            }
        }
    }

    func deleteNote(_ note: Note) async throws {
        // 先尝试删除加密笔记文件
        if let url = storage.noteFileURL(for: note.id),
           FileManager.default.fileExists(atPath: url.path) {
            try storage.deleteNoteFile(at: url)
            notes.removeAll { $0.id == note.id }
            return
        }

        // 再尝试删除明文笔记文件
        if let url = storage.plainNoteFileURL(for: note.id),
           FileManager.default.fileExists(atPath: url.path) {
            try storage.deletePlainNoteFile(at: url)
            plainNotes.removeAll { $0.id == note.id }
            return
        }
    }

    func lock() {
        currentKey = nil
        notes = []
        searchText = ""
        // 明文笔记在锁定状态下仍可见（显示为乱码），不清理

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

        // 删除 Keychain 中的密钥
        try keychainStore.deleteKey(forVaultId: vaultId)

        // 删除所有加密笔记文件
        let noteURLs = try storage.listNoteFiles()
        for url in noteURLs {
            try storage.deleteNoteFile(at: url)
        }

        // 删除所有明文笔记文件
        let plainNoteURLs = try storage.listPlainNoteFiles()
        for url in plainNoteURLs {
            try storage.deletePlainNoteFile(at: url)
        }

        // 删除 vault.json
        if let manifestURL = storage.vaultManifestURL {
            try? FileManager.default.removeItem(at: manifestURL)
        }

        // 清空 trash 和 meta 目录
        if let container = storage.containerURL {
            let trashURL = container.appendingPathComponent("trash")
            let metaURL = container.appendingPathComponent("meta")
            if FileManager.default.fileExists(atPath: trashURL.path) {
                if let trashContents = try? FileManager.default.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil) {
                    for file in trashContents {
                        try? FileManager.default.removeItem(at: file)
                    }
                }
            }
            if FileManager.default.fileExists(atPath: metaURL.path) {
                if let metaContents = try? FileManager.default.contentsOfDirectory(at: metaURL, includingPropertiesForKeys: nil) {
                    for file in metaContents {
                        try? FileManager.default.removeItem(at: file)
                    }
                }
            }
        }

        currentKey = nil
        notes = []
        plainNotes = []
        currentVaultId = nil

        await createNewVault()
    }
}

enum VaultError: Error, LocalizedError {
    case freeLimitReached
    case notUnlocked

    var errorDescription: String? {
        switch self {
        case .freeLimitReached: return "已达免费版上限（20 条），升级 Pro 解锁无限笔记"
        case .notUnlocked: return "加密空间未解锁"
        }
    }
}
