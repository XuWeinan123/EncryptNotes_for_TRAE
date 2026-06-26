import Foundation
import SwiftUI
import Combine
import CryptoKit

/// 内部技术状态，仅用于初始化与错误展示，不再决定首页是否可用。
enum VaultState: Equatable {
    case loading
    case ready
    case error(message: String)

    static func == (lhs: VaultState, rhs: VaultState) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading): return true
        case (.ready, .ready): return true
        case (.error(let l), .error(let r)): return l == r
        default: return false
        }
    }
}

/// 未解密加密笔记的元信息，用于乱码卡片展示。
struct EncryptedNoteInfo: Identifiable, Equatable {
    let id: String
    let url: URL
    let ciphertextPreview: String
    let fileSize: Int
    let updatedAt: Date
}

@MainActor
final class VaultStore: ObservableObject {
    static let shared = VaultStore()

    // MARK: - Published state

    @Published private(set) var state: VaultState = .loading
    /// 已解密加密笔记（密钥已加载时填充）。
    @Published private(set) var decryptedNotes: [Note] = []
    /// 明文笔记。
    @Published private(set) var plainNotes: [Note] = []
    /// 未解密加密笔记的元信息（密钥未加载时展示为乱码卡片）。
    @Published private(set) var lockedEncryptedNotes: [EncryptedNoteInfo] = []
    /// 回收站笔记。
    @Published private(set) var trashNotes: [TrashNote] = []
    /// 当前选中的标签；nil 表示展示全部。
    @Published var selectedTag: String?
    @Published var searchText: String = ""
    @Published var lastError: String?
    /// 创建密钥后置 true，UI 提示用户导出密钥文件。
    @Published var needsKeyExport: Bool = false

    // MARK: - Dependencies

    private let storage: VaultStorage
    private let cryptoService = CryptoService.shared
    private let keychainStore = KeychainStore.shared
    private let keyManager = VaultKeyManager.shared
    private let settings = SettingsStore.shared

    private var currentVaultId: String?
    private var currentKey: CryptoKit.SymmetricKey?

    // MARK: - Init

    init(storage: VaultStorage? = nil) {
        self.storage = storage ?? (ICloudVaultStorage.shared.isAvailable ? ICloudVaultStorage.shared : LocalFallbackStorage.shared)
    }

    #if DEBUG
    func configureForTesting(
        vaultId: String,
        key: CryptoKit.SymmetricKey? = nil,
        decryptedNotes: [Note] = [],
        plainNotes: [Note] = [],
        lockedEncryptedNotes: [EncryptedNoteInfo] = [],
        trashNotes: [TrashNote] = []
    ) {
        self.currentVaultId = vaultId
        self.currentKey = key
        self.decryptedNotes = decryptedNotes
        self.plainNotes = plainNotes
        self.lockedEncryptedNotes = lockedEncryptedNotes
        self.trashNotes = trashNotes
        self.state = .ready
    }
    #endif

    // MARK: - Derived state

    /// 密钥是否已加载到当前设备。
    var isKeyLoaded: Bool { currentKey != nil }

    /// 所有可读笔记（明文 + 已解密加密），按更新时间倒序。
    var readableNotes: [Note] {
        (plainNotes + decryptedNotes).sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 首页展示的笔记：可读笔记按 selectedTag + searchText 过滤。
    /// 未解密加密笔记以乱码卡片形式追加在末尾（不参与搜索与标签筛选）。
    var filteredNotes: [NoteListItem] {
        var readable = readableNotes

        if let tag = selectedTag {
            readable = readable.filter { note in
                TagParser.tags(in: note.body).contains(tag)
            }
        }

        if !searchText.isEmpty {
            readable = readable.filter {
                $0.body.localizedCaseInsensitiveContains(searchText)
            }
        }

        var items: [NoteListItem] = readable.map { .readable($0) }

        // 未解密加密笔记仅在未选标签、未搜索时展示在末尾
        if selectedTag == nil && searchText.isEmpty {
            items.append(contentsOf: lockedEncryptedNotes.map { .locked($0) })
        }

        return items
    }

    /// 所有标签及其在可读笔记中的出现次数，按数量倒序、再按名称排序。
    var allTags: [TagCount] {
        var counts: [String: Int] = [:]
        for note in readableNotes {
            for tag in TagParser.tags(in: note.body) {
                counts[tag, default: 0] += 1
            }
        }
        return counts
            .map { TagCount(tag: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.tag < rhs.tag
            }
    }

    /// 回收站笔记数量（含未解密加密笔记）。
    var trashCount: Int { trashNotes.count }

    var readableNoteCount: Int { plainNotes.count + decryptedNotes.count }
    var encryptedNoteCount: Int { decryptedNotes.count + lockedEncryptedNotes.count }
    var lockedNoteCount: Int { lockedEncryptedNotes.count }
    var totalNoteCount: Int { readableNoteCount + lockedEncryptedNotes.count }

    // MARK: - Initialize

    func initialize() async {
        do {
            try await storage.initializeVault()
            await purgeExpiredTrash()

            if let manifest = try storage.loadManifest() {
                currentVaultId = manifest.vaultId
                await loadAllNotes()
                seedDefaultNotesIfNeeded()
                state = .ready
            } else {
                await createNewVault()
                seedDefaultNotesIfNeeded()
                state = .ready
            }
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }

    private func createNewVault() async {
        let vaultId = UUID().uuidString
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

            currentVaultId = vaultId
            currentKey = nil
            decryptedNotes = []
            plainNotes = []
            lockedEncryptedNotes = []
            trashNotes = []
            needsKeyExport = false
            settings.preferredNoteMode = .plain
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }

    /// 加载所有笔记：明文笔记 + 加密笔记（按密钥是否加载决定解密或展示为乱码）。
    private func loadAllNotes() async {
        do {
            if let vaultId = currentVaultId,
               let keyMaterial = try? keychainStore.loadKey(forVaultId: vaultId),
               let loadedKey = try? keyManager.keyFromBase64(keyMaterial) {
                currentKey = loadedKey
            } else {
                currentKey = nil
                if settings.preferredNoteMode == .encrypted {
                    settings.preferredNoteMode = .plain
                }
            }

            // 明文笔记
            plainNotes = try loadPlainNotesFromDisk()

            // 加密笔记
            let noteURLs = try storage.listNoteFiles()
            if let key = currentKey {
                var decrypted: [Note] = []
                var locked: [EncryptedNoteInfo] = []
                for url in noteURLs {
                    let file = try storage.loadNoteFile(at: url)
                    if let note = try? cryptoService.decryptNote(file: file, using: key) {
                        decrypted.append(note)
                    } else {
                        // 单条解密失败时降级为乱码卡片，不阻断整体加载
                        locked.append(makeLockedInfo(from: file, url: url))
                    }
                }
                decryptedNotes = decrypted
                lockedEncryptedNotes = locked
            } else {
                decryptedNotes = []
                lockedEncryptedNotes = try noteURLs.map { url in
                    let file = try storage.loadNoteFile(at: url)
                    return makeLockedInfo(from: file, url: url)
                }
            }

            trashNotes = try loadTrashNotes()
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }

    private func makeLockedInfo(from file: EncryptedNoteFile, url: URL) -> EncryptedNoteInfo {
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
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

    private func loadPlainNotesFromDisk() throws -> [Note] {
        let plainURLs = try storage.listPlainNoteFiles()
        var loaded: [Note] = []
        for url in plainURLs {
            let file = try storage.loadPlainNoteFile(at: url)
            loaded.append(file.toNote())
        }
        return loaded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func loadTrashNotes() throws -> [TrashNote] {
        var loaded: [TrashNote] = []

        let key = currentKey
        let encURLs = (try? storage.listTrashNoteFiles()) ?? []
        for url in encURLs {
            let file = try storage.loadNoteFile(at: url)
            let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
            let size = attrs[.size] as? Int ?? 0
            let body: String? = {
                guard let k = key else { return nil }
                return (try? cryptoService.decryptNote(file: file, using: k))?.body
            }()
            loaded.append(TrashNote(
                id: file.noteId,
                vaultId: file.vaultId,
                isEncrypted: true,
                createdAt: file.createdAt,
                updatedAt: file.updatedAt,
                deletedAt: file.deletedAt ?? Date(),
                purgeAfter: file.purgeAfter ?? Date().addingTimeInterval(30 * 86400),
                url: url,
                body: body,
                ciphertextPreview: String(file.payload.ciphertext.prefix(50)),
                fileSize: size
            ))
        }

        let plainURLs = (try? storage.listTrashPlainNoteFiles()) ?? []
        for url in plainURLs {
            let file = try storage.loadPlainNoteFile(at: url)
            let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
            let size = attrs[.size] as? Int ?? 0
            loaded.append(TrashNote(
                id: file.noteId,
                vaultId: file.vaultId,
                isEncrypted: false,
                createdAt: file.createdAt,
                updatedAt: file.updatedAt,
                deletedAt: file.deletedAt ?? Date(),
                purgeAfter: file.purgeAfter ?? Date().addingTimeInterval(30 * 86400),
                url: url,
                body: file.body,
                ciphertextPreview: nil,
                fileSize: size
            ))
        }

        return loaded.sorted { $0.deletedAt > $1.deletedAt }
    }

    // MARK: - Default notes

    /// 首次启动且无任何笔记时创建默认明文笔记。
    private func seedDefaultNotesIfNeeded() {
        guard !settings.hasSeededDefaultNotes else { return }
        guard plainNotes.isEmpty && decryptedNotes.isEmpty && lockedEncryptedNotes.isEmpty else {
            settings.hasSeededDefaultNotes = true
            return
        }
        guard let vaultId = currentVaultId else { return }

        let now = Date()
        let defaults: [(String, Date)] = [
            ("欢迎使用别看我。\n\n你可以像写卡片一样记录想法，也可以在需要时创建加密笔记。\n\n#欢迎", now),
            ("标签写法示例：\n\n在正文中输入 #灵感 或 #日记 ，它们会出现在侧边栏的标签区域。\n\n#使用说明 #标签", now.addingTimeInterval(-1)),
            ("加密笔记适合保存更私密的内容。\n\n首次创建笔记时，你可以选择创建密钥。创建密钥后，新建笔记时可以打开\"加密笔记\"开关。\n\n#加密", now.addingTimeInterval(-2))
        ]

        for (body, date) in defaults {
            let noteId = UUID().uuidString
            let file = PlainNoteFile(
                noteId: noteId,
                vaultId: vaultId,
                createdAt: date,
                updatedAt: date,
                body: body
            )
            if let url = storage.plainNoteFileURL(for: noteId) {
                try? storage.savePlainNoteFile(file, at: url)
                plainNotes.append(file.toNote())
            }
        }
        plainNotes.sort { $0.updatedAt > $1.updatedAt }
        settings.hasSeededDefaultNotes = true
    }

    // MARK: - Key management

    /// 创建新密钥并自动加载到当前设备。
    func createKey() async throws {
        guard let vaultId = currentVaultId else { throw VaultError.notReady }

        let key = keyManager.generateKey()
        let keyMaterial = keyManager.keyToBase64(key)

        try keychainStore.saveKey(keyMaterial, forVaultId: vaultId)
        currentKey = key

        // 重新加载加密笔记（如果有），未解密的尝试解密
        await reloadEncryptedNotes()

        needsKeyExport = true
        settings.preferredNoteMode = .encrypted
    }

    /// 导入 `.bkwkey` 文件；先验证能解密全部加密笔记才持久化到 Keychain。
    func importKeyFile(from url: URL) async throws -> Bool {
        guard let vaultId = currentVaultId else { throw VaultError.notReady }

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

        // 先验证密钥能否解密现有加密笔记，验证通过后才写入 Keychain
        let noteURLs = try storage.listNoteFiles()
        var decryptedNotes: [Note] = []
        for url in noteURLs {
            let file = try storage.loadNoteFile(at: url)
            let note = try cryptoService.decryptNote(file: file, using: key)
            decryptedNotes.append(note)
        }

        // 解密全部成功后才持久化密钥
        try keychainStore.saveKey(vaultKey.keyMaterial, forVaultId: vaultId)

        currentKey = key
        self.decryptedNotes = decryptedNotes
        self.lockedEncryptedNotes = []
        trashNotes = try loadTrashNotes()

        settings.preferredNoteMode = .encrypted
        return true
    }

    /// 卸载本机密钥：删除 Keychain，加密笔记回到乱码态，不删除任何笔记文件。
    func unloadKey() async throws {
        guard let vaultId = currentVaultId else { return }
        try keychainStore.deleteKey(forVaultId: vaultId)
        currentKey = nil
        decryptedNotes = []
        // 重新加载加密笔记为乱码态
        lockedEncryptedNotes = try storage.listNoteFiles().map { url in
            let file = try storage.loadNoteFile(at: url)
            return makeLockedInfo(from: file, url: url)
        }
        trashNotes = try loadTrashNotes()
        settings.preferredNoteMode = .plain

        // 若当前选中标签因卸载密钥失效，自动切回全部
        if let tag = selectedTag, !allTags.contains(where: { $0.tag == tag }) {
            selectedTag = nil
        }
    }

    /// 重置密钥：删除所有加密笔记（含回收站），保留明文笔记，生成并加载新密钥。
    func resetKey() async throws {
        guard let vaultId = currentVaultId else { throw VaultError.notReady }

        // 删除 Keychain 旧密钥
        try keychainStore.deleteKey(forVaultId: vaultId)

        // 删除 notes/ 中所有加密笔记
        let noteURLs = try storage.listNoteFiles()
        for url in noteURLs {
            try storage.permanentlyDeleteFile(at: url)
        }

        // 删除 trash/ 中所有加密笔记
        let trashEncURLs = (try? storage.listTrashNoteFiles()) ?? []
        for url in trashEncURLs {
            try storage.permanentlyDeleteFile(at: url)
        }

        // 生成新密钥并加载
        let key = keyManager.generateKey()
        let keyMaterial = keyManager.keyToBase64(key)
        try keychainStore.saveKey(keyMaterial, forVaultId: vaultId)
        currentKey = key

        decryptedNotes = []
        lockedEncryptedNotes = []
        trashNotes = try loadTrashNotes()

        needsKeyExport = true
        settings.preferredNoteMode = .encrypted
    }

    private func reloadEncryptedNotes() async {
        do {
            if let key = currentKey {
                let noteURLs = try storage.listNoteFiles()
                var decrypted: [Note] = []
                var locked: [EncryptedNoteInfo] = []
                for url in noteURLs {
                    let file = try storage.loadNoteFile(at: url)
                    if let note = try? cryptoService.decryptNote(file: file, using: key) {
                        decrypted.append(note)
                    } else {
                        locked.append(makeLockedInfo(from: file, url: url))
                    }
                }
                decryptedNotes = decrypted
                lockedEncryptedNotes = locked
            }
            trashNotes = try loadTrashNotes()
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }

    /// 导出密钥文件到临时目录，返回 URL 供分享。
    func exportKeyFile() throws -> URL {
        guard let vaultId = currentVaultId,
              let keyMaterial = try? keychainStore.loadKey(forVaultId: vaultId) else {
            throw KeychainError.notFound
        }

        let key = try keyManager.keyFromBase64(keyMaterial)
        let vaultKey = keyManager.generateVaultKey(vaultId: vaultId, key: key)
        let data = try JSONEncoder.default.encode(vaultKey)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("别看我-密钥-\(dateStr).bkwkey")
        try data.write(to: tempURL)
        return tempURL
    }

    // MARK: - Note CRUD

    /// 创建笔记。`isEncrypted = true` 时创建加密笔记，否则创建明文笔记。返回创建好的 Note。
    @discardableResult
    func createNote(body: String, isEncrypted: Bool) async throws -> Note {
        guard let vaultId = currentVaultId else { throw VaultError.notReady }

        let noteId = UUID().uuidString
        let now = Date()

        if isEncrypted {
            guard let key = currentKey else { throw VaultError.keyNotLoaded }

            let payload = PlainNotePayload(body: body, createdAt: now, updatedAt: now)
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

            let note = Note(from: payload, noteId: noteId, vaultId: vaultId)
            decryptedNotes.insert(note, at: 0)
            return note
        } else {
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
                updatedAt: now,
                isEncrypted: false
            )
            plainNotes.insert(note, at: 0)
            return note
        }
    }

    /// 更新笔记。明文笔记编辑后仍为明文，加密笔记编辑后仍为加密。
    func updateNote(_ note: Note, body: String) async throws {
        guard let vaultId = currentVaultId else { throw VaultError.notReady }
        let now = Date()

        if note.isEncrypted {
            guard let key = currentKey else { throw VaultError.keyNotLoaded }

            let payload = PlainNotePayload(body: body, createdAt: note.createdAt, updatedAt: now)
            let noteFile = try cryptoService.encryptToNoteFile(
                noteId: note.id,
                vaultId: vaultId,
                payload: payload,
                key: key
            )

            guard let url = storage.noteFileURL(for: note.id) else {
                throw StorageError.iCloudUnavailable
            }

            // 多设备冲突检测：磁盘版本更新时生成冲突副本
            if let diskFile = try? storage.loadNoteFile(at: url), diskFile.updatedAt > note.updatedAt {
                _ = try storage.createConflictCopy(for: url)
            }

            try storage.saveNoteFile(noteFile, at: url)

            if let index = decryptedNotes.firstIndex(where: { $0.id == note.id }) {
                decryptedNotes[index] = Note(
                    id: note.id,
                    vaultId: vaultId,
                    body: body,
                    createdAt: note.createdAt,
                    updatedAt: now,
                    isEncrypted: true
                )
            }
        } else {
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

            if let diskFile = try? storage.loadPlainNoteFile(at: url), diskFile.updatedAt > note.updatedAt {
                _ = try storage.createPlainConflictCopy(for: url)
            }

            try storage.savePlainNoteFile(plainFile, at: url)

            if let index = plainNotes.firstIndex(where: { $0.id == note.id }) {
                plainNotes[index] = Note(
                    id: note.id,
                    vaultId: vaultId,
                    body: body,
                    createdAt: note.createdAt,
                    updatedAt: now,
                    isEncrypted: false
                )
            }
        }
    }

    /// 删除笔记：移动到 trash/ 并写入 deleted_at / purge_after / original_location。
    func deleteNote(_ note: Note) async throws {
        let now = Date()
        let purgeAfter = now.addingTimeInterval(30 * 86400)
        let location = NoteLocation.root

        if note.isEncrypted {
            guard let srcURL = storage.noteFileURL(for: note.id),
                  FileManager.default.fileExists(atPath: srcURL.path) else { return }
            guard let trashURL = storage.trashNoteFileURL(for: note.id) else {
                throw StorageError.iCloudUnavailable
            }

            // 先读取原文件，写入回收站元数据后再移动
            let file = try storage.loadNoteFile(at: srcURL)
            let trashedFile = EncryptedNoteFile(
                version: file.version,
                app: file.app,
                type: file.type,
                noteId: file.noteId,
                vaultId: file.vaultId,
                createdAt: file.createdAt,
                updatedAt: file.updatedAt,
                encryption: file.encryption,
                payload: file.payload,
                deletedAt: now,
                purgeAfter: purgeAfter,
                originalLocation: location
            )
            try storage.saveNoteFile(trashedFile, at: trashURL)
            try storage.permanentlyDeleteFile(at: srcURL)

            decryptedNotes.removeAll { $0.id == note.id }
            lockedEncryptedNotes.removeAll { $0.id == note.id }
        } else {
            guard let srcURL = storage.plainNoteFileURL(for: note.id),
                  FileManager.default.fileExists(atPath: srcURL.path) else { return }
            guard let trashURL = storage.trashPlainNoteFileURL(for: note.id) else {
                throw StorageError.iCloudUnavailable
            }

            let file = try storage.loadPlainNoteFile(at: srcURL)
            let trashedFile = PlainNoteFile(
                version: file.version,
                app: file.app,
                type: file.type,
                noteId: file.noteId,
                vaultId: file.vaultId,
                createdAt: file.createdAt,
                updatedAt: file.updatedAt,
                body: file.body,
                deletedAt: now,
                purgeAfter: purgeAfter,
                originalLocation: location
            )
            try storage.savePlainNoteFile(trashedFile, at: trashURL)
            try storage.permanentlyDeleteFile(at: srcURL)

            plainNotes.removeAll { $0.id == note.id }
        }

        trashNotes = try loadTrashNotes()
    }

    /// 删除未解密加密笔记（通过 EncryptedNoteInfo）。
    func deleteLockedNote(_ info: EncryptedNoteInfo) async throws {
        let now = Date()
        let purgeAfter = now.addingTimeInterval(30 * 86400)
        let location = NoteLocation.root

        let file = try storage.loadNoteFile(at: info.url)
        guard let trashURL = storage.trashNoteFileURL(for: file.noteId) else {
            throw StorageError.iCloudUnavailable
        }
        let trashedFile = EncryptedNoteFile(
            version: file.version,
            app: file.app,
            type: file.type,
            noteId: file.noteId,
            vaultId: file.vaultId,
            createdAt: file.createdAt,
            updatedAt: file.updatedAt,
            encryption: file.encryption,
            payload: file.payload,
            deletedAt: now,
            purgeAfter: purgeAfter,
            originalLocation: location
        )
        try storage.saveNoteFile(trashedFile, at: trashURL)
        try storage.permanentlyDeleteFile(at: info.url)

        lockedEncryptedNotes.removeAll { $0.id == info.id }
        trashNotes = try loadTrashNotes()
    }

    // MARK: - Trash

    /// 恢复回收站笔记到主列表。
    func restoreTrashNote(_ trashNote: TrashNote) async throws {
        if trashNote.isEncrypted {
            guard let restoreURL = storage.noteFileURL(for: trashNote.id) else {
                throw StorageError.iCloudUnavailable
            }
            let file = try storage.loadNoteFile(at: trashNote.url)
            let restoredFile = EncryptedNoteFile(
                version: file.version,
                app: file.app,
                type: file.type,
                noteId: file.noteId,
                vaultId: file.vaultId,
                createdAt: file.createdAt,
                updatedAt: file.updatedAt,
                encryption: file.encryption,
                payload: file.payload,
                deletedAt: nil,
                purgeAfter: nil,
                originalLocation: nil
            )
            try storage.saveNoteFile(restoredFile, at: restoreURL)
            try storage.permanentlyDeleteFile(at: trashNote.url)

            // 重新加载加密笔记列表
            if let key = currentKey {
                if let note = try? cryptoService.decryptNote(file: restoredFile, using: key) {
                    decryptedNotes.insert(note, at: 0)
                }
            } else {
                lockedEncryptedNotes.insert(makeLockedInfo(from: restoredFile, url: restoreURL), at: 0)
            }
        } else {
            guard let restoreURL = storage.plainNoteFileURL(for: trashNote.id) else {
                throw StorageError.iCloudUnavailable
            }
            let file = try storage.loadPlainNoteFile(at: trashNote.url)
            let restoredFile = PlainNoteFile(
                version: file.version,
                app: file.app,
                type: file.type,
                noteId: file.noteId,
                vaultId: file.vaultId,
                createdAt: file.createdAt,
                updatedAt: file.updatedAt,
                body: file.body,
                deletedAt: nil,
                purgeAfter: nil,
                originalLocation: nil
            )
            try storage.savePlainNoteFile(restoredFile, at: restoreURL)
            try storage.permanentlyDeleteFile(at: trashNote.url)

            plainNotes.insert(restoredFile.toNote(), at: 0)
        }

        trashNotes.removeAll { $0.id == trashNote.id }
    }

    /// 永久删除单条回收站笔记。
    func permanentlyDeleteTrashNote(_ trashNote: TrashNote) async throws {
        try storage.permanentlyDeleteFile(at: trashNote.url)
        trashNotes.removeAll { $0.id == trashNote.id }
    }

    /// 清空回收站。
    func emptyTrash() async throws {
        try storage.emptyTrash()
        trashNotes = []
    }

    /// 清理过期（超过 30 天）的回收站笔记。
    func purgeExpiredTrash() async {
        let now = Date()
        let encURLs = (try? storage.listTrashNoteFiles()) ?? []
        for url in encURLs {
            if let file = try? storage.loadNoteFile(at: url),
               let purgeAfter = file.purgeAfter, purgeAfter <= now {
                try? storage.permanentlyDeleteFile(at: url)
            }
        }
        let plainURLs = (try? storage.listTrashPlainNoteFiles()) ?? []
        for url in plainURLs {
            if let file = try? storage.loadPlainNoteFile(at: url),
               let purgeAfter = file.purgeAfter, purgeAfter <= now {
                try? storage.permanentlyDeleteFile(at: url)
            }
        }
    }

    // MARK: - Scene phase

    /// App 进入后台时调用：清空内存中的密钥与已解密笔记，加密笔记回到乱码态。
    func handleEnterBackground() {
        guard settings.autoUnloadKeyOnForeground == false else { return }
        // 默认不清空密钥，仅由 AppLockStore 显示隐私遮罩
    }

    /// App 回到前台时调用：若开启自动卸载密钥，则卸载密钥。
    func handleEnterForeground() async {
        await purgeExpiredTrash()
        if settings.autoUnloadKeyOnForeground {
            try? await unloadKey()
        }
    }
}

/// 首页列表项：可读笔记或未解密加密笔记。
enum NoteListItem: Identifiable, Equatable {
    case readable(Note)
    case locked(EncryptedNoteInfo)

    var id: String {
        switch self {
        case .readable(let note): return note.id
        case .locked(let info): return info.id
        }
    }
}

enum VaultError: Error, LocalizedError {
    case notReady
    case keyNotLoaded

    var errorDescription: String? {
        switch self {
        case .notReady: return "加密空间未就绪"
        case .keyNotLoaded: return "密钥未加载，无法创建或编辑加密笔记"
        }
    }
}
