import XCTest
import CryptoKit
@testable import SealNote

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
    func testUntitledAutosaveCanPreserveTemporaryFileNameUntilExplicitRename() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_deferred_title_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "test-vault-deferred-title")

        let note = try await store.createNote(body: "", isEncrypted: false)
        let initialURL = try savedNoteURL(in: tmpDir, noteId: note.id)
        XCTAssertEqual(initialURL.lastPathComponent, "临时笔记.md")

        try await store.updateNote(note, body: "#", renameIfUntitled: false)
        let autosavedURL = try savedNoteURL(in: tmpDir, noteId: note.id)
        XCTAssertEqual(autosavedURL.lastPathComponent, "临时笔记.md")

        guard let savedNote = store.readableNotes.first(where: { $0.id == note.id }) else {
            return XCTFail("Expected updated note")
        }
        try await store.renameNote(savedNote, title: "# 标题", limitsLength: false)

        let renamedURL = try savedNoteURL(in: tmpDir, noteId: note.id)
        XCTAssertEqual(renamedURL.lastPathComponent, "标题.md")

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testRenameNoteChangesFileNameButLeavesMarkdownContentUntouched() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_title_rename_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "test-vault-title-rename")

        let originalBody = "第一行正文\n\n更多内容"
        let note = try await store.createNote(body: originalBody, isEncrypted: false)
        let oldURL = try savedNoteURL(in: tmpDir, noteId: note.id)
        let oldFile = try storage.loadMarkdownFile(at: oldURL)

        try await store.renameNote(note, title: "会议/记录?")

        let newURL = try savedNoteURL(in: tmpDir, noteId: note.id)
        XCTAssertNotEqual(oldURL.lastPathComponent, newURL.lastPathComponent)
        XCTAssertEqual(newURL.lastPathComponent, "会议-记录.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))

        let newFile = try storage.loadMarkdownFile(at: newURL)
        XCTAssertEqual(newFile.body, oldFile.body)
        XCTAssertEqual(newFile.body, originalBody)
        XCTAssertEqual(store.displayTitle(for: note), "会议-记录")

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
    func testRefreshFromStorageIndexesUnindexedPlainMarkdownFile() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_unindexed_plain_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        try await storage.initializeVault()

        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "test-vault-unindexed-plain")

        let noteId = UUID().uuidString
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let mdFile = MarkdownNoteFile(
            noteId: noteId,
            createdAt: createdAt,
            updatedAt: createdAt.addingTimeInterval(60),
            title: "远端笔记",
            body: "来自另一台 Mac 的内容"
        )
        let remoteURL = tmpDir.appendingPathComponent("远端笔记.md")
        try storage.saveMarkdownFile(mdFile, at: remoteURL)

        XCTAssertNil(try storage.loadIndex()?.entry(for: noteId))

        await store.refreshFromStorage()

        XCTAssertTrue(store.plainNotes.contains { $0.id == noteId })
        let entry = try XCTUnwrap(storage.loadIndex()?.entry(for: noteId))
        XCTAssertEqual(entry.fileName, "远端笔记.md")
        XCTAssertEqual(entry.mode, .plain)
        XCTAssertEqual(entry.location, .notes)

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testRefreshFromStorageRepairsDuplicateIndexEntriesForSameFile() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_duplicate_index_file_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        try await storage.initializeVault()

        let actualNoteId = UUID().uuidString
        let staleNoteId = UUID().uuidString
        let fileName = "重复索引笔记.md"
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        try storage.saveMarkdownFile(
            MarkdownNoteFile(
                noteId: actualNoteId,
                createdAt: timestamp,
                updatedAt: timestamp,
                title: "重复索引笔记",
                body: "只应加载一次"
            ),
            at: tmpDir.appendingPathComponent(fileName)
        )
        try storage.saveIndex(NoteIndex(entries: [
            NoteIndexEntry(noteId: staleNoteId, fileName: fileName, mode: .plain, location: .notes),
            NoteIndexEntry(noteId: actualNoteId, fileName: fileName, mode: .plain, location: .notes)
        ]))

        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "test-vault-duplicate-index-file")
        await store.refreshFromStorage()

        XCTAssertEqual(store.plainNotes.filter { $0.id == actualNoteId }.count, 1)
        let repairedEntries = try XCTUnwrap(storage.loadIndex()).entries.filter { $0.fileName == fileName }
        XCTAssertEqual(repairedEntries.count, 1)
        XCTAssertEqual(repairedEntries.first?.noteId, actualNoteId)

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testRefreshFromStorageIndexesUnindexedEncryptedMarkdownFileAsLocked() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_unindexed_encrypted_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        try await storage.initializeVault()

        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "test-vault-unindexed-encrypted")

        let noteId = UUID().uuidString
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let encryptedBody = try CryptoService.shared.encryptMarkdownBody(
            "另一台 Mac 创建的加密内容",
            using: SymmetricKey(size: .bits256)
        )
        let mdFile = MarkdownNoteFile(
            noteId: noteId,
            createdAt: createdAt,
            updatedAt: createdAt.addingTimeInterval(120),
            title: "远端加密",
            body: encryptedBody
        )
        let remoteURL = tmpDir.appendingPathComponent("远端加密.md")
        try storage.saveMarkdownFile(mdFile, at: remoteURL)

        await store.refreshFromStorage()

        XCTAssertTrue(store.lockedEncryptedNotes.contains { $0.id == noteId })
        let entry = try XCTUnwrap(storage.loadIndex()?.entry(for: noteId))
        XCTAssertEqual(entry.fileName, "远端加密.md")
        XCTAssertEqual(entry.mode, .encrypted)
        XCTAssertEqual(entry.location, .notes)

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testPendingICloudDownloadsDoNotSurfaceAsLastErrorOrDoubleCount() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_pending_download_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        try await storage.initializeVault()
        SyncStatusStore.shared.setSaved()

        let noteId = UUID().uuidString
        let fileName = "待下载笔记.md"
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let mdFile = MarkdownNoteFile(
            noteId: noteId,
            createdAt: createdAt,
            updatedAt: createdAt.addingTimeInterval(60),
            title: "待下载笔记",
            body: "下载完成后显示"
        )
        try storage.saveMarkdownFile(mdFile, at: tmpDir.appendingPathComponent(fileName))
        try storage.saveIndex(NoteIndex(entries: [
            NoteIndexEntry(noteId: noteId, fileName: fileName, mode: .plain, location: .notes)
        ]))
        storage.pendingMarkdownFileNames = [fileName]

        let store = VaultStore(storage: storage)
        await store.initialize()

        XCTAssertEqual(store.state, .ready)
        XCTAssertNil(store.lastError)
        XCTAssertEqual(store.plainNotes.count, 0)
        XCTAssertEqual(SyncStatusStore.shared.status, .pendingDownloads(count: 1))

        storage.pendingMarkdownFileNames = []
        await store.refreshFromStorage()

        XCTAssertEqual(store.state, .ready)
        XCTAssertNil(store.lastError)
        XCTAssertTrue(store.plainNotes.contains { $0.id == noteId })
        XCTAssertEqual(SyncStatusStore.shared.status, .saved)

        SyncStatusStore.shared.setSaved()
        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testRefreshFromStorageStillReportsRealErrorsAsFailedSync() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_refresh_real_error_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        try await storage.initializeVault()
        SyncStatusStore.shared.setSaved()

        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "test-vault-refresh-real-error")
        storage.loadIndexError = StorageError.invalidData

        await store.refreshFromStorage()

        XCTAssertEqual(store.state, .error(message: StorageError.invalidData.localizedDescription))
        XCTAssertEqual(SyncStatusStore.shared.status, .failed(message: StorageError.invalidData.localizedDescription))

        SyncStatusStore.shared.setSaved()
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
    func testTagParserExcludesSixAndEightDigitHexColorsWhenEnabled() {
        let tags = TagParser.tags(
            in: "颜色 #0B996E、#10151F0A，标签 #设计",
            excludingHexColors: true
        )
        XCTAssertEqual(tags, ["#设计"])
    }

    @MainActor
    func testTagParserKeepsHexColorsWhenExclusionIsDisabled() {
        let tags = TagParser.tags(
            in: "颜色 #0B996E、#10151F0A",
            excludingHexColors: false
        )
        XCTAssertEqual(tags, ["#0B996E、", "#10151F0A"])
    }

    @MainActor
    func testTagsExcludeEncryptedNotesEvenWhenDecrypted() {
        let store = VaultStore(storage: try? TemporaryStorage(baseURL: FileManager.default.temporaryDirectory))
        let plain = Note(id: "p1", body: "明文 #标签A", isEncrypted: false)
        let encrypted = Note(id: "e1", body: "加密 #标签B", isEncrypted: true)
        store.configureForTesting(vaultId: "v", decryptedNotes: [encrypted], plainNotes: [plain])

        let tags = store.allTags
        XCTAssertTrue(tags.contains { $0.tag == "#标签A" })
        XCTAssertFalse(tags.contains { $0.tag == "#标签B" })
    }

    @MainActor
    func testTagFilterDoesNotMatchDecryptedEncryptedNoteBody() {
        let store = VaultStore(storage: try? TemporaryStorage(baseURL: FileManager.default.temporaryDirectory))
        let plain = Note(id: "p1", body: "明文 #公开", isEncrypted: false)
        let encrypted = Note(id: "e1", body: "加密 #私密", isEncrypted: true)
        store.configureForTesting(vaultId: "v", decryptedNotes: [encrypted], plainNotes: [plain])

        store.selectedTag = "#私密"

        XCTAssertTrue(store.filteredNotes.isEmpty)
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
            createdAt: Date(timeIntervalSince1970: 150),
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
            createdAt: Date(),
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
    func testPlainNotesSearchStableTitleAndBody() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_plain_title_search_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "test-plain-title-search")

        let note = try await store.createNote(body: "假装是", isEncrypted: false)
        try await store.renameNote(note, title: "标题内容")

        store.searchText = "标题"
        XCTAssertEqual(store.filteredNotes.map(\.id), [note.id])

        store.searchText = "假装"
        XCTAssertEqual(store.filteredNotes.map(\.id), [note.id])

        try? FileManager.default.removeItem(at: tmpDir)
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
            createdAt: Date(),
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
        try? KeychainStore.shared.deleteKey(forVaultId: "clear-empty-vault")
        store.configureForTesting(vaultId: "clear-empty-vault", key: key)

        let emptyPlain = try await store.createNote(body: " \n\t ", isEncrypted: false)
        let nonEmptyPlain = try await store.createNote(body: "正文", isEncrypted: false)
        let emptyEncrypted = try await store.createNote(body: "\n\n", isEncrypted: true)

        await store.refreshFromStorage()
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
    func testUnloadKeyWithEncryptedNotesRequiresCleanupPath() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_unload_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        try await storage.initializeVault()

        let key = SymmetricKey(size: .bits256)
        let store = VaultStore(storage: storage)
        let vaultId = "unload-vault"
        try? KeychainStore.shared.deleteKey(forVaultId: vaultId)
        store.configureForTesting(vaultId: vaultId, key: key)

        try await store.createNote(body: "加密笔记", isEncrypted: true)
        XCTAssertEqual(store.decryptedNotes.count, 1)

        do {
            try await store.unloadKey()
            XCTFail("有加密笔记时不应直接移除密钥引用")
        } catch {
            XCTAssertEqual(error as? VaultKeyFileError, .encryptedNotesExist)
        }

        XCTAssertEqual(store.decryptedNotes.count, 1)

        let removedCount = try await store.permanentlyDeleteAllEncryptedNotes()
        XCTAssertEqual(removedCount, 1)
        XCTAssertEqual(store.encryptedEntryCount, 0)
        XCTAssertTrue(store.decryptedNotes.isEmpty)

        try? FileManager.default.removeItem(at: tmpDir)
        try? KeychainStore.shared.deleteKey(forVaultId: vaultId)
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
    func testMacImportRejectsUnsupportedKeyExtension() async throws {
        SettingsStore.shared.resetForTesting()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_mac_unsupported_key_extension_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "mac-unsupported-key-extension")

        let vaultKey = VaultKeyManager.shared.generateVaultKey(key: SymmetricKey(size: .bits256))
        let unsupportedURL = tmpDir.appendingPathComponent("unsupported.key")
        try JSONEncoder.default.encode(vaultKey).write(to: unsupportedURL, options: .atomic)

        do {
            _ = try await store.importKeyFile(from: unsupportedURL)
            XCTFail("非 .snkey 扩展名不应被加载")
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

    // MARK: - Phase 2: stable vault identity (P0-1)

    #if os(iOS)
    @MainActor
    func testVaultIdSurvivesRelaunch() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("vaultid_relaunch_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "relaunch_\(UUID().uuidString)")!)
        settings.hasSeededDefaultNotes = true
        let keyStore = InMemoryKeyStore()

        let storeA = VaultStore(storage: storage, settings: settings, keyStore: keyStore)
        await storeA.initialize()
        try await storeA.createKey()
        _ = try await storeA.createNote(body: "机密内容", isEncrypted: true)
        XCTAssertEqual(storeA.decryptedNotes.count, 1)

        // A brand-new store over the SAME storage/settings/keyStore = an app relaunch.
        let storeB = VaultStore(storage: storage, settings: settings, keyStore: keyStore)
        await storeB.initialize()
        XCTAssertEqual(storeB.decryptedNotes.count, 1)
        XCTAssertEqual(storeB.decryptedNotes.first?.body, "机密内容")

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testLegacyKeychainAdoption() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("legacy_adopt_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "legacy_\(UUID().uuidString)")!)
        settings.hasSeededDefaultNotes = true

        let keyManager = VaultKeyManager.shared
        let key = keyManager.generateKey()
        let vaultKey = keyManager.generateVaultKey(key: key)
        let legacyId = "legacy-\(UUID().uuidString)"
        let keyStore = InMemoryKeyStore()
        try keyStore.saveKey(vaultKey.keyMaterial, forVaultId: legacyId,
                             keyId: vaultKey.keyId, keyFingerprint: try keyManager.keyFingerprint(vaultKey))

        // One encrypted note on disk (encrypted with the legacy key), no vault.json / no cache.
        let noteId = UUID().uuidString
        let cipher = try CryptoService.shared.encryptMarkdownBody("旧密文", using: key)
        let mdFile = MarkdownNoteFile(noteId: noteId, createdAt: Date(), updatedAt: Date(), title: "旧笔记", body: cipher)
        try storage.saveMarkdownFile(mdFile, at: tmpDir.appendingPathComponent("旧笔记.md"))
        try storage.saveIndex(NoteIndex(entries: [
            NoteIndexEntry(noteId: noteId, fileName: "旧笔记.md", mode: .encrypted, location: .notes)
        ]))

        let store = VaultStore(storage: storage, settings: settings, keyStore: keyStore)
        await store.initialize()

        XCTAssertEqual(store.decryptedNotes.count, 1)
        XCTAssertEqual(store.decryptedNotes.first?.body, "旧密文")
        let descriptorData = try Data(contentsOf: tmpDir.appendingPathComponent(".meta/vault.json"))
        let descriptor = try JSONDecoder.default.decode(VaultDescriptor.self, from: descriptorData)
        XCTAssertEqual(descriptor.vaultId, legacyId)

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testVaultDescriptorDisagreementPrefersStorage() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("descriptor_disagree_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let defaults = UserDefaults(suiteName: "disagree_\(UUID().uuidString)")!

        let idA = "vault-A-\(UUID().uuidString)"
        let idB = "vault-B-\(UUID().uuidString)"
        // vault.json (authoritative) says A.
        let metaDir = tmpDir.appendingPathComponent(".meta")
        try FileManager.default.createDirectory(at: metaDir, withIntermediateDirectories: true)
        let descriptorA = VaultDescriptor(vaultId: idA, createdAt: Date(), schemaVersion: 1)
        try JSONEncoder.default.encode(descriptorA).write(to: metaDir.appendingPathComponent("vault.json"))
        // The cache says B and the key lives under B.
        defaults.set(idB, forKey: VaultIdentityStore.vaultIdDefaultsKey)
        let keyManager = VaultKeyManager.shared
        let vaultKey = keyManager.generateVaultKey(key: keyManager.generateKey())
        let keyStore = InMemoryKeyStore()
        try keyStore.saveKey(vaultKey.keyMaterial, forVaultId: idB,
                             keyId: vaultKey.keyId, keyFingerprint: try keyManager.keyFingerprint(vaultKey))

        let settings = SettingsStore(defaults: defaults)
        settings.hasSeededDefaultNotes = true
        let store = VaultStore(storage: storage, settings: settings, keyStore: keyStore)
        await store.initialize()

        XCTAssertTrue(keyStore.hasKey(forVaultId: idA))
        XCTAssertFalse(keyStore.hasKey(forVaultId: idB))
        XCTAssertEqual(defaults.string(forKey: VaultIdentityStore.vaultIdDefaultsKey), idA)

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testNeedsKeyExportPersists() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("needexport_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let defaults = UserDefaults(suiteName: "needexport_\(UUID().uuidString)")!
        let keyStore = InMemoryKeyStore()

        let settingsA = SettingsStore(defaults: defaults)
        settingsA.hasSeededDefaultNotes = true
        let storeA = VaultStore(storage: storage, settings: settingsA, keyStore: keyStore)
        await storeA.initialize()
        try await storeA.createKey()
        XCTAssertTrue(storeA.needsKeyExport)

        // Fresh settings instance over the same suite proves the flag round-trips through UserDefaults.
        let storeB = VaultStore(storage: storage, settings: SettingsStore(defaults: defaults), keyStore: keyStore)
        await storeB.initialize()
        XCTAssertTrue(storeB.needsKeyExport)

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testNonValidatingCandidateMintsFreshId() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("nonvalidating_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "nonvalidating_\(UUID().uuidString)")!)
        settings.hasSeededDefaultNotes = true

        let keyManager = VaultKeyManager.shared
        let realKey = keyManager.generateKey()
        // A keychain candidate whose key does NOT decrypt the note.
        let wrongVaultKey = keyManager.generateVaultKey(key: keyManager.generateKey())
        let candidateId = "candidate-\(UUID().uuidString)"
        let keyStore = InMemoryKeyStore()
        try keyStore.saveKey(wrongVaultKey.keyMaterial, forVaultId: candidateId,
                             keyId: wrongVaultKey.keyId, keyFingerprint: try keyManager.keyFingerprint(wrongVaultKey))

        let noteId = UUID().uuidString
        let cipher = try CryptoService.shared.encryptMarkdownBody("秘密", using: realKey)
        let mdFile = MarkdownNoteFile(noteId: noteId, createdAt: Date(), updatedAt: Date(), title: "x", body: cipher)
        try storage.saveMarkdownFile(mdFile, at: tmpDir.appendingPathComponent("x.md"))
        try storage.saveIndex(NoteIndex(entries: [
            NoteIndexEntry(noteId: noteId, fileName: "x.md", mode: .encrypted, location: .notes)
        ]))

        let store = VaultStore(storage: storage, settings: settings, keyStore: keyStore)
        await store.initialize()

        // Non-validating candidate is NOT adopted; a fresh id is minted instead.
        let descriptorData = try Data(contentsOf: tmpDir.appendingPathComponent(".meta/vault.json"))
        let descriptor = try JSONDecoder.default.decode(VaultDescriptor.self, from: descriptorData)
        XCTAssertNotEqual(descriptor.vaultId, candidateId)
        // The candidate key is left inert (never deleted).
        XCTAssertTrue(keyStore.hasKey(forVaultId: candidateId))
        // The note stays locked.
        XCTAssertEqual(store.decryptedNotes.count, 0)
        XCTAssertTrue(store.lockedEncryptedNotes.contains { $0.id == noteId })

        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - Phase 3: cloud-placeholder safety (P0-2)

    @MainActor
    func testClearEmptyReadableNotesSkipsCloudOnly() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("clear_cloudonly_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage)

        // An undownloaded iCloud placeholder: empty body, tracked as cloud-only.
        // Without the guard, clearEmptyReadableNotes would try to delete it (empty body)
        // and throw fileNotFound; the guard must skip it entirely.
        let cloudOnly = Note(id: "cloud-1", body: "", createdAt: Date(), updatedAt: Date(), isEncrypted: false)
        store.configureForTesting(
            vaultId: "clear-cloudonly-vault",
            plainNotes: [cloudOnly],
            cloudOnlyPlainNoteIDs: ["cloud-1"]
        )

        let cleared = try await store.clearEmptyReadableNotes()

        XCTAssertEqual(cleared, 0)
        XCTAssertTrue(store.plainNotes.contains { $0.id == "cloud-1" })
        XCTAssertTrue(store.isCloudOnly(cloudOnly))

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testExportSkipsCloudOnlyAndCountsThem() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("export_cloudonly_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage)

        let real = Note(id: "real-1", body: "真实内容", createdAt: Date(), updatedAt: Date(), isEncrypted: false)
        let cloudOnly = Note(id: "cloud-1", body: "", createdAt: Date(), updatedAt: Date(), isEncrypted: false)
        store.configureForTesting(
            vaultId: "export-cloudonly-vault",
            plainNotes: [real, cloudOnly],
            cloudOnlyPlainNoteIDs: ["cloud-1"]
        )

        let result = try store.exportReadableNotesAsZip()

        XCTAssertEqual(result.exportedCount, 1)   // only the downloaded note
        XCTAssertEqual(result.skippedCount, 1)    // the cloud-only placeholder counted, not exported

        try? FileManager.default.removeItem(at: result.url)
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - Phase 4: storage-root pinning (P0-3)

    @MainActor
    func testResolveStorageTable() {
        var r = VaultStore.resolveStorage(pinned: nil, iCloudAvailable: true)
        XCTAssertTrue(r.storage is ICloudVaultStorage); XCTAssertEqual(r.pin, "icloud"); XCTAssertFalse(r.mismatch)

        r = VaultStore.resolveStorage(pinned: nil, iCloudAvailable: false)
        XCTAssertTrue(r.storage is LocalFallbackStorage); XCTAssertEqual(r.pin, "local"); XCTAssertFalse(r.mismatch)

        r = VaultStore.resolveStorage(pinned: "icloud", iCloudAvailable: true)
        XCTAssertTrue(r.storage is ICloudVaultStorage); XCTAssertEqual(r.pin, "icloud"); XCTAssertFalse(r.mismatch)

        // Pinned to iCloud but unavailable: temporary local fallback, pin unchanged, mismatch flagged.
        r = VaultStore.resolveStorage(pinned: "icloud", iCloudAvailable: false)
        XCTAssertTrue(r.storage is LocalFallbackStorage); XCTAssertEqual(r.pin, "icloud"); XCTAssertTrue(r.mismatch)

        // Pinned to local: iCloud reappearing does NOT auto-switch.
        r = VaultStore.resolveStorage(pinned: "local", iCloudAvailable: true)
        XCTAssertTrue(r.storage is LocalFallbackStorage); XCTAssertEqual(r.pin, "local"); XCTAssertFalse(r.mismatch)

        r = VaultStore.resolveStorage(pinned: "local", iCloudAvailable: false)
        XCTAssertTrue(r.storage is LocalFallbackStorage); XCTAssertEqual(r.pin, "local"); XCTAssertFalse(r.mismatch)
    }

    @MainActor
    func testHasVaultDataDetectsNotesTrashAndIndex() throws {
        let fm = FileManager.default
        let empty = fm.temporaryDirectory.appendingPathComponent("hvd_empty_\(UUID().uuidString)")
        try fm.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertFalse(VaultStore.hasVaultData(at: empty))

        let withMd = fm.temporaryDirectory.appendingPathComponent("hvd_md_\(UUID().uuidString)")
        try fm.createDirectory(at: withMd, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: withMd.appendingPathComponent("note.md"))
        XCTAssertTrue(VaultStore.hasVaultData(at: withMd))

        let withIndex = fm.temporaryDirectory.appendingPathComponent("hvd_idx_\(UUID().uuidString)")
        try fm.createDirectory(at: withIndex, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: withIndex.appendingPathComponent("notes.json"))
        XCTAssertTrue(VaultStore.hasVaultData(at: withIndex))

        [empty, withMd, withIndex].forEach { try? fm.removeItem(at: $0) }
    }

    @MainActor
    func testMergeVaultDataMergesUniqueAndRenamesCollisions() throws {
        let fm = FileManager.default
        let srcDir = fm.temporaryDirectory.appendingPathComponent("merge_src_\(UUID().uuidString)")
        let dstDir = fm.temporaryDirectory.appendingPathComponent("merge_dst_\(UUID().uuidString)")
        let source = try TemporaryStorage(baseURL: srcDir)
        let dest = try TemporaryStorage(baseURL: dstDir)

        // Source: a unique note + one that collides with an existing dest note.
        try source.saveMarkdownFile(
            MarkdownNoteFile(noteId: "u1", createdAt: Date(), updatedAt: Date(), title: "唯一", body: "unique body"),
            at: srcDir.appendingPathComponent("u1.md"))
        try source.saveMarkdownFile(
            MarkdownNoteFile(noteId: "c1", createdAt: Date(), updatedAt: Date(), title: "冲突", body: "local version"),
            at: srcDir.appendingPathComponent("c1.md"))
        try source.saveIndex(NoteIndex(entries: [
            NoteIndexEntry(noteId: "u1", fileName: "u1.md", mode: .plain, location: .notes),
            NoteIndexEntry(noteId: "c1", fileName: "c1.md", mode: .plain, location: .notes)
        ]))
        try dest.saveMarkdownFile(
            MarkdownNoteFile(noteId: "c1", createdAt: Date(), updatedAt: Date(), title: "云端", body: "cloud version"),
            at: dstDir.appendingPathComponent("c1.md"))
        try dest.saveIndex(NoteIndex(entries: [
            NoteIndexEntry(noteId: "c1", fileName: "c1.md", mode: .plain, location: .notes)
        ]))

        let result = try VaultStore.mergeVaultData(from: source, into: dest)

        XCTAssertEqual(result.merged, 1)
        XCTAssertEqual(result.conflicted, 1)

        let destIndex = try XCTUnwrap(dest.loadIndex())
        XCTAssertEqual(destIndex.entries.count, 3)          // original c1 + merged u1 + renamed copy
        XCTAssertNotNil(destIndex.entry(for: "u1"))
        XCTAssertNotNil(destIndex.entry(for: "c1"))         // cloud original preserved
        let copyEntry = try XCTUnwrap(destIndex.entries.first { $0.noteId != "u1" && $0.noteId != "c1" })
        let copyFile = try dest.loadMarkdownFile(at: dstDir.appendingPathComponent(copyEntry.fileName))
        XCTAssertTrue((copyFile.title ?? "").contains("本机副本"))
        XCTAssertEqual(copyFile.body, "local version")

        // Local originals removed only after verified read-back.
        let sourceIndex = try XCTUnwrap(source.loadIndex())
        XCTAssertTrue(sourceIndex.entries.isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: srcDir.appendingPathComponent("u1.md").path))
        XCTAssertFalse(fm.fileExists(atPath: srcDir.appendingPathComponent("c1.md").path))

        [srcDir, dstDir].forEach { try? fm.removeItem(at: $0) }
    }

    // MARK: - Phase 5: serialized writes + visible conflicts (P0/P1-2)

    @MainActor
    func testConflictProducesVisibleConflictNote() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("conflict_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage, settings: SettingsStore(defaults: UserDefaults(suiteName: "conflict_\(UUID().uuidString)")!))
        store.configureForTesting(vaultId: "conflict-vault")

        let note = try await store.createNote(body: "MEM_ORIGINAL", isEncrypted: false)

        // Simulate an external device writing a newer, different version to the same file.
        let entry0 = try XCTUnwrap(storage.loadIndex()?.entry(for: note.id))
        let bumped = MarkdownNoteFile(
            noteId: note.id,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt.addingTimeInterval(10),
            title: "远端标题",
            body: "DISK_NEWER"
        )
        try storage.saveMarkdownFile(bumped, at: tmpDir.appendingPathComponent(entry0.fileName))

        // Save our (stale) memory version — this is the conflict.
        try await store.updateNote(note, body: "MEM_UPDATED")

        // Both versions survive: original updated in place, disk version kept as a copy.
        XCTAssertEqual(store.plainNotes.count, 2)
        XCTAssertTrue(store.plainNotes.contains { $0.id == note.id && $0.body == "MEM_UPDATED" })
        let conflict = try XCTUnwrap(store.plainNotes.first { $0.id != note.id })
        XCTAssertEqual(conflict.body, "DISK_NEWER")

        let index = try XCTUnwrap(storage.loadIndex())
        XCTAssertEqual(index.entries.count, 2)
        let conflictEntry = try XCTUnwrap(index.entry(for: conflict.id))
        let conflictFile = try storage.loadMarkdownFile(at: tmpDir.appendingPathComponent(conflictEntry.fileName))
        XCTAssertTrue((conflictFile.title ?? "").contains("冲突副本"))

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testConcurrentUpdatesAllPersist() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("concurrent_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let store = VaultStore(storage: storage, settings: SettingsStore(defaults: UserDefaults(suiteName: "concurrent_\(UUID().uuidString)")!))
        store.configureForTesting(vaultId: "concurrent-vault")

        var notes: [Note] = []
        for i in 0..<10 {
            notes.append(try await store.createNote(body: "note-\(i)-v0", isEncrypted: false))
        }

        await withThrowingTaskGroup(of: Void.self) { group in
            for (i, note) in notes.enumerated() {
                group.addTask { @MainActor in
                    try await store.updateNote(note, body: "note-\(i)-final")
                }
            }
            try? await group.waitForAll()
        }

        // Every note's file ended with its own last write — no lost or crossed updates.
        let index = try XCTUnwrap(storage.loadIndex())
        for (i, note) in notes.enumerated() {
            let entry = try XCTUnwrap(index.entry(for: note.id))
            let file = try storage.loadMarkdownFile(at: tmpDir.appendingPathComponent(entry.fileName))
            XCTAssertEqual(file.body, "note-\(i)-final")
        }

        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - Phase 6: non-destructive session lock (P0-4)

    @MainActor
    func testLockSessionKeepsKeychainKey() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("locksession_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "locksession_\(UUID().uuidString)")!)
        settings.hasSeededDefaultNotes = true
        let keyStore = InMemoryKeyStore()
        let store = VaultStore(storage: storage, settings: settings, keyStore: keyStore)
        await store.initialize()
        try await store.createKey()
        _ = try await store.createNote(body: "机密", isEncrypted: true)
        XCTAssertEqual(store.decryptedNotes.count, 1)
        XCTAssertEqual(keyStore.allVaultIdCandidates().count, 1)

        await store.lockSession()
        XCTAssertTrue(store.decryptedNotes.isEmpty)
        XCTAssertEqual(store.lockedEncryptedNotes.count, 1)
        XCTAssertEqual(keyStore.allVaultIdCandidates().count, 1)   // Keychain key intact

        try await store.unlockSession()
        XCTAssertEqual(store.decryptedNotes.count, 1)
        XCTAssertTrue(store.lockedEncryptedNotes.isEmpty)

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @MainActor
    func testHandleEnterForegroundNeverDeletesKey() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("foreground_\(UUID().uuidString)")
        let storage = try TemporaryStorage(baseURL: tmpDir)
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "foreground_\(UUID().uuidString)")!)
        settings.hasSeededDefaultNotes = true
        let keyStore = InMemoryKeyStore()
        let store = VaultStore(storage: storage, settings: settings, keyStore: keyStore)
        await store.initialize()
        try await store.createKey()
        _ = try await store.createNote(body: "机密", isEncrypted: true)

        // The old code silently deleted the key here when this flag was set.
        settings.autoUnloadKeyOnForeground = true
        await store.handleEnterForeground()
        XCTAssertEqual(keyStore.allVaultIdCandidates().count, 1)
        XCTAssertEqual(store.decryptedNotes.count, 1)

        settings.autoUnloadKeyOnForeground = false
        await store.handleEnterForeground()
        XCTAssertEqual(keyStore.allVaultIdCandidates().count, 1)

        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - Phase 7: reliable debounced autosave (P0-5)

    private func makeNote(_ id: String = "n", body: String = "") -> Note {
        Note(id: id, body: body, createdAt: Date(), updatedAt: Date(), isEncrypted: false)
    }

    @MainActor
    func testEditorSessionBurstCoalescesToOneSave() async throws {
        var saves: [String] = []
        let note = makeNote()
        let session = EditorSession(
            initialNote: note, debounceInterval: 0.05,
            create: { _, _ in nil },
            update: { n, b in saves.append(b); return n },
            convert: { n, _, _ in n },
            discardEmpty: { _, _ in }
        )
        for i in 0..<10 { session.noteDidChange(body: "v\(i)", isEncrypted: false) }
        await session.flush(reason: .close)
        XCTAssertEqual(saves, ["v9"])   // exactly one save, newest body
    }

    @MainActor
    func testEditorSessionEditDuringSaveTriggersSecondSave() async throws {
        var saves: [String] = []
        var updateCount = 0
        var firstContinuation: CheckedContinuation<Void, Never>?
        let note = makeNote()
        let session = EditorSession(
            initialNote: note, debounceInterval: 0.05,
            create: { _, _ in nil },
            update: { n, b in
                updateCount += 1
                if updateCount == 1 { await withCheckedContinuation { firstContinuation = $0 } }
                saves.append(b)
                return n
            },
            convert: { n, _, _ in n },
            discardEmpty: { _, _ in }
        )
        session.noteDidChange(body: "A", isEncrypted: false)
        let flushTask = Task { await session.flush(reason: .close) }
        while firstContinuation == nil { await Task.yield() }
        session.noteDidChange(body: "B", isEncrypted: false)   // newer edit mid-save
        firstContinuation?.resume()
        await flushTask.value
        XCTAssertEqual(saves, ["A", "B"])   // regression for the old `guard !isSaving`
    }

    @MainActor
    func testEditorSessionFlushWaitsForAllSaves() async throws {
        var saved = ""
        let note = makeNote()
        let session = EditorSession(
            initialNote: note, debounceInterval: 10,   // long, so only flush drives the save
            create: { _, _ in nil },
            update: { n, b in saved = b; return n },
            convert: { n, _, _ in n },
            discardEmpty: { _, _ in }
        )
        session.noteDidChange(body: "final", isEncrypted: false)
        XCTAssertTrue(session.hasUnsavedChanges)
        await session.flush(reason: .close)
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertEqual(saved, "final")
    }

    @MainActor
    func testEditorSessionCloseIsIdempotent() async throws {
        var createCount = 0
        var discardCount = 0
        let session = EditorSession(
            initialNote: nil, debounceInterval: 10, autoDiscardEmpty: { true },
            create: { b, _ in createCount += 1; return Note(id: "c", body: b, createdAt: Date(), updatedAt: Date(), isEncrypted: false) },
            update: { n, _ in n },
            convert: { n, _, _ in n },
            discardEmpty: { _, _ in discardCount += 1 }
        )
        session.noteDidChange(body: "hello", isEncrypted: false)
        await session.close()
        await session.close()
        XCTAssertEqual(createCount, 1)
        XCTAssertLessThanOrEqual(discardCount, 1)
    }

    @MainActor
    func testEditorSessionCreateModeSemantics() async throws {
        var createCount = 0
        var updateCount = 0
        let session = EditorSession(
            initialNote: nil, debounceInterval: 10,
            create: { b, _ in createCount += 1; return Note(id: "c", body: b, createdAt: Date(), updatedAt: Date(), isEncrypted: false) },
            update: { n, b in updateCount += 1; return Note(id: n.id, body: b, createdAt: n.createdAt, updatedAt: Date(), isEncrypted: n.isEncrypted) },
            convert: { n, _, _ in n },
            discardEmpty: { _, _ in }
        )
        session.noteDidChange(body: "   ", isEncrypted: false)   // empty → no create
        await session.flush(reason: .close)
        XCTAssertEqual(createCount, 0)

        session.noteDidChange(body: "hi", isEncrypted: false)    // non-empty → create once
        await session.flush(reason: .close)
        XCTAssertEqual(createCount, 1)

        session.noteDidChange(body: "hi there", isEncrypted: false)   // then update
        await session.flush(reason: .close)
        XCTAssertEqual(createCount, 1)
        XCTAssertEqual(updateCount, 1)
    }
    #endif
}

private final class TemporaryStorage: VaultStorage, @unchecked Sendable {
    let fileManager = FileManager.default
    let _containerURL: URL
    var pendingMarkdownFileNames = Set<String>()
    var loadIndexError: Error?

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
        if let loadIndexError {
            throw loadIndexError
        }
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
        if pendingMarkdownFileNames.contains(url.lastPathComponent) {
            throw StorageError.iCloudDownloadPending
        }
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

/// In-memory `KeyStore` fake so VaultStore key lifecycle can be tested without the
/// real Keychain. Shared by reference, so it survives across VaultStore instances
/// (used to simulate app relaunch over the same vault).
@MainActor
final class InMemoryKeyStore: KeyStore {
    private var keys: [String: String] = [:]
    private var keyIds: [String: String] = [:]
    private var fingerprints: [String: String] = [:]

    init(seedVaultId: String? = nil, keyMaterial: String? = nil) {
        if let seedVaultId, let keyMaterial {
            keys[seedVaultId] = keyMaterial
        }
    }

    func saveKey(_ keyMaterial: String, forVaultId vaultId: String, keyId: String?, keyFingerprint: String?) throws {
        keys[vaultId] = keyMaterial
        if let keyId { keyIds[vaultId] = keyId }
        if let keyFingerprint { fingerprints[vaultId] = keyFingerprint }
    }

    func loadKey(forVaultId vaultId: String) throws -> String {
        guard let material = keys[vaultId] else { throw KeychainError.notFound }
        return material
    }

    func loadKeyId(forVaultId vaultId: String) -> String? { keyIds[vaultId] }
    func loadKeyFingerprint(forVaultId vaultId: String) -> String? { fingerprints[vaultId] }

    func saveKeyMetadata(keyId: String?, keyFingerprint: String, forVaultId vaultId: String) throws {
        if let keyId { keyIds[vaultId] = keyId }
        fingerprints[vaultId] = keyFingerprint
    }

    func deleteKey(forVaultId vaultId: String) throws {
        keys[vaultId] = nil
        keyIds[vaultId] = nil
        fingerprints[vaultId] = nil
    }

    func hasKey(forVaultId vaultId: String) -> Bool { keys[vaultId] != nil }
    func allVaultIdCandidates() -> [String] { Array(keys.keys) }
}
