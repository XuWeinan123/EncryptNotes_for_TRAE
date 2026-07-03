import XCTest
import CryptoKit
@testable import EncryptNotes

final class VaultStoreTests: XCTestCase {
    private func savedNoteURL(in tmpDir: URL, noteId: String) throws -> URL {
        let indexURL = tmpDir.appendingPathComponent("notes.json")
        let data = try Data(contentsOf: indexURL)
        let index = try JSONDecoder.default.decode(NoteIndex.self, from: data)
        guard let entry = index.entry(for: noteId) else {
            XCTFail("notes.json 中应能找到笔记记录")
            throw CocoaError(.fileNoSuchFile)
        }
        return entry.location == .notes
            ? tmpDir.appendingPathComponent(entry.fileName)
            : tmpDir.appendingPathComponent(entry.location.rawValue).appendingPathComponent(entry.fileName)
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
        XCTAssertEqual(mdURL.lastPathComponent, "未导入密钥时添加的笔记.md")
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
        XCTAssertEqual(mdURL.lastPathComponent, "Hello.md")
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
        let oldFile = try storage.loadMarkdownFile(at: oldURL)

        try await store.renameNote(note, title: "AI 总结/标题?")

        let newURL = try savedNoteURL(in: tmpDir, noteId: note.id)
        XCTAssertNotEqual(oldURL.lastPathComponent, newURL.lastPathComponent)
        XCTAssertEqual(newURL.lastPathComponent, "AI 总结-标题.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))

        let newFile = try storage.loadMarkdownFile(at: newURL)
        XCTAssertEqual(newFile.body, oldFile.body)
        XCTAssertEqual(newFile.body, originalBody)
        XCTAssertEqual(store.displayTitle(for: note), "AI 总结-标题")

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testEditingTitledNotePreservesFileNameAndFrontmatterTitle() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_title_freeze_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "test-vault-title-freeze")

        let note = try await store.createNote(body: "第一版正文", isEncrypted: false)
        try await store.renameNote(note, title: "固定标题")
        let titledURL = try savedNoteURL(in: tmpDir, noteId: note.id)
        XCTAssertEqual(titledURL.lastPathComponent, "固定标题.md")

        try await store.updateNote(note, body: "第二版正文\n\n更多内容")

        let updatedURL = try savedNoteURL(in: tmpDir, noteId: note.id)
        XCTAssertEqual(updatedURL.lastPathComponent, "固定标题.md")
        XCTAssertEqual(titledURL, updatedURL)

        let updatedFile = try storage.loadMarkdownFile(at: updatedURL)
        XCTAssertEqual(updatedFile.title, "固定标题")
        XCTAssertEqual(updatedFile.body, "第二版正文\n\n更多内容")

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testDiscardEmptyNoteUsesCurrentBodySnapshot() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_empty_snapshot_discard_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "test-vault-empty-snapshot")

        let note = try await store.createNote(body: "稍后会清空", isEncrypted: false)
        let noteURL = try savedNoteURL(in: tmpDir, noteId: note.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: noteURL.path))

        try await store.discardEmptyNote(note, body: "\n \t")

        XCTAssertNil(try storage.loadIndex()?.entry(for: note.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: noteURL.path))
        XCTAssertFalse(store.plainNotes.contains { $0.id == note.id })

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
        XCTAssertEqual(mdURL.lastPathComponent, "加密笔记内容.md")
        let mdFile = try storage.loadMarkdownFile(at: mdURL)
        XCTAssertTrue(mdFile.body.contains("snenc:v1:"), "加密笔记文件 body 应为密文")
        XCTAssertFalse(mdFile.body.contains("加密笔记内容"), "加密笔记文件 body 不应包含明文正文")

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testExportKeyFileUsesSNKeyExtension() throws {
        let key = SymmetricKey(size: .bits256)
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_export_key_\(UUID().uuidString)")
        let store = VaultStore(storage: try TemporaryStorage(baseURL: tmpDir))
        store.configureForTesting(vaultId: "test-vault-export-key", key: key)

        let exportedURL = try store.exportKeyFile()

        XCTAssertEqual(exportedURL.pathExtension, "snkey")
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportedURL.path))
        try? FileManager.default.removeItem(at: exportedURL)
        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testEncryptNoteForEditingConvertsPlainNoteAndDecryptsFromDisk() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_editor_encrypt_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let key = SymmetricKey(size: .bits256)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "test-vault-editor-encrypt", key: key)

        let note = try await store.createNote(body: "需要加密的内容", isEncrypted: false)
        let result = try await store.encryptNoteForEditing(note, body: "需要加密的内容")

        XCTAssertTrue(result.note.isEncrypted)
        XCTAssertEqual(result.note.body, "需要加密的内容")
        XCTAssertTrue(store.plainNotes.isEmpty)
        XCTAssertEqual(store.decryptedNotes.first?.id, note.id)

        let entry = try XCTUnwrap(storage.loadIndex()?.entry(for: note.id))
        XCTAssertEqual(entry.mode, .encrypted)

        let mdURL = try savedNoteURL(in: tmpDir, noteId: note.id)
        let mdFile = try storage.loadMarkdownFile(at: mdURL)
        XCTAssertEqual(result.ciphertext, mdFile.body)
        XCTAssertTrue(mdFile.body.hasPrefix("snenc:v1:"))

        let encryptedFile = try storage.loadMarkdownFile(at: mdURL)
        XCTAssertFalse(encryptedFile.body.contains("需要加密的内容"))

        let decrypted = try await store.decryptEncryptedNoteBody(result.note)
        XCTAssertEqual(decrypted, "需要加密的内容")

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testUpdateNoteModeConvertsPlainToEncryptedAndBackToPlain() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_update_mode_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let key = SymmetricKey(size: .bits256)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "test-vault-update-mode", key: key)

        let plain = try await store.createNote(body: "转换模式", isEncrypted: false)
        let encrypted = try await store.updateNoteMode(plain, body: "转换模式", mode: .encrypted)

        XCTAssertTrue(encrypted.isEncrypted)
        XCTAssertTrue(store.plainNotes.isEmpty)
        XCTAssertEqual(store.decryptedNotes.first?.id, plain.id)
        XCTAssertEqual(try XCTUnwrap(storage.loadIndex()?.entry(for: plain.id)).mode, .encrypted)

        var mdURL = try savedNoteURL(in: tmpDir, noteId: plain.id)
        var mdContent = String(data: try Data(contentsOf: mdURL), encoding: .utf8) ?? ""
        XCTAssertTrue(mdContent.contains("snenc:v1:"))
        XCTAssertFalse(mdContent.contains("转换模式\n"))

        let restored = try await store.updateNoteMode(encrypted, body: "转换模式", mode: .plain)

        XCTAssertFalse(restored.isEncrypted)
        XCTAssertEqual(store.plainNotes.first?.id, plain.id)
        XCTAssertTrue(store.decryptedNotes.isEmpty)
        XCTAssertEqual(try XCTUnwrap(storage.loadIndex()?.entry(for: plain.id)).mode, .plain)

        mdURL = try savedNoteURL(in: tmpDir, noteId: plain.id)
        mdContent = String(data: try Data(contentsOf: mdURL), encoding: .utf8) ?? ""
        XCTAssertTrue(mdContent.contains("转换模式"))
        XCTAssertFalse(mdContent.contains("snenc:v1:"))

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testUpdateNoteModeFailsWithoutKeyAndDoesNotChangeFile() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_update_mode_no_key_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "test-vault-update-mode-no-key")

        let plain = try await store.createNote(body: "保持明文", isEncrypted: false)
        let beforeURL = try savedNoteURL(in: tmpDir, noteId: plain.id)
        let beforeContent = String(data: try Data(contentsOf: beforeURL), encoding: .utf8) ?? ""

        do {
            _ = try await store.updateNoteMode(plain, body: "保持明文", mode: .encrypted)
            XCTFail("缺少密钥时不应转为加密")
        } catch VaultError.keyNotLoaded {
        } catch {
            XCTFail("应抛出 keyNotLoaded，实际：\(error)")
        }

        XCTAssertEqual(try XCTUnwrap(storage.loadIndex()?.entry(for: plain.id)).mode, .plain)
        let afterURL = try savedNoteURL(in: tmpDir, noteId: plain.id)
        let afterContent = String(data: try Data(contentsOf: afterURL), encoding: .utf8) ?? ""
        XCTAssertEqual(afterContent, beforeContent)

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
            title: "锁定标题",
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
    func testEncryptedReadableNotesSearchTitleOnly() {
        let store = VaultStore(storage: try? TemporaryStorage(baseURL: FileManager.default.temporaryDirectory))
        let encrypted = Note(id: "e1", body: "# 项目标题\n隐藏正文关键词", isEncrypted: true)
        let plain = Note(id: "p1", body: "普通标题\n隐藏正文关键词", isEncrypted: false)
        store.configureForTesting(vaultId: "v", decryptedNotes: [encrypted], plainNotes: [plain])

        store.searchText = "隐藏正文关键词"
        XCTAssertEqual(store.filteredNotes, [.readable(plain)])

        store.searchText = "项目标题"
        XCTAssertEqual(store.filteredNotes, [.readable(encrypted)])
    }

    @MainActor
    func testLockedEncryptedNotesSearchTitleOnly() {
        let store = VaultStore(storage: try? TemporaryStorage(baseURL: FileManager.default.temporaryDirectory))
        let locked = EncryptedNoteInfo(
            id: "l1",
            url: URL(fileURLWithPath: "/tmp/l1.md"),
            title: "锁定项目标题",
            ciphertextPreview: "隐藏正文关键词",
            fileSize: 12,
            updatedAt: Date()
        )
        store.configureForTesting(vaultId: "v", lockedEncryptedNotes: [locked])

        store.searchText = "隐藏正文关键词"
        XCTAssertTrue(store.filteredNotes.isEmpty)

        store.searchText = "锁定项目标题"
        XCTAssertEqual(store.filteredNotes, [.locked(locked)])
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
    func testClearEmptyReadableNotesMovesOnlyReadableEmptyNotesToTrash() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_clear_empty_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        try await storage.initializeVault()

        let key = SymmetricKey(size: .bits256)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "clear-empty-vault", key: key)

        let emptyPlain = try await store.createNote(body: " \n\t ", isEncrypted: false)
        let nonEmptyPlain = try await store.createNote(body: "正文", isEncrypted: false)
        let emptyEncrypted = try await store.createNote(body: "\n\n", isEncrypted: true)

        try await store.unloadKey()
        let lockedEncrypted = try XCTUnwrap(store.lockedEncryptedNotes.first(where: { $0.id == emptyEncrypted.id }))

        let movedCount = try await store.clearEmptyReadableNotes()

        XCTAssertEqual(movedCount, 1)
        XCTAssertFalse(store.plainNotes.contains { $0.id == emptyPlain.id })
        XCTAssertTrue(store.plainNotes.contains { $0.id == nonEmptyPlain.id })
        XCTAssertTrue(store.lockedEncryptedNotes.contains { $0.id == lockedEncrypted.id })

        let index = try XCTUnwrap(storage.loadIndex())
        XCTAssertEqual(index.entry(for: emptyPlain.id)?.location, .trash)
        XCTAssertEqual(index.entry(for: nonEmptyPlain.id)?.location, .notes)
        XCTAssertEqual(index.entry(for: emptyEncrypted.id)?.location, .notes)

        let trashURL = tmpDir.appendingPathComponent("trash").appendingPathComponent("\(emptyPlain.id).md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashURL.path))

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

    #if os(macOS)
    @MainActor
    func testMacCreateEncryptedNoteRequiresKeyFileReference() async throws {
        SettingsStore.shared.resetForTesting()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_mac_requires_key_file_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "mac-requires-key-file")

        do {
            _ = try await store.createNote(body: "需要密钥", isEncrypted: true)
            XCTFail("没有密钥引用时不应创建加密笔记")
        } catch {
            XCTAssertNotNil(error)
        }

        try? FileManager.default.removeItem(at: tmpDir)
        SettingsStore.shared.resetForTesting()
    }

    @MainActor
    func testMacCreateKeyFileStoresIdentityMetadata() async throws {
        SettingsStore.shared.resetForTesting()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_mac_key_identity_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "mac-key-identity")

        let keyURL = tmpDir.appendingPathComponent("vault.snkey")
        try await store.createKeyFile(at: keyURL)

        let reference = try XCTUnwrap(SettingsStore.shared.vaultKeyFileReference)
        XCTAssertEqual(reference.displayPath, keyURL.path)
        XCTAssertFalse(try XCTUnwrap(reference.keyId).isEmpty)
        XCTAssertEqual(try XCTUnwrap(reference.keyFingerprint).count, 64)
        XCTAssertEqual(keyURL.pathExtension, "snkey")

        try? FileManager.default.removeItem(at: tmpDir)
        SettingsStore.shared.resetForTesting()
    }

    @MainActor
    func testMacImportRejectsLegacyKeyExtension() async throws {
        SettingsStore.shared.resetForTesting()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_mac_legacy_key_extension_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "mac-legacy-key-extension")

        let vaultKey = VaultKeyManager.shared.generateVaultKey(key: SymmetricKey(size: .bits256))
        let legacyExtension = "bk" + "wkey"
        let legacyURL = tmpDir.appendingPathComponent("legacy.\(legacyExtension)")
        try JSONEncoder.default.encode(vaultKey).write(to: legacyURL, options: .atomic)

        do {
            _ = try await store.importKeyFile(from: legacyURL)
            XCTFail("旧密钥扩展名不应被加载")
        } catch {
            XCTAssertEqual(error as? VaultKeyFileError, .unsupportedFileExtension)
        }
        XCTAssertNil(SettingsStore.shared.vaultKeyFileReference)

        try? FileManager.default.removeItem(at: tmpDir)
        SettingsStore.shared.resetForTesting()
    }

    @MainActor
    func testMacReplacedKeyAtSamePathInvalidatesReference() async throws {
        SettingsStore.shared.resetForTesting()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_mac_replaced_key_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "mac-replaced-key")

        let keyURL = tmpDir.appendingPathComponent("vault.snkey")
        try await store.createKeyFile(at: keyURL)
        let originalReference = try XCTUnwrap(SettingsStore.shared.vaultKeyFileReference)

        let replacementKey = VaultKeyManager.shared.generateVaultKey(key: SymmetricKey(size: .bits256))
        try JSONEncoder.default.encode(replacementKey).write(to: keyURL, options: .atomic)

        XCTAssertEqual(store.macKeyStatus, .invalid(.keyReplaced))
        XCTAssertFalse(store.isKeyLoaded)
        XCTAssertEqual(SettingsStore.shared.vaultKeyFileReference?.keyFingerprint, originalReference.keyFingerprint)

        try? FileManager.default.removeItem(at: tmpDir)
        SettingsStore.shared.resetForTesting()
    }

    @MainActor
    func testMacOpenEncryptedNoteWithWrongKeyFails() async throws {
        SettingsStore.shared.resetForTesting()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_mac_wrong_key_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "mac-wrong-key")

        let correctKeyURL = tmpDir.appendingPathComponent("correct.snkey")
        try await store.createKeyFile(at: correctKeyURL)
        let note = try await store.createNote(body: "加密内容", isEncrypted: true)

        let wrongKey = VaultKeyManager.shared.generateVaultKey(key: SymmetricKey(size: .bits256))
        let wrongKeyURL = tmpDir.appendingPathComponent("wrong.snkey")
        try JSONEncoder.default.encode(wrongKey).write(to: wrongKeyURL, options: .atomic)
        try SettingsStore.shared.saveVaultKeyFileReference(for: wrongKeyURL)
        await store.refreshFromStorage()

        let info = try XCTUnwrap(store.lockedEncryptedNotes.first(where: { $0.id == note.id }))
        do {
            _ = try await store.openEncryptedNote(info)
            XCTFail("错误密钥不应解密成功")
        } catch {
            XCTAssertEqual(error.localizedDescription, VaultKeyFileError.keyMismatch.localizedDescription)
        }

        try? FileManager.default.removeItem(at: tmpDir)
        SettingsStore.shared.resetForTesting()
    }

    @MainActor
    func testMacImportMismatchedKeyDoesNotOverwriteSavedReference() async throws {
        SettingsStore.shared.resetForTesting()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_mac_import_mismatch_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "mac-import-mismatch")

        let correctKeyURL = tmpDir.appendingPathComponent("correct.snkey")
        try await store.createKeyFile(at: correctKeyURL)
        _ = try await store.createNote(body: "现有加密内容", isEncrypted: true)
        let originalReference = try XCTUnwrap(SettingsStore.shared.vaultKeyFileReference)

        let wrongKey = VaultKeyManager.shared.generateVaultKey(key: SymmetricKey(size: .bits256))
        let wrongKeyURL = tmpDir.appendingPathComponent("wrong.snkey")
        try JSONEncoder.default.encode(wrongKey).write(to: wrongKeyURL, options: .atomic)

        do {
            _ = try await store.importKeyFile(from: wrongKeyURL)
            XCTFail("不匹配密钥不应覆盖已有密钥引用")
        } catch {
            XCTAssertEqual(error as? VaultKeyFileError, .keyMismatch)
        }

        let currentReference = try XCTUnwrap(SettingsStore.shared.vaultKeyFileReference)
        XCTAssertEqual(currentReference.displayPath, originalReference.displayPath)
        XCTAssertEqual(currentReference.keyFingerprint, originalReference.keyFingerprint)

        try? FileManager.default.removeItem(at: tmpDir)
        SettingsStore.shared.resetForTesting()
    }

    @MainActor
    func testMacUnloadKeyWithEncryptedNotesRequiresCleanupPath() async throws {
        SettingsStore.shared.resetForTesting()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_mac_unload_requires_cleanup_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "mac-unload-requires-cleanup")

        let keyURL = tmpDir.appendingPathComponent("vault.snkey")
        try await store.createKeyFile(at: keyURL)
        let plain = try await store.createNote(body: "保留明文", isEncrypted: false)
        _ = try await store.createNote(body: "删除密文", isEncrypted: true)

        do {
            try await store.unloadKey()
            XCTFail("有加密笔记时不应直接移除密钥引用")
        } catch {
            XCTAssertEqual(error as? VaultKeyFileError, .encryptedNotesExist)
        }
        XCTAssertNotNil(SettingsStore.shared.vaultKeyFileReference)

        let removedCount = try await store.permanentlyDeleteAllEncryptedNotes()
        XCTAssertEqual(removedCount, 1)
        XCTAssertNil(SettingsStore.shared.vaultKeyFileReference)
        XCTAssertTrue(store.plainNotes.contains { $0.id == plain.id })
        XCTAssertEqual(store.encryptedEntryCount, 0)

        try? FileManager.default.removeItem(at: tmpDir)
        SettingsStore.shared.resetForTesting()
    }

    @MainActor
    func testMacDecryptAllEncryptedNotesAndRemoveKeyKeepsPlainNotes() async throws {
        SettingsStore.shared.resetForTesting()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_mac_decrypt_all_remove_key_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "mac-decrypt-all-remove-key")

        let keyURL = tmpDir.appendingPathComponent("vault.snkey")
        try await store.createKeyFile(at: keyURL)
        let plain = try await store.createNote(body: "原明文", isEncrypted: false)
        let encrypted = try await store.createNote(body: "转明文", isEncrypted: true)

        let decryptedCount = try await store.decryptAllEncryptedNotesAndRemoveKey()

        XCTAssertEqual(decryptedCount, 1)
        XCTAssertNil(SettingsStore.shared.vaultKeyFileReference)
        XCTAssertTrue(store.plainNotes.contains { $0.id == plain.id })
        XCTAssertTrue(store.plainNotes.contains { $0.id == encrypted.id })
        XCTAssertEqual(store.encryptedEntryCount, 0)

        try? FileManager.default.removeItem(at: tmpDir)
        SettingsStore.shared.resetForTesting()
    }

    @MainActor
    func testMacPermanentDecryptConvertsEncryptedNoteToPlain() async throws {
        SettingsStore.shared.resetForTesting()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_mac_permanent_decrypt_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "mac-permanent-decrypt")

        let keyURL = tmpDir.appendingPathComponent("vault.snkey")
        try await store.createKeyFile(at: keyURL)
        let encrypted = try await store.createNote(body: "转为明文", isEncrypted: true)

        let plain = try await store.decryptNotePermanently(encrypted)

        XCTAssertFalse(plain.isEncrypted)
        XCTAssertEqual(plain.body, "转为明文")
        XCTAssertEqual(store.plainNotes.first?.id, encrypted.id)
        XCTAssertTrue(store.decryptedNotes.isEmpty)
        let entry = try XCTUnwrap(storage.loadIndex()?.entry(for: encrypted.id))
        XCTAssertEqual(entry.mode, .plain)
        let mdURL = try savedNoteURL(in: tmpDir, noteId: encrypted.id)
        let mdContent = String(data: try Data(contentsOf: mdURL), encoding: .utf8) ?? ""
        XCTAssertTrue(mdContent.contains("转为明文"))
        XCTAssertFalse(mdContent.contains("snenc:v1:"))

        try? FileManager.default.removeItem(at: tmpDir)
        SettingsStore.shared.resetForTesting()
    }
    #endif
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
            baseURL.appendingPathComponent("conflicts"),
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
            _containerURL.appendingPathComponent("conflicts"),
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
