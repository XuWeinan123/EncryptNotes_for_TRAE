import XCTest
import CryptoKit
@testable import EncryptNotes

final class VaultStoreTests: XCTestCase {
    private func savedNoteURL(in tmpDir: URL, noteId: String) throws -> URL {
        let files = try FileManager.default.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil)
        guard let url = files.first(where: { $0.pathExtension == "md" && $0.lastPathComponent.contains(noteId) }) else {
            XCTFail("应能找到包含 noteId 的 Markdown 文件")
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }

    @MainActor
    func testCreatePlainNoteWithoutKey() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_plain_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "test-vault-plain")

        try await store.createNote(body: "未导入密钥时添加的笔记", isEncrypted: false)

        XCTAssertEqual(store.plainNotes.count, 1)
        XCTAssertEqual(store.plainNotes.first?.body, "未导入密钥时添加的笔记")
        XCTAssertFalse(store.plainNotes.first?.isEncrypted ?? true)

        let noteId = store.plainNotes.first!.id
        let mdURL = try savedNoteURL(in: tmpDir, noteId: noteId)
        XCTAssertTrue(mdURL.lastPathComponent.hasPrefix("未导入密钥时添加的笔记-"))
        let mdData = try Data(contentsOf: mdURL)
        let mdContent = String(data: mdData, encoding: .utf8) ?? ""
        XCTAssertTrue(mdContent.contains("未导入密钥时添加的笔记"), "Markdown 文件应包含正文")
        XCTAssertTrue(mdContent.contains("note_id:"), "Markdown 文件应包含 frontmatter")

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testCreateNoteWithHeadingTitleOmitsHashFromFileName() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_heading_filename_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "test-vault-heading")

        let note = try await store.createNote(body: "# Hello\nBody", isEncrypted: false)

        let mdURL = try savedNoteURL(in: tmpDir, noteId: note.id)
        XCTAssertTrue(mdURL.lastPathComponent.hasPrefix("Hello-"))
        XCTAssertFalse(mdURL.lastPathComponent.hasPrefix("#"))

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testRenameNoteChangesFileNameButLeavesMarkdownContentUntouched() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_ai_title_rename_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "test-vault-ai-title")

        let originalBody = "第一行正文\n\n更多内容"
        let note = try await store.createNote(body: originalBody, isEncrypted: false)
        let oldURL = try savedNoteURL(in: tmpDir, noteId: note.id)
        let oldData = try Data(contentsOf: oldURL)
        let oldContent = String(data: oldData, encoding: .utf8) ?? ""

        try await store.renameNote(note, title: "AI 总结/标题?")

        let newURL = try savedNoteURL(in: tmpDir, noteId: note.id)
        XCTAssertNotEqual(oldURL.lastPathComponent, newURL.lastPathComponent)
        XCTAssertTrue(newURL.lastPathComponent.hasPrefix("AI 总结-标题-"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))

        let newData = try Data(contentsOf: newURL)
        let newContent = String(data: newData, encoding: .utf8) ?? ""
        XCTAssertEqual(newContent, oldContent)
        XCTAssertTrue(newContent.contains(originalBody))
        XCTAssertEqual(store.displayTitle(for: note), "AI 总结-标题")

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testCreateEncryptedNoteRequiresKey() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_encreq_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "test-vault-enc")

        do {
            try await store.createNote(body: "加密内容", isEncrypted: true)
            XCTFail("无密钥时不应创建加密笔记")
        } catch VaultError.keyNotLoaded {
        } catch {
            XCTFail("应抛出 keyNotLoaded，实际：\(error)")
        }

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testCreateEncryptedNoteWithKey() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_enc_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let key = SymmetricKey(size: .bits256)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "test-vault-enc-key", key: key)

        try await store.createNote(body: "加密笔记内容", isEncrypted: true)

        XCTAssertEqual(store.decryptedNotes.count, 1)
        XCTAssertEqual(store.decryptedNotes.first?.body, "加密笔记内容")
        XCTAssertTrue(store.decryptedNotes.first?.isEncrypted ?? false)

        let noteId = store.decryptedNotes.first!.id
        let mdURL = try savedNoteURL(in: tmpDir, noteId: noteId)
        XCTAssertTrue(mdURL.lastPathComponent.hasPrefix("加密笔记内容-"))
        let mdData = try Data(contentsOf: mdURL)
        let mdContent = String(data: mdData, encoding: .utf8) ?? ""
        XCTAssertTrue(mdContent.contains("bkwenc:v1:"), "加密笔记文件 body 应为密文")
        XCTAssertFalse(mdContent.contains("加密笔记内容"), "加密笔记文件不应包含明文正文")

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testNoFreeLimit() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_nolimit_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "test-vault-nolimit")

        for i in 0..<25 {
            try await store.createNote(body: "笔记 \(i)", isEncrypted: false)
        }
        XCTAssertEqual(store.plainNotes.count, 25)

        try? FileManager.default.removeItem(at: tmpDir)
    }

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
        let store = VaultStore(storage: try? TemporaryStorage(baseURL: FileManager.default.temporaryDirectory))
        let plain = Note(id: "p1", body: "明文 #标签A", isEncrypted: false)
        let encrypted = Note(id: "e1", body: "加密 #标签B", isEncrypted: true)
        store.configureForTesting(vaultId: "v", decryptedNotes: [encrypted], plainNotes: [plain])

        let tags = store.allTags
        XCTAssertTrue(tags.contains { $0.tag == "#标签A" })
        XCTAssertTrue(tags.contains { $0.tag == "#标签B" })
    }

    @MainActor
    func testReadableNotesMergesAndSorts() {
        let store = VaultStore(storage: try? TemporaryStorage(baseURL: FileManager.default.temporaryDirectory))
        let encrypted = Note(
            id: "enc-1", body: "加密",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            isEncrypted: true
        )
        let plain = Note(
            id: "plain-1", body: "明文",
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
        let store = VaultStore(storage: try? TemporaryStorage(baseURL: FileManager.default.temporaryDirectory))
        let plain = Note(id: "p1", body: "明文", isEncrypted: false)
        let encrypted = Note(id: "e1", body: "加密", isEncrypted: true)
        let locked = EncryptedNoteInfo(
            id: "l1",
            url: URL(fileURLWithPath: "/tmp/l1.md"),
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

    @MainActor
    func testUpdateNotePreservesCreatedAt() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_update_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "test-update")

        let note = try await store.createNote(body: "原始内容", isEncrypted: false)
        let originalCreated = note.createdAt

        try await Task.sleep(nanoseconds: 100_000_000)
        try await store.updateNote(note, body: "更新后的内容")

        XCTAssertEqual(store.plainNotes.count, 1)
        XCTAssertEqual(store.plainNotes.first?.body, "更新后的内容")
        XCTAssertEqual(store.plainNotes.first?.createdAt, originalCreated)
        XCTAssertGreaterThan(store.plainNotes.first!.updatedAt, originalCreated)

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testDeletePlainNoteMovesToTrash() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_delete_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        try await storage.initializeVault()

        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "v")

        let plainNote = try await store.createNote(body: "待删除", isEncrypted: false)
        let noteURL = try savedNoteURL(in: tmpDir, noteId: plainNote.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: noteURL.path))

        try await store.deleteNote(plainNote)

        XCTAssertTrue(store.plainNotes.isEmpty, "主列表应已移除")
        XCTAssertFalse(FileManager.default.fileExists(atPath: noteURL.path), "根目录中的笔记文件应已删除")
        let trashURL = tmpDir.appendingPathComponent("trash").appendingPathComponent("\(plainNote.id).md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashURL.path), "trash/ 中应有文件")

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testEmptyTrash() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_emptytrash_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        try await storage.initializeVault()

        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "v")

        let note = try await store.createNote(body: "x", isEncrypted: false)
        try await store.deleteNote(note)

        try await Task.sleep(nanoseconds: 50_000_000)
        try await store.emptyTrash()

        let trashURL = tmpDir.appendingPathComponent("trash")
        let contents = try FileManager.default.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil)
        let mdFiles = contents.filter { $0.lastPathComponent.hasSuffix(".md") }
        XCTAssertTrue(mdFiles.isEmpty, "回收站应清空")

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testResetKeyDeletesEncryptedKeepsPlain() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_reset_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        try await storage.initializeVault()

        let key = SymmetricKey(size: .bits256)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "reset-vault", key: key)

        try await store.createNote(body: "加密", isEncrypted: true)
        try await store.createNote(body: "明文", isEncrypted: false)

        XCTAssertEqual(store.decryptedNotes.count, 1)
        XCTAssertEqual(store.plainNotes.count, 1)

        try await store.resetKey()

        XCTAssertTrue(store.decryptedNotes.isEmpty, "加密笔记应被删除")
        XCTAssertEqual(store.plainNotes.count, 1, "明文笔记应保留")
        XCTAssertTrue(store.isKeyLoaded, "应已加载新密钥")

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testUnloadKeyClearsDecryptedNotes() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_unload_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        try await storage.initializeVault()

        let key = SymmetricKey(size: .bits256)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "unload-vault", key: key)

        try await store.createNote(body: "加密笔记", isEncrypted: true)
        XCTAssertEqual(store.decryptedNotes.count, 1)

        try await store.unloadKey()

        XCTAssertFalse(store.isKeyLoaded)
        XCTAssertTrue(store.decryptedNotes.isEmpty)

        try? FileManager.default.removeItem(at: tmpDir)
    }

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

    @MainActor
    func testBatchDeletePlainNotesMovesToTrash() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_batchdel_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        try await storage.initializeVault()

        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "batch-plain-vault")

        let n1 = try await store.createNote(body: "明文笔记一", isEncrypted: false)
        let n2 = try await store.createNote(body: "明文笔记二", isEncrypted: false)
        let n3 = try await store.createNote(body: "明文笔记三", isEncrypted: false)

        XCTAssertEqual(store.plainNotes.count, 3)

        let items: [NoteListItem] = [.readable(n1), .readable(n2)]
        let result = try await store.batchDeleteNotes(items)

        XCTAssertEqual(result.deleted, 2)
        XCTAssertEqual(result.errors, 0)
        XCTAssertEqual(store.plainNotes.count, 1)
        XCTAssertEqual(store.plainNotes.first?.id, n3.id)

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testBatchDeleteEncryptedNotesWithKeyMovesToTrash() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_batchenc_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        try await storage.initializeVault()

        let key = SymmetricKey(size: .bits256)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "batch-enc-vault", key: key)

        let e1 = try await store.createNote(body: "加密笔记一", isEncrypted: true)
        let e2 = try await store.createNote(body: "加密笔记二", isEncrypted: true)
        _ = try await store.createNote(body: "明文笔记", isEncrypted: false)

        XCTAssertEqual(store.decryptedNotes.count, 2)
        XCTAssertEqual(store.plainNotes.count, 1)

        let items: [NoteListItem] = [.readable(e1), .readable(e2)]
        let result = try await store.batchDeleteNotes(items)

        XCTAssertEqual(result.deleted, 2)
        XCTAssertEqual(result.errors, 0)
        XCTAssertTrue(store.decryptedNotes.isEmpty)
        XCTAssertEqual(store.plainNotes.count, 1)

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testExportOnlyIncludesPlainNotesSkipsEncrypted() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_export_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        try await storage.initializeVault()

        let key = SymmetricKey(size: .bits256)
        let store = VaultStore(storage: storage)
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

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testBatchCopyOnlyCopiesPlainNotes() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_copy_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        try await storage.initializeVault()

        let key = SymmetricKey(size: .bits256)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "copy-vault", key: key)

        let p1 = try await store.createNote(body: "明文复制测试", isEncrypted: false)
        let e1 = try await store.createNote(body: "加密不应复制", isEncrypted: true)

        let items: [NoteListItem] = [.readable(p1), .readable(e1)]

        #if os(iOS)
        let result = store.batchCopyNotesToClipboard(items)
        XCTAssertEqual(result.copied, 1, "只应复制 1 条明文笔记")
        XCTAssertEqual(result.skipped, 1, "应跳过 1 条加密笔记")
        #endif

        try? FileManager.default.removeItem(at: tmpDir)
    }
}

private final class TemporaryStorage: VaultStorage, @unchecked Sendable {
    let fileManager = FileManager.default
    let _containerURL: URL

    var containerURL: URL? { _containerURL }
    var isAvailable: Bool { true }

    init(baseURL: URL) throws {
        self._containerURL = baseURL
        let directories = [
            baseURL,
            baseURL.appendingPathComponent("trash"),
            baseURL.appendingPathComponent(".meta")
        ]
        for directory in directories {
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
    }

    func initializeVault() async throws {
        let directories = [
            _containerURL,
            _containerURL.appendingPathComponent("trash"),
            _containerURL.appendingPathComponent(".meta")
        ]
        for directory in directories {
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
    }

    func loadIndex() throws -> NoteIndex? {
        let url = _containerURL.appendingPathComponent("notes.json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.default.decode(NoteIndex.self, from: data)
    }

    func saveIndex(_ index: NoteIndex) throws {
        let url = _containerURL.appendingPathComponent("notes.json")
        let data = try JSONEncoder.default.encode(index)
        try data.write(to: url, options: .atomic)
    }

    func loadMarkdownFile(at url: URL) throws -> MarkdownNoteFile {
        let data = try Data(contentsOf: url)
        return try MarkdownNoteFile.parse(from: data)
    }

    func saveMarkdownFile(_ file: MarkdownNoteFile, at url: URL) throws {
        let dir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let data = try file.render()
        try data.write(to: url, options: .atomic)
    }
}
