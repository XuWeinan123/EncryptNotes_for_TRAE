import XCTest
import CryptoKit
import Compression
@testable import EncryptNotes

final class VaultStoreTests: XCTestCase {

    // MARK: - 明文笔记

    @MainActor
    func testCreatePlainNoteWithoutKey() async throws {
        let store = VaultStore(storage: LocalFallbackStorage.shared)
        store.configureForTesting(vaultId: "test-vault-plain")

        try await store.createNote(body: "未导入密钥时添加的笔记", isEncrypted: false)

        XCTAssertEqual(store.plainNotes.count, 1)
        XCTAssertEqual(store.plainNotes.first?.body, "未导入密钥时添加的笔记")
        XCTAssertFalse(store.plainNotes.first?.isEncrypted ?? true)
    }

    @MainActor
    func testCreateEncryptedNoteRequiresKey() async throws {
        let store = VaultStore(storage: LocalFallbackStorage.shared)
        store.configureForTesting(vaultId: "test-vault-enc")

        // 无密钥时创建加密笔记应失败
        do {
            try await store.createNote(body: "加密内容", isEncrypted: true)
            XCTFail("无密钥时不应创建加密笔记")
        } catch VaultError.keyNotLoaded {
            // 预期
        } catch {
            XCTFail("应抛出 keyNotLoaded，实际：\(error)")
        }
    }

    @MainActor
    func testCreateEncryptedNoteWithKey() async throws {
        let store = VaultStore(storage: LocalFallbackStorage.shared)
        let key = SymmetricKey(size: .bits256)
        store.configureForTesting(vaultId: "test-vault-enc-key", key: key)

        try await store.createNote(body: "加密笔记内容", isEncrypted: true)

        XCTAssertEqual(store.decryptedNotes.count, 1)
        XCTAssertEqual(store.decryptedNotes.first?.body, "加密笔记内容")
        XCTAssertTrue(store.decryptedNotes.first?.isEncrypted ?? false)
    }

    // MARK: - 移除 Free 限制

    @MainActor
    func testNoFreeLimit() async throws {
        let store = VaultStore(storage: LocalFallbackStorage.shared)
        store.configureForTesting(vaultId: "test-vault-nolimit")

        // 创建超过 20 条明文笔记，不应抛出 freeLimitReached
        for i in 0..<25 {
            try await store.createNote(body: "笔记 \(i)", isEncrypted: false)
        }
        XCTAssertEqual(store.plainNotes.count, 25)
    }

    // MARK: - 标签解析

    @MainActor
    func testTagParserSpaceDelimiter() {
        let tags = TagParser.tags(in: "今天想到一个产品点 #产品 #隐私")
        XCTAssertEqual(tags, ["#产品", "#隐私"])
    }

    @MainActor
    func testTagParserNewlineDelimiter() {
        let tags = TagParser.tags(in: "第一行\n#标签1\n第二行 #标签2")
        XCTAssertEqual(tags, ["#标签1", "#标签2"])
    }

    @MainActor
    func testTagParserEndOfText() {
        let tags = TagParser.tags(in: "正文结尾的标签 #结尾")
        XCTAssertEqual(tags, ["#结尾"])
    }

    @MainActor
    func testTagParserNoSubtags() {
        let tags = TagParser.tags(in: "#产品/隐私 不拆分")
        XCTAssertEqual(tags, ["#产品/隐私"])
    }

    @MainActor
    func testTagsOnlyFromReadableNotes() {
        let store = VaultStore(storage: LocalFallbackStorage.shared)
        let plain = Note(id: "p1", vaultId: "v", body: "明文 #标签A", isEncrypted: false)
        let encrypted = Note(id: "e1", vaultId: "v", body: "加密 #标签B", isEncrypted: true)
        store.configureForTesting(vaultId: "v", decryptedNotes: [encrypted], plainNotes: [plain])

        let tags = store.allTags
        XCTAssertTrue(tags.contains { $0.tag == "#标签A" })
        XCTAssertTrue(tags.contains { $0.tag == "#标签B" })
    }

    // MARK: - 合并排序

    @MainActor
    func testReadableNotesMergesAndSorts() {
        let store = VaultStore(storage: LocalFallbackStorage.shared)
        let encrypted = Note(
            id: "enc-1", vaultId: "v", body: "加密",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            isEncrypted: true
        )
        let plain = Note(
            id: "plain-1", vaultId: "v", body: "明文",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 300),
            isEncrypted: false
        )
        store.configureForTesting(vaultId: "v", decryptedNotes: [encrypted], plainNotes: [plain])

        let readable = store.readableNotes
        XCTAssertEqual(readable.count, 2)
        XCTAssertEqual(readable.first?.id, "plain-1")
    }

    @MainActor
    func testNoteCountDerivedState() {
        let store = VaultStore(storage: LocalFallbackStorage.shared)
        let plain = Note(id: "p1", vaultId: "v", body: "明文", isEncrypted: false)
        let encrypted = Note(id: "e1", vaultId: "v", body: "加密", isEncrypted: true)
        let locked = EncryptedNoteInfo(
            id: "l1",
            url: URL(fileURLWithPath: "/tmp/l1.bkwenc.json"),
            ciphertextPreview: "cipher",
            fileSize: 12,
            updatedAt: Date()
        )
        store.configureForTesting(
            vaultId: "v",
            decryptedNotes: [encrypted],
            plainNotes: [plain],
            lockedEncryptedNotes: [locked]
        )

        XCTAssertEqual(store.readableNoteCount, 2)
        XCTAssertEqual(store.encryptedNoteCount, 2)
        XCTAssertEqual(store.lockedNoteCount, 1)
        XCTAssertEqual(store.totalNoteCount, 3)
    }

    // MARK: - 回收站

    @MainActor
    func testDeletePlainNoteMovesToTrash() async throws {
        let store = VaultStore(storage: LocalFallbackStorage.shared)
        let storage = LocalFallbackStorage.shared
        try await storage.initializeVault()

        let plainNote = Note(id: "plain-trash", vaultId: "v", body: "待删除", isEncrypted: false)
        store.configureForTesting(vaultId: "v", plainNotes: [plainNote])

        guard let url = storage.plainNoteFileURL(for: plainNote.id) else {
            XCTFail("无法获取明文笔记 URL")
            return
        }
        let file = PlainNoteFile(
            noteId: plainNote.id, vaultId: "v",
            createdAt: plainNote.createdAt, updatedAt: plainNote.updatedAt,
            body: plainNote.body
        )
        try storage.savePlainNoteFile(file, at: url)

        try await store.deleteNote(plainNote)

        XCTAssertTrue(store.plainNotes.isEmpty, "主列表应已移除")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "notes/ 中文件应已删除")
        XCTAssertEqual(store.trashNotes.count, 1, "回收站应有一条")
    }

    @MainActor
    func testEmptyTrash() async throws {
        let store = VaultStore(storage: LocalFallbackStorage.shared)
        let storage = LocalFallbackStorage.shared
        try await storage.initializeVault()
        try? storage.emptyTrash()

        let note = Note(id: "empty-trash", vaultId: "v", body: "x", isEncrypted: false)
        store.configureForTesting(vaultId: "v", plainNotes: [note])

        guard let url = storage.plainNoteFileURL(for: note.id) else { return }
        let file = PlainNoteFile(
            noteId: note.id, vaultId: "v",
            createdAt: note.createdAt, updatedAt: note.updatedAt,
            body: note.body
        )
        try storage.savePlainNoteFile(file, at: url)

        try await store.deleteNote(note)
        XCTAssertEqual(store.trashNotes.count, 1)

        try await store.emptyTrash()
        XCTAssertEqual(store.trashNotes.count, 0)
    }

    // MARK: - 重置密钥

    @MainActor
    func testResetKeyDeletesEncryptedKeepsPlain() async throws {
        let store = VaultStore(storage: LocalFallbackStorage.shared)
        let storage = LocalFallbackStorage.shared
        try await storage.initializeVault()

        let key = SymmetricKey(size: .bits256)
        store.configureForTesting(vaultId: "reset-vault", key: key)

        // 创建一条加密笔记 + 一条明文笔记
        try await store.createNote(body: "加密", isEncrypted: true)
        try await store.createNote(body: "明文", isEncrypted: false)

        XCTAssertEqual(store.decryptedNotes.count, 1)
        XCTAssertEqual(store.plainNotes.count, 1)

        try await store.resetKey()

        // 加密笔记应被删除，明文笔记应保留
        XCTAssertTrue(store.decryptedNotes.isEmpty, "加密笔记应被删除")
        XCTAssertEqual(store.plainNotes.count, 1, "明文笔记应保留")
        XCTAssertTrue(store.isKeyLoaded, "应已加载新密钥")
    }

    // MARK: - 卸载密钥

    @MainActor
    func testUnloadKeyClearsDecryptedNotes() async throws {
        let store = VaultStore(storage: LocalFallbackStorage.shared)
        let storage = LocalFallbackStorage.shared
        try await storage.initializeVault()

        let key = SymmetricKey(size: .bits256)
        store.configureForTesting(vaultId: "unload-vault", key: key)

        try await store.createNote(body: "加密笔记", isEncrypted: true)
        XCTAssertEqual(store.decryptedNotes.count, 1)

        try await store.unloadKey()

        XCTAssertFalse(store.isKeyLoaded)
        XCTAssertTrue(store.decryptedNotes.isEmpty)
        // 加密笔记应作为乱码卡片存在
        XCTAssertEqual(store.lockedEncryptedNotes.count, 1)
    }

    // MARK: - 模式持久化

    @MainActor
    func testPreferredNoteModeDefaultsToPlain() {
        let settings = SettingsStore.shared
        settings.resetForTesting()
        XCTAssertEqual(settings.preferredNoteMode, .plain)
    }

    @MainActor
    func testPreferredNoteModePersists() {
        let settings = SettingsStore.shared
        settings.resetForTesting()
        settings.preferredNoteMode = .encrypted
        XCTAssertEqual(settings.preferredNoteMode, .encrypted)
    }

    // MARK: - 默认笔记 seeding

    @MainActor
    func testDefaultNotesSeededOnce() async throws {
        let store = VaultStore(storage: LocalFallbackStorage.shared)
        let settings = SettingsStore.shared
        settings.resetForTesting()

        // 清空 notes 目录
        let storage = LocalFallbackStorage.shared
        try await storage.initializeVault()
        if let notesURL = storage.containerURL?.appendingPathComponent("notes") {
            let contents = (try? FileManager.default.contentsOfDirectory(at: notesURL, includingPropertiesForKeys: nil)) ?? []
            for file in contents { try? FileManager.default.removeItem(at: file) }
        }

        await store.initialize()

        // 首次启动应创建 3 条默认笔记
        XCTAssertEqual(store.plainNotes.count, 3, "应创建 3 条默认笔记")

        // 再次 initialize 不应重复创建
        let countBefore = store.plainNotes.count
        await store.initialize()
        XCTAssertEqual(store.plainNotes.count, countBefore, "不应重复创建默认笔记")
    }

    // MARK: - 批量删除

    @MainActor
    func testBatchDeletePlainNotesMovesToTrash() async throws {
        let store = VaultStore(storage: LocalFallbackStorage.shared)
        let storage = LocalFallbackStorage.shared
        try await storage.initializeVault()
        try? storage.emptyTrash()

        store.configureForTesting(vaultId: "batch-plain-vault")

        let n1 = try await store.createNote(body: "明文笔记一", isEncrypted: false)
        let n2 = try await store.createNote(body: "明文笔记二", isEncrypted: false)
        let n3 = try await store.createNote(body: "明文笔记三", isEncrypted: false)

        XCTAssertEqual(store.plainNotes.count, 3)

        let items: [NoteListItem] = [
            .readable(n1),
            .readable(n2)
        ]
        let result = try await store.batchDeleteNotes(items)

        XCTAssertEqual(result.deleted, 2)
        XCTAssertEqual(result.errors, 0)
        XCTAssertEqual(store.plainNotes.count, 1, "应只保留一条")
        XCTAssertEqual(store.plainNotes.first?.id, n3.id)
        XCTAssertEqual(store.trashNotes.count, 2, "回收站应有两条")
    }

    @MainActor
    func testBatchDeleteEncryptedNotesWithKeyMovesToTrash() async throws {
        let store = VaultStore(storage: LocalFallbackStorage.shared)
        let storage = LocalFallbackStorage.shared
        try await storage.initializeVault()
        try? storage.emptyTrash()

        let key = SymmetricKey(size: .bits256)
        store.configureForTesting(vaultId: "batch-enc-vault", key: key)

        let e1 = try await store.createNote(body: "加密笔记一", isEncrypted: true)
        let e2 = try await store.createNote(body: "加密笔记二", isEncrypted: true)
        let p1 = try await store.createNote(body: "明文笔记", isEncrypted: false)

        XCTAssertEqual(store.decryptedNotes.count, 2)
        XCTAssertEqual(store.plainNotes.count, 1)

        let items: [NoteListItem] = [
            .readable(e1),
            .readable(e2)
        ]
        let result = try await store.batchDeleteNotes(items)

        XCTAssertEqual(result.deleted, 2)
        XCTAssertEqual(result.errors, 0)
        XCTAssertTrue(store.decryptedNotes.isEmpty, "加密笔记应被删除")
        XCTAssertEqual(store.plainNotes.count, 1, "明文笔记应保留")
        XCTAssertEqual(store.trashNotes.count, 2, "回收站应有两条加密笔记")
    }

    // MARK: - 导出

    @MainActor
    func testExportOnlyIncludesPlainNotesSkipsEncrypted() async throws {
        let store = VaultStore(storage: LocalFallbackStorage.shared)
        let storage = LocalFallbackStorage.shared
        try await storage.initializeVault()

        let key = SymmetricKey(size: .bits256)
        store.configureForTesting(vaultId: "export-vault", key: key)

        try await store.createNote(body: "明文笔记内容 A", isEncrypted: false)
        try await store.createNote(body: "明文笔记内容 B", isEncrypted: false)
        try await store.createNote(body: "加密笔记内容", isEncrypted: true)

        XCTAssertEqual(store.plainNotes.count, 2)
        XCTAssertEqual(store.decryptedNotes.count, 1)

        let result = try store.exportReadableNotesAsZip()

        XCTAssertEqual(result.exportedCount, 2, "只应导出 2 条明文笔记")
        XCTAssertEqual(result.skippedCount, 1, "应跳过 1 条加密笔记")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))

        var extractedMarkdown: [String] = []
        if let archive = Archive(url: result.url, accessMode: .read) {
            for entry in archive {
                var data = Data()
                _ = try archive.extract(entry) { chunk in
                    data.append(chunk)
                    return chunk.count
                }
                if let content = String(data: data, encoding: .utf8) {
                    extractedMarkdown.append(content)
                }
            }
        }

        XCTAssertEqual(extractedMarkdown.count, 2, "zip 中应包含 2 个 Markdown 文件")

        let allContent = extractedMarkdown.joined(separator: "\n")
        XCTAssertTrue(allContent.contains("明文笔记内容 A"))
        XCTAssertTrue(allContent.contains("明文笔记内容 B"))
        XCTAssertFalse(allContent.contains("加密笔记内容"), "加密笔记内容不应出现在导出中")
    }

    @MainActor
    func testBatchCopyOnlyCopiesPlainNotes() async throws {
        let store = VaultStore(storage: LocalFallbackStorage.shared)
        let storage = LocalFallbackStorage.shared
        try await storage.initializeVault()

        let key = SymmetricKey(size: .bits256)
        store.configureForTesting(vaultId: "copy-vault", key: key)

        let p1 = try await store.createNote(body: "明文复制测试", isEncrypted: false)
        let e1 = try await store.createNote(body: "加密不应复制", isEncrypted: true)

        let items: [NoteListItem] = [
            .readable(p1),
            .readable(e1)
        ]

        #if os(iOS)
        let result = store.batchCopyNotesToClipboard(items)
        XCTAssertEqual(result.copied, 1, "只应复制 1 条明文笔记")
        XCTAssertEqual(result.skipped, 1, "应跳过 1 条加密笔记")
        #endif
    }
}
