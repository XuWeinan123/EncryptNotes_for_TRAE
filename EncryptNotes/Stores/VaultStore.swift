import Foundation
import SwiftUI
import Combine
import CryptoKit

#if os(iOS)
import UIKit
#endif

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

    @Published private(set) var state: VaultState = .loading
    @Published private(set) var decryptedNotes: [Note] = []
    @Published private(set) var plainNotes: [Note] = []
    @Published private(set) var lockedEncryptedNotes: [EncryptedNoteInfo] = []
    @Published private(set) var trashNotes: [TrashNote] = []
    @Published var selectedTag: String?
    @Published var searchText: String = ""
    @Published var lastError: String?
    @Published var needsKeyExport: Bool = false

    private let storage: VaultStorage
    private let cryptoService = CryptoService.shared
    private let keychainStore = KeychainStore.shared
    private let keyManager = VaultKeyManager.shared
    private let settings = SettingsStore.shared

    private var vaultId: String?
    private var currentKey: CryptoKit.SymmetricKey?
    private var noteIndex: NoteIndex = NoteIndex()

    private struct LoadedNotesSnapshot {
        let currentKey: CryptoKit.SymmetricKey?
        let resetPreferredModeToPlain: Bool
        let plainNotes: [Note]
        let decryptedNotes: [Note]
        let lockedEncryptedNotes: [EncryptedNoteInfo]
        let trashNotes: [TrashNote]
        let noteIndex: NoteIndex
    }

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
        self.vaultId = vaultId
        self.currentKey = key
        self.decryptedNotes = decryptedNotes
        self.plainNotes = plainNotes
        self.lockedEncryptedNotes = lockedEncryptedNotes
        self.trashNotes = trashNotes
        self.noteIndex = NoteIndex()
        self.state = .ready
    }
    #endif

    var isKeyLoaded: Bool { currentKey != nil }

    var readableNotes: [Note] {
        (plainNotes + decryptedNotes).sorted { $0.updatedAt > $1.updatedAt }
    }

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

        if selectedTag == nil && searchText.isEmpty {
            items.append(contentsOf: lockedEncryptedNotes.map { .locked($0) })
        }

        return items
    }

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

    var trashCount: Int { trashNotes.count }

    var readableNoteCount: Int { plainNotes.count + decryptedNotes.count }
    var encryptedNoteCount: Int { decryptedNotes.count + lockedEncryptedNotes.count }
    var lockedNoteCount: Int { lockedEncryptedNotes.count }
    var totalNoteCount: Int { readableNoteCount + lockedEncryptedNotes.count }

    func initialize() async {
        do {
            try await storage.initializeVault()
            await purgeExpiredTrash()

            var loadedIndex = (try? storage.loadIndex()) ?? NoteIndex()
            let vId = vaultId ?? UUID().uuidString
            vaultId = vId

            try await reconcileIndexWithFiles(&loadedIndex)
            noteIndex = loadedIndex

            await loadAllNotes()
            seedDefaultNotesIfNeeded()
            state = .ready
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }

    private func reconcileIndexWithFiles(_ index: inout NoteIndex) async throws {
        let notesURLs = (try? storage.listMarkdownFiles(in: .notes)) ?? []
        let trashURLs = (try? storage.listMarkdownFiles(in: .trash)) ?? []

        var seenIds = Set<String>()

        for url in notesURLs {
            guard let mdFile = try? storage.loadMarkdownFile(at: url) else { continue }
            seenIds.insert(mdFile.noteId)
            let fileName = url.lastPathComponent
            if index.entry(for: mdFile.noteId) == nil {
                let mode: NoteFileMode = mdFile.isEncrypted ? .encrypted : .plain
                index.upsert(NoteIndexEntry(
                    noteId: mdFile.noteId,
                    fileName: fileName,
                    mode: mode,
                    location: .notes
                ))
            }
        }

        for url in trashURLs {
            guard let mdFile = try? storage.loadMarkdownFile(at: url) else { continue }
            seenIds.insert(mdFile.noteId)
            let fileName = url.lastPathComponent
            if index.entry(for: mdFile.noteId) == nil {
                let mode: NoteFileMode = mdFile.isEncrypted ? .encrypted : .plain
                let now = Date()
                index.upsert(NoteIndexEntry(
                    noteId: mdFile.noteId,
                    fileName: fileName,
                    mode: mode,
                    location: .trash,
                    deletedAt: mdFile.updatedAt,
                    purgeAfter: mdFile.updatedAt.addingTimeInterval(30 * 86400),
                    originalLocation: .notes
                ))
            }
        }

        index.entries.removeAll { !seenIds.contains($0.noteId) }

        try storage.saveIndex(index)
    }

    private func loadAllNotes() async {
        do {
            let loadedKey: CryptoKit.SymmetricKey?
            if let vId = vaultId,
               let keyMaterial = try? keychainStore.loadKey(forVaultId: vId),
               let key = try? keyManager.keyFromBase64(keyMaterial) {
                loadedKey = key
            } else {
                loadedKey = nil
            }

            let preferredMode = settings.preferredNoteMode
            let snapshot = try await Task.detached(priority: .userInitiated) { [storage, noteIndex, preferredMode] in
                try Self.loadNotesSnapshot(
                    storage: storage,
                    index: noteIndex,
                    currentKey: loadedKey,
                    preferredMode: preferredMode
                )
            }.value

            currentKey = snapshot.currentKey
            if snapshot.resetPreferredModeToPlain {
                settings.preferredNoteMode = .plain
            }
            plainNotes = snapshot.plainNotes
            decryptedNotes = snapshot.decryptedNotes
            lockedEncryptedNotes = snapshot.lockedEncryptedNotes
            trashNotes = snapshot.trashNotes
            noteIndex = snapshot.noteIndex
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }

    nonisolated private static func loadNotesSnapshot(
        storage: VaultStorage,
        index: NoteIndex,
        currentKey: CryptoKit.SymmetricKey?,
        preferredMode: NoteFileMode
    ) throws -> LoadedNotesSnapshot {
        let resetPreferredModeToPlain = currentKey == nil && preferredMode == .encrypted
        var plainNotes: [Note] = []
        var decryptedNotes: [Note] = []
        var lockedEncryptedNotes: [EncryptedNoteInfo] = []
        var trashNotes: [TrashNote] = []
        var updatedIndex = index

        for entry in index.entries {
            guard let url = urlForEntry(entry, storage: storage) else { continue }

            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            if entry.location == .trash {
                if let trashNote = loadTrashNote(entry: entry, url: url, key: currentKey, storage: storage) {
                    trashNotes.append(trashNote)
                }
                continue
            }

            do {
                let mdFile = try storage.loadMarkdownFile(at: url)
                let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
                let size = attrs[.size] as? Int ?? 0

                if entry.mode == .plain {
                    plainNotes.append(Note(
                        id: mdFile.noteId,
                        body: mdFile.body,
                        createdAt: mdFile.createdAt,
                        updatedAt: mdFile.updatedAt,
                        isEncrypted: false
                    ))
                } else {
                    if let key = currentKey {
                        do {
                            let decryptedBody = try CryptoService.shared.decryptMarkdownBody(mdFile.body, using: key)
                            decryptedNotes.append(Note(
                                id: mdFile.noteId,
                                body: decryptedBody,
                                createdAt: mdFile.createdAt,
                                updatedAt: mdFile.updatedAt,
                                isEncrypted: true
                            ))
                        } catch {
                            lockedEncryptedNotes.append(EncryptedNoteInfo(
                                id: mdFile.noteId,
                                url: url,
                                ciphertextPreview: String(mdFile.body.prefix(50)),
                                fileSize: size,
                                updatedAt: mdFile.updatedAt
                            ))
                        }
                    } else {
                        lockedEncryptedNotes.append(EncryptedNoteInfo(
                            id: mdFile.noteId,
                            url: url,
                            ciphertextPreview: String(mdFile.body.prefix(50)),
                            fileSize: size,
                            updatedAt: mdFile.updatedAt
                        ))
                    }
                }
            } catch {
                continue
            }
        }

        plainNotes.sort { $0.updatedAt > $1.updatedAt }
        decryptedNotes.sort { $0.updatedAt > $1.updatedAt }
        trashNotes.sort { $0.deletedAt > $1.deletedAt }

        return LoadedNotesSnapshot(
            currentKey: currentKey,
            resetPreferredModeToPlain: resetPreferredModeToPlain,
            plainNotes: plainNotes,
            decryptedNotes: decryptedNotes,
            lockedEncryptedNotes: lockedEncryptedNotes,
            trashNotes: trashNotes,
            noteIndex: updatedIndex
        )
    }

    nonisolated private static func urlForEntry(_ entry: NoteIndexEntry, storage: VaultStorage) -> URL? {
        let dir: NoteFileLocation = entry.location
        guard let container = storage.containerURL else { return nil }
        return container.appendingPathComponent(dir.rawValue).appendingPathComponent(entry.fileName)
    }

    nonisolated private static func loadTrashNote(entry: NoteIndexEntry, url: URL, key: SymmetricKey?, storage: VaultStorage) -> TrashNote? {
        guard let mdFile = try? storage.loadMarkdownFile(at: url) else { return nil }

        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let size = attrs[.size] as? Int ?? 0

        let body: String?
        let preview: String?

        if entry.mode == .plain {
            body = mdFile.body
            preview = nil
        } else {
            if let k = key, let decrypted = try? CryptoService.shared.decryptMarkdownBody(mdFile.body, using: k) {
                body = decrypted
                preview = nil
            } else {
                body = nil
                preview = String(mdFile.body.prefix(50))
            }
        }

        let deletedAt = entry.deletedAt ?? mdFile.updatedAt
        let purgeAfter = entry.purgeAfter ?? deletedAt.addingTimeInterval(30 * 86400)

        return TrashNote(
            id: entry.noteId,
            isEncrypted: entry.mode == .encrypted,
            createdAt: mdFile.createdAt,
            updatedAt: mdFile.updatedAt,
            deletedAt: deletedAt,
            purgeAfter: purgeAfter,
            url: url,
            body: body,
            ciphertextPreview: preview,
            fileSize: size
        )
    }

    private func seedDefaultNotesIfNeeded() {
        guard !settings.hasSeededDefaultNotes else { return }
        guard plainNotes.isEmpty && decryptedNotes.isEmpty && lockedEncryptedNotes.isEmpty else {
            settings.hasSeededDefaultNotes = true
            return
        }

        let now = Date()
        let defaults: [(String, Date)] = [
            ("欢迎使用别看我。\n\n你可以像写卡片一样记录想法，也可以在需要时创建加密笔记。\n\n#欢迎", now),
            ("标签写法示例：\n\n在正文中输入 #灵感 或 #日记 ，它们会出现在侧边栏的标签区域。\n\n#使用说明 #标签", now.addingTimeInterval(-1)),
            ("加密笔记适合保存更私密的内容。\n\n首次创建笔记时，你可以选择创建密钥。创建密钥后，新建笔记时可以打开\"加密笔记\"开关。\n\n#加密", now.addingTimeInterval(-2))
        ]

        for (body, date) in defaults {
            let noteId = UUID().uuidString
            let mdFile = MarkdownNoteFile(
                noteId: noteId,
                createdAt: date,
                updatedAt: date,
                body: body
            )
            if let url = storage.noteFileURL(for: noteId) {
                try? storage.saveMarkdownFile(mdFile, at: url)
                noteIndex.upsert(NoteIndexEntry(
                    noteId: noteId,
                    fileName: "\(noteId).md",
                    mode: .plain,
                    location: .notes
                ))
                plainNotes.append(Note(
                    id: noteId,
                    body: body,
                    createdAt: date,
                    updatedAt: date,
                    isEncrypted: false
                ))
            }
        }
        try? storage.saveIndex(noteIndex)
        plainNotes.sort { $0.updatedAt > $1.updatedAt }
        settings.hasSeededDefaultNotes = true
    }

    func createKey() async throws {
        let vId = vaultId ?? UUID().uuidString
        vaultId = vId

        let key = keyManager.generateKey()
        let keyMaterial = keyManager.keyToBase64(key)

        try keychainStore.saveKey(keyMaterial, forVaultId: vId)
        currentKey = key

        await reloadAllNotes()

        needsKeyExport = true
        settings.preferredNoteMode = .encrypted
    }

    func importKeyFile(from url: URL) async throws -> Bool {
        let vId = vaultId ?? UUID().uuidString

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

        let key = try keyManager.extractKey(vaultKey)

        let encURLs = noteIndex.entries
            .filter { $0.location == .notes && $0.mode == .encrypted }
            .compactMap { Self.urlForEntry($0, storage: storage) }

        for encUrl in encURLs {
            let mdFile = try storage.loadMarkdownFile(at: encUrl)
            _ = try cryptoService.decryptMarkdownBody(mdFile.body, using: key)
        }

        try keychainStore.saveKey(vaultKey.keyMaterial, forVaultId: vId)
        vaultId = vId
        currentKey = key

        await reloadAllNotes()

        settings.preferredNoteMode = .encrypted
        return true
    }

    func unloadKey() async throws {
        guard let vId = vaultId else { return }
        try keychainStore.deleteKey(forVaultId: vId)
        currentKey = nil
        decryptedNotes = []

        await reloadAllNotes()
        settings.preferredNoteMode = .plain

        if let tag = selectedTag, !allTags.contains(where: { $0.tag == tag }) {
            selectedTag = nil
        }
    }

    func resetKey() async throws {
        guard let vId = vaultId else { throw VaultError.notReady }

        try keychainStore.deleteKey(forVaultId: vId)

        let encEntries = noteIndex.entries.filter { $0.mode == .encrypted }
        for entry in encEntries {
            if let url = Self.urlForEntry(entry, storage: storage) {
                try? storage.permanentlyDeleteFile(at: url)
            }
            noteIndex.removeEntry(for: entry.noteId)
        }
        try storage.saveIndex(noteIndex)

        let key = keyManager.generateKey()
        let keyMaterial = keyManager.keyToBase64(key)
        try keychainStore.saveKey(keyMaterial, forVaultId: vId)
        currentKey = key

        await reloadAllNotes()

        needsKeyExport = true
        settings.preferredNoteMode = .encrypted
    }

    private func reloadAllNotes() async {
        do {
            var loadedIndex = (try? storage.loadIndex()) ?? noteIndex
            try await reconcileIndexWithFiles(&loadedIndex)
            noteIndex = loadedIndex

            let loadedKey: CryptoKit.SymmetricKey?
            if let vId = vaultId,
               let keyMaterial = try? keychainStore.loadKey(forVaultId: vId),
               let key = try? keyManager.keyFromBase64(keyMaterial) {
                loadedKey = key
            } else {
                loadedKey = nil
            }

            let preferredMode = settings.preferredNoteMode
            let snapshot = try await Task.detached(priority: .userInitiated) { [storage, noteIndex, preferredMode] in
                try Self.loadNotesSnapshot(
                    storage: storage,
                    index: noteIndex,
                    currentKey: loadedKey,
                    preferredMode: preferredMode
                )
            }.value

            currentKey = snapshot.currentKey
            plainNotes = snapshot.plainNotes
            decryptedNotes = snapshot.decryptedNotes
            lockedEncryptedNotes = snapshot.lockedEncryptedNotes
            trashNotes = snapshot.trashNotes
            noteIndex = snapshot.noteIndex
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }

    func exportKeyFile() throws -> URL {
        guard let key = currentKey else {
            throw KeychainError.notFound
        }

        let vaultKey = keyManager.generateVaultKey(key: key)
        let data = try JSONEncoder.default.encode(vaultKey)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("别看我-密钥-\(dateStr).bkwkey")
        try data.write(to: tempURL)
        return tempURL
    }

    @discardableResult
    func createNote(body: String, isEncrypted: Bool) async throws -> Note {
        guard let vId = vaultId else { throw VaultError.notReady }
        vaultId = vId

        let noteId = UUID().uuidString
        let now = Date()

        let finalBody: String
        if isEncrypted {
            guard let key = currentKey else { throw VaultError.keyNotLoaded }
            finalBody = try cryptoService.encryptMarkdownBody(body, using: key)
        } else {
            finalBody = body
        }

        let mdFile = MarkdownNoteFile(
            noteId: noteId,
            createdAt: now,
            updatedAt: now,
            body: finalBody
        )

        guard let url = storage.noteFileURL(for: noteId) else {
            throw StorageError.iCloudUnavailable
        }
        try storage.saveMarkdownFile(mdFile, at: url)

        let entry = NoteIndexEntry(
            noteId: noteId,
            fileName: "\(noteId).md",
            mode: isEncrypted ? .encrypted : .plain,
            location: .notes
        )
        noteIndex.upsert(entry)
        try storage.saveIndex(noteIndex)

        let note = Note(
            id: noteId,
            body: body,
            createdAt: now,
            updatedAt: now,
            isEncrypted: isEncrypted
        )

        if isEncrypted {
            decryptedNotes.insert(note, at: 0)
        } else {
            plainNotes.insert(note, at: 0)
        }

        return note
    }

    func updateNote(_ note: Note, body: String) async throws {
        guard let _ = vaultId else { throw VaultError.notReady }
        let now = Date()

        let finalBody: String
        if note.isEncrypted {
            guard let key = currentKey else { throw VaultError.keyNotLoaded }
            finalBody = try cryptoService.encryptMarkdownBody(body, using: key)
        } else {
            finalBody = body
        }

        guard let url = storage.noteFileURL(for: note.id) else {
            throw StorageError.iCloudUnavailable
        }

        if let diskFile = try? storage.loadMarkdownFile(at: url), diskFile.updatedAt > note.updatedAt {
            _ = try storage.createConflictCopy(for: url)
        }

        let mdFile = MarkdownNoteFile(
            noteId: note.id,
            createdAt: note.createdAt,
            updatedAt: now,
            body: finalBody
        )
        try storage.saveMarkdownFile(mdFile, at: url)

        if let entry = noteIndex.entry(for: note.id) {
            noteIndex.upsert(entry)
            try? storage.saveIndex(noteIndex)
        }

        let updatedNote = Note(
            id: note.id,
            body: body,
            createdAt: note.createdAt,
            updatedAt: now,
            isEncrypted: note.isEncrypted
        )

        if note.isEncrypted {
            if let index = decryptedNotes.firstIndex(where: { $0.id == note.id }) {
                decryptedNotes[index] = updatedNote
            }
        } else {
            if let index = plainNotes.firstIndex(where: { $0.id == note.id }) {
                plainNotes[index] = updatedNote
            }
        }
    }

    func deleteNote(_ note: Note) async throws {
        let now = Date()
        let purgeAfter = now.addingTimeInterval(30 * 86400)

        guard let srcURL = (note.isEncrypted ? storage.noteFileURL(for: note.id) : storage.noteFileURL(for: note.id)) else {
            throw StorageError.iCloudUnavailable
        }
        guard FileManager.default.fileExists(atPath: srcURL.path) else { return }
        guard let trashURL = storage.trashFileURL(for: note.id) else {
            throw StorageError.iCloudUnavailable
        }

        let mdFile = try storage.loadMarkdownFile(at: srcURL)
        let trashFile = MarkdownNoteFile(
            noteId: mdFile.noteId,
            createdAt: mdFile.createdAt,
            updatedAt: now,
            body: mdFile.body
        )
        try storage.saveMarkdownFile(trashFile, at: trashURL)
        try storage.permanentlyDeleteFile(at: srcURL)

        if let entry = noteIndex.entry(for: note.id) {
            noteIndex.upsert(NoteIndexEntry(
                noteId: entry.noteId,
                fileName: "\(note.id).md",
                mode: entry.mode,
                location: .trash,
                deletedAt: now,
                purgeAfter: purgeAfter,
                originalLocation: .notes
            ))
            try storage.saveIndex(noteIndex)
        }

        decryptedNotes.removeAll { $0.id == note.id }
        plainNotes.removeAll { $0.id == note.id }
        lockedEncryptedNotes.removeAll { $0.id == note.id }

        await reloadTrashOnly()
    }

    func discardEmptyNote(_ note: Note) async throws {
        guard note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if let url = storage.noteFileURL(for: note.id),
           FileManager.default.fileExists(atPath: url.path) {
            try storage.permanentlyDeleteFile(at: url)
        }
        noteIndex.removeEntry(for: note.id)
        try? storage.saveIndex(noteIndex)

        decryptedNotes.removeAll { $0.id == note.id }
        plainNotes.removeAll { $0.id == note.id }
        lockedEncryptedNotes.removeAll { $0.id == note.id }
    }

    func deleteLockedNote(_ info: EncryptedNoteInfo) async throws {
        let now = Date()
        let purgeAfter = now.addingTimeInterval(30 * 86400)

        let mdFile = try storage.loadMarkdownFile(at: info.url)
        guard let trashURL = storage.trashFileURL(for: info.id) else {
            throw StorageError.iCloudUnavailable
        }

        let trashFile = MarkdownNoteFile(
            noteId: mdFile.noteId,
            createdAt: mdFile.createdAt,
            updatedAt: now,
            body: mdFile.body
        )
        try storage.saveMarkdownFile(trashFile, at: trashURL)
        try storage.permanentlyDeleteFile(at: info.url)

        if let entry = noteIndex.entry(for: info.id) {
            noteIndex.upsert(NoteIndexEntry(
                noteId: entry.noteId,
                fileName: "\(info.id).md",
                mode: entry.mode,
                location: .trash,
                deletedAt: now,
                purgeAfter: purgeAfter,
                originalLocation: .notes
            ))
            try storage.saveIndex(noteIndex)
        }

        lockedEncryptedNotes.removeAll { $0.id == info.id }
        await reloadTrashOnly()
    }

    func restoreTrashNote(_ trashNote: TrashNote) async throws {
        guard let srcURL = storage.trashFileURL(for: trashNote.id) else {
            throw StorageError.iCloudUnavailable
        }
        guard let dstURL = storage.noteFileURL(for: trashNote.id) else {
            throw StorageError.iCloudUnavailable
        }
        guard FileManager.default.fileExists(atPath: srcURL.path) else { return }

        let mdFile = try storage.loadMarkdownFile(at: srcURL)
        let restoredFile = MarkdownNoteFile(
            noteId: mdFile.noteId,
            createdAt: mdFile.createdAt,
            updatedAt: Date(),
            body: mdFile.body
        )
        try storage.saveMarkdownFile(restoredFile, at: dstURL)
        try storage.permanentlyDeleteFile(at: srcURL)

        if let entry = noteIndex.entry(for: trashNote.id) {
            noteIndex.upsert(NoteIndexEntry(
                noteId: entry.noteId,
                fileName: "\(trashNote.id).md",
                mode: entry.mode,
                location: .notes
            ))
            try storage.saveIndex(noteIndex)
        }

        trashNotes.removeAll { $0.id == trashNote.id }
        await reloadAllNotes()
    }

    func permanentlyDeleteTrashNote(_ trashNote: TrashNote) async throws {
        try storage.permanentlyDeleteFile(at: trashNote.url)
        noteIndex.removeEntry(for: trashNote.id)
        try? storage.saveIndex(noteIndex)
        trashNotes.removeAll { $0.id == trashNote.id }
    }

    func emptyTrash() async throws {
        try storage.emptyTrash()
        noteIndex.entries.removeAll { $0.location == .trash }
        try storage.saveIndex(noteIndex)
        trashNotes = []
    }

    func purgeExpiredTrash() async {
        let now = Date()
        var purgedIds: [String] = []
        for entry in noteIndex.entries where entry.location == .trash {
            if let purgeAfter = entry.purgeAfter, purgeAfter <= now {
                if let url = storage.trashFileURL(for: entry.noteId) {
                    try? storage.permanentlyDeleteFile(at: url)
                }
                purgedIds.append(entry.noteId)
            }
        }
        if !purgedIds.isEmpty {
            for id in purgedIds {
                noteIndex.removeEntry(for: id)
            }
            try? storage.saveIndex(noteIndex)
        }
    }

    private func reloadTrashOnly() async {
        let preferredMode = settings.preferredNoteMode
        let snapshot = try? await Task.detached(priority: .userInitiated) { [storage, noteIndex, currentKey, preferredMode] in
            try Self.loadNotesSnapshot(
                storage: storage,
                index: noteIndex,
                currentKey: currentKey,
                preferredMode: preferredMode
            )
        }.value
        if let snap = snapshot {
            trashNotes = snap.trashNotes
        }
    }

    func batchDeleteNotes(_ items: [NoteListItem]) async throws -> (deleted: Int, errors: Int) {
        var deleted = 0
        var errors = 0
        for item in items {
            do {
                switch item {
                case .readable(let note):
                    try await deleteNote(note)
                case .locked(let info):
                    try await deleteLockedNote(info)
                }
                deleted += 1
            } catch {
                errors += 1
            }
        }
        return (deleted, errors)
    }

    #if os(iOS)
    @discardableResult
    func batchCopyNotesToClipboard(_ items: [NoteListItem]) -> (copied: Int, skipped: Int) {
        var plainBodies: [String] = []
        var skipped = 0
        for item in items {
            switch item {
            case .readable(let note):
                if !note.isEncrypted {
                    plainBodies.append(note.body)
                } else {
                    skipped += 1
                }
            case .locked:
                skipped += 1
            }
        }
        if !plainBodies.isEmpty {
            UIPasteboard.general.string = plainBodies.joined(separator: "\n\n---\n\n")
        }
        return (plainBodies.count, skipped)
    }
    #endif

    func exportReadableNotesAsZip() throws -> (url: URL, exportedCount: Int, skippedCount: Int) {
        let plainOnly = plainNotes.sorted { $0.updatedAt > $1.updatedAt }
        let skippedCount = decryptedNotes.count + lockedEncryptedNotes.count

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("别看我-笔记-\(dateStr)-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let fileDateFormatter = DateFormatter()
        fileDateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"

        for (index, note) in plainOnly.enumerated() {
            let timestamp = fileDateFormatter.string(from: note.updatedAt)
            let shortId = String(note.id.prefix(6))
            let safeIndex = String(format: "%03d", index + 1)
            let fileName = "\(safeIndex)-\(timestamp)-\(shortId).md"
            let fileURL = tmpDir.appendingPathComponent(fileName)

            let mdFile = MarkdownNoteFile(
                noteId: note.id,
                createdAt: note.createdAt,
                updatedAt: note.updatedAt,
                body: note.body
            )
            let data = try mdFile.render()
            try data.write(to: fileURL, options: .atomic)
        }

        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("别看我-笔记-\(dateStr).zip")
        try ZipUtility.createZip(from: tmpDir, to: zipURL)
        try? FileManager.default.removeItem(at: tmpDir)

        return (zipURL, plainOnly.count, skippedCount)
    }

    func handleEnterBackground() {
        guard settings.autoUnloadKeyOnForeground == false else { return }
    }

    func handleEnterForeground() async {
        await purgeExpiredTrash()
        if settings.autoUnloadKeyOnForeground {
            try? await unloadKey()
        }
    }
}

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
