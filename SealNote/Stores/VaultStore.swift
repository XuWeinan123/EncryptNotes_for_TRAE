import Foundation
import SwiftUI
import Combine
import CryptoKit

#if os(iOS)
import UIKit
#endif

nonisolated enum VaultState: Equatable {
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

#if os(macOS)
nonisolated enum MacVaultKeyStatus: Equatable {
    case noReference
    case available
    case invalid(VaultKeyFileError)
}
#endif

#if os(iOS)
nonisolated enum IOSVaultKeyStatus: Equatable {
    case noReference
    case available
    case invalid(VaultKeyFileError)
}
#endif

nonisolated struct EncryptedNoteInfo: Identifiable, Equatable {
    let id: String
    let url: URL
    let title: String
    let ciphertextPreview: String
    let fileSize: Int
    let createdAt: Date
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
    @Published var needsKeyExport: Bool = false {
        didSet { settings.needsKeyExportPending = needsKeyExport }
    }

    #if os(iOS)
    /// True when the vault is pinned to iCloud but iCloud is unavailable this launch,
    /// so we're temporarily using local storage instead (P0-3).
    @Published private(set) var storageRootMismatch: Bool = false
    /// True when the vault is on iCloud but a local fallback vault still holds notes
    /// written while iCloud was signed out (P0-3).
    @Published private(set) var strandedLocalDataDetected: Bool = false
    #endif

    private let storage: VaultStorage
    private let cryptoService = CryptoService.shared
    private let keyStore: KeyStore
    private let keyManager = VaultKeyManager.shared
    private let settings: SettingsStore
    private let identityStore: VaultIdentityStore
    /// True when `storage` was picked by `resolveStorage` (real app) rather than
    /// injected by a test — gates the pin/mismatch/stranded bookkeeping.
    private let usesResolvedStorage: Bool
    /// Serial off-main lane for all disk mutations, so concurrent saves neither
    /// interleave on disk nor block the main actor (P0/P1-2).
    private let fileIO = VaultFileIO()

    private var vaultId: String?
    private var currentKey: CryptoKit.SymmetricKey?
    private var noteIndex: NoteIndex = NoteIndex()
    private var pendingDownloadRetryTask: Task<Void, Never>?
    private var pendingDownloadCount = 0
    #if os(iOS)
    private var cloudOnlyPlainNoteIDs = Set<String>()
    #endif

    private struct LoadedNotesSnapshot {
        let currentKey: CryptoKit.SymmetricKey?
        let resetPreferredModeToPlain: Bool
        let plainNotes: [Note]
        let decryptedNotes: [Note]
        let lockedEncryptedNotes: [EncryptedNoteInfo]
        let trashNotes: [TrashNote]
        let noteIndex: NoteIndex
        let pendingDownloadKeys: Set<String>
        #if os(iOS)
        let cloudOnlyPlainNoteIDs: Set<String>
        #endif
    }

    private struct PreparedIndexResult {
        let index: NoteIndex
        let removedMissingFiles: [String]
        let pendingDownloadKeys: Set<String>
        let discoveredFileCount: Int
    }

    private struct ReconciledIndexResult {
        let missingFiles: [String]
        let pendingDownloadKeys: Set<String>
        let changed: Bool
    }

    private struct DiscoveredIndexResult {
        let discoveredFileCount: Int
        let pendingDownloadKeys: Set<String>
        let changed: Bool
    }

    private enum KeyReloadMode {
        case keychain
        case explicit(CryptoKit.SymmetricKey?)
    }

    init(storage: VaultStorage? = nil, settings: SettingsStore? = nil, keyStore: KeyStore = KeychainStore.shared) {
        let resolvedSettings = settings ?? .shared
        if let storage {
            self.storage = storage
            self.usesResolvedStorage = false
        } else {
            self.storage = Self.resolveStorage(
                pinned: resolvedSettings.pinnedStorageRoot,
                iCloudAvailable: ICloudVaultStorage.shared.isAvailable
            ).storage
            self.usesResolvedStorage = true
        }
        self.settings = resolvedSettings
        self.keyStore = keyStore
        self.identityStore = VaultIdentityStore(defaults: resolvedSettings.userDefaults, keyStore: keyStore)
    }

    #if DEBUG
    func configureForTesting(
        vaultId: String,
        key: CryptoKit.SymmetricKey? = nil,
        decryptedNotes: [Note] = [],
        plainNotes: [Note] = [],
        lockedEncryptedNotes: [EncryptedNoteInfo] = [],
        trashNotes: [TrashNote] = [],
        cloudOnlyPlainNoteIDs: Set<String> = []
    ) {
        self.vaultId = vaultId
        self.currentKey = key
        self.decryptedNotes = decryptedNotes
        self.plainNotes = plainNotes
        self.lockedEncryptedNotes = lockedEncryptedNotes
        self.trashNotes = trashNotes
        self.noteIndex = NoteIndex()
        self.state = .ready
        #if os(iOS)
        self.cloudOnlyPlainNoteIDs = cloudOnlyPlainNoteIDs
        #endif
    }
    #endif

    var isKeyLoaded: Bool {
        #if DEBUG
        if currentKey != nil {
            return true
        }
        #endif
        #if os(macOS)
        if case .available = macKeyStatus {
            return true
        }
        return false
        #else
        if case .available = iosKeyStatus {
            return true
        }
        return false
        #endif
    }

    #if os(macOS)
    var hasKeyReference: Bool {
        settings.vaultKeyFileReference != nil
    }

    var keyFileDisplayPath: String? {
        settings.vaultKeyFileReference?.displayPath
    }

    var macKeyStatus: MacVaultKeyStatus {
        guard hasKeyReference else { return .noReference }
        do {
            _ = try loadConfiguredKeyFile()
            return .available
        } catch let error as VaultKeyFileError {
            return .invalid(error)
        } catch {
            return .invalid(.invalidFile)
        }
    }

    var isConfiguredKeyFileAvailable: Bool {
        if case .available = macKeyStatus {
            return true
        }
        return false
    }
    #endif

    #if os(iOS)
    var hasKeyReference: Bool {
        guard let vId = vaultId else { return false }
        return keyStore.hasKey(forVaultId: vId)
    }

    var iosKeyStatus: IOSVaultKeyStatus {
        do {
            _ = try loadStoredIOSKey()
            return .available
        } catch KeychainError.notFound {
            return .noReference
        } catch let error as VaultKeyFileError {
            return .invalid(error)
        } catch CryptoError.invalidKeyLength, CryptoError.invalidKeyMaterial {
            return .invalid(.invalidFile)
        } catch let error as KeychainError {
            switch error {
            case .notFound:
                return .noReference
            default:
                return .invalid(.permissionDenied)
            }
        } catch {
            return .invalid(.invalidFile)
        }
    }
    #endif

    var storageContainerURL: URL? { storage.containerURL }

    var isUsingICloudStorage: Bool { storage is ICloudVaultStorage }

    var readableNotes: [Note] {
        (plainNotes + decryptedNotes).sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.id < $1.id
        }
    }

    func displayTitle(for note: Note, emptyTitle: String = NoteTitleFormatter.emptyTitle) -> String {
        if let entry = noteIndex.entry(for: note.id) {
            let fileTitle = NoteTitleFormatter.displayTitle(fromFileName: entry.fileName, emptyTitle: "")
            if !fileTitle.isEmpty {
                return fileTitle
            }
        }
        return NoteTitleFormatter.displayTitle(from: note.body, emptyTitle: emptyTitle)
    }

    func hasStableTitle(for note: Note) -> Bool {
        guard let entry = noteIndex.entry(for: note.id) else { return false }
        let mdFile = Self.urlForEntry(entry, storage: storage).flatMap { try? storage.loadMarkdownFile(at: $0) }
        return Self.stableExistingTitle(for: entry, mdFile: mdFile) != nil
    }

    func noteMatchesSearch(_ note: Note, searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        if note.isEncrypted {
            return displayTitle(for: note, emptyTitle: "").localizedCaseInsensitiveContains(query)
        }

        return displayTitle(for: note, emptyTitle: "").localizedCaseInsensitiveContains(query)
            || note.body.localizedCaseInsensitiveContains(query)
    }

    func lockedNoteMatchesSearch(_ info: EncryptedNoteInfo, searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return info.title.localizedCaseInsensitiveContains(query)
    }

    var filteredNotes: [NoteListItem] {
        var readable = readableNotes
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let tag = selectedTag {
            readable = readable.filter { note in
                !note.isEncrypted
                    && TagParser.tags(
                        in: note.body,
                        excludingHexColors: settings.excludeHexColorsFromTags
                    ).contains(tag)
            }
        }

        if !query.isEmpty {
            readable = readable.filter { noteMatchesSearch($0, searchText: query) }
        }

        var items: [NoteListItem] = readable.map { .readable($0) }

        if selectedTag == nil {
            let locked = query.isEmpty
                ? lockedEncryptedNotes
                : lockedEncryptedNotes.filter { lockedNoteMatchesSearch($0, searchText: query) }
            items.append(contentsOf: locked.map { .locked($0) })
        }

        return items.sorted(by: NoteListOrdering.newestCreatedFirst)
    }

    var allTags: [TagCount] {
        var counts: [String: Int] = [:]
        // Encrypted-note tags remain private even while the note is open and
        // decrypted in this process. They must not leak into global filters.
        for note in readableNotes where !note.isEncrypted {
            for tag in TagParser.tags(in: note.body, excludingHexColors: settings.excludeHexColorsFromTags) {
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
    var encryptedEntryCount: Int { noteIndex.entries.filter { $0.mode == .encrypted }.count }
    var lockedNoteCount: Int { lockedEncryptedNotes.count }
    var totalNoteCount: Int { readableNoteCount + lockedEncryptedNotes.count }

    #if os(iOS)
    func isCloudOnly(_ note: Note) -> Bool {
        cloudOnlyPlainNoteIDs.contains(note.id)
    }

    func openCloudOnlyNote(_ note: Note) async throws -> Note {
        guard cloudOnlyPlainNoteIDs.contains(note.id),
              let entry = noteIndex.entry(for: note.id),
              let url = Self.urlForEntry(entry, storage: storage) else {
            return note
        }
        let mdFile = try await fileIO.perform { [storage] in try storage.loadMarkdownFile(at: url) }
        let loaded = Note(
            id: mdFile.noteId,
            body: mdFile.body,
            createdAt: mdFile.createdAt,
            updatedAt: mdFile.updatedAt,
            isEncrypted: false
        )
        cloudOnlyPlainNoteIDs.remove(note.id)
        if let index = plainNotes.firstIndex(where: { $0.id == note.id }) {
            plainNotes[index] = loaded
        }
        return loaded
    }
    #endif

    func initialize() async {
        do {
            let prepared = try await Task.detached(priority: .userInitiated) { [storage] in
                try await Self.prepareIndex(storage: storage, fallbackIndex: NoteIndex(), initializeStorage: true)
            }.value
            noteIndex = prepared.index
            vaultId = identityStore.resolveVaultId(
                containerURL: storage.containerURL,
                index: noteIndex,
                validate: { [weak self] candidate in
                    self?.canDecryptExistingEncryptedNote(withCandidate: candidate) ?? false
                }
            )
            needsKeyExport = settings.needsKeyExportPending
            #if os(iOS)
            if usesResolvedStorage {
                let resolution = Self.resolveStorage(
                    pinned: settings.pinnedStorageRoot,
                    iCloudAvailable: ICloudVaultStorage.shared.isAvailable
                )
                settings.pinnedStorageRoot = resolution.pin
                storageRootMismatch = resolution.mismatch
                if isUsingICloudStorage, let localContainer = LocalFallbackStorage.shared.containerURL {
                    strandedLocalDataDetected = Self.hasVaultData(at: localContainer)
                }
            }
            #endif
            reportMissingIndexedFiles(prepared.removedMissingFiles)

            let loadedPendingDownloadKeys = await loadAllNotes()
            let pendingDownloadCount = prepared.pendingDownloadKeys.union(loadedPendingDownloadKeys).count
            if case .error = state {
                return
            }
            if pendingDownloadCount == 0 {
                handlePendingDownloads(0)
                seedDefaultNotesIfNeeded()
            } else {
                handlePendingDownloads(pendingDownloadCount)
            }
            state = .ready
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }

    nonisolated private static func prepareIndex(
        storage: VaultStorage,
        fallbackIndex: NoteIndex,
        initializeStorage: Bool
    ) async throws -> PreparedIndexResult {
        if initializeStorage {
            try await storage.initializeVault()
        }

        let loadedIndex = try storage.loadIndex()
        var index = loadedIndex ?? fallbackIndex
        let reconciled = try reconcileIndexWithFiles(&index, storage: storage)
        let discovered = try discoverUnindexedMarkdownFiles(in: &index, storage: storage)
        let purged = purgeExpiredTrash(in: &index, storage: storage)
        if loadedIndex == nil || reconciled.changed || discovered.changed || purged {
            try storage.saveIndex(index)
        }
        if discovered.discoveredFileCount > 0 {
            MaintenanceLogStore.shared.record("unindexed_markdown_files_added_to_index", fields: [
                "count": discovered.discoveredFileCount
            ])
        }
        return PreparedIndexResult(
            index: index,
            removedMissingFiles: reconciled.missingFiles,
            pendingDownloadKeys: reconciled.pendingDownloadKeys.union(discovered.pendingDownloadKeys),
            discoveredFileCount: discovered.discoveredFileCount
        )
    }

    nonisolated private static func reconcileIndexWithFiles(_ index: inout NoteIndex, storage: VaultStorage) throws -> ReconciledIndexResult {
        var missingFiles: [String] = []
        var pendingDownloadKeys = Set<String>()
        var survivingEntries: [NoteIndexEntry] = []
        var changed = false
        let preservesTemporarilyMissingFiles = storage is ICloudVaultStorage
        var seenFileKeys = Set<String>()
        var seenNoteIds = Set<String>()

        for entry in index.entries {
            guard let url = urlForEntry(entry, storage: storage) else {
                missingFiles.append(entry.fileName)
                changed = true
                continue
            }

            let currentFileKey = fileKey(fileName: entry.fileName, location: entry.location)
            guard seenFileKeys.insert(currentFileKey).inserted else {
                changed = true
                continue
            }

            guard FileManager.default.fileExists(atPath: url.path) else {
                if preservesTemporarilyMissingFiles {
                    pendingDownloadKeys.insert(currentFileKey)
                    if seenNoteIds.insert(entry.noteId).inserted {
                        survivingEntries.append(entry)
                    } else {
                        changed = true
                    }
                    continue
                }
                missingFiles.append(entry.fileName)
                changed = true
                continue
            }

            #if os(iOS)
            // The index is the source of truth for iCloud placeholders. Do not
            // open every note merely to validate it: opening requests a
            // download and defeats on-demand storage.
            if storage is ICloudVaultStorage {
                guard seenNoteIds.insert(entry.noteId).inserted else {
                    changed = true
                    continue
                }
                survivingEntries.append(entry)
                continue
            }
            #endif

            do {
                let mdFile = try storage.loadMarkdownFile(at: url)
                let actualMode: NoteFileMode = mdFile.isEncrypted ? .encrypted : .plain
                guard seenNoteIds.insert(mdFile.noteId).inserted else {
                    changed = true
                    continue
                }

                let normalizedEntry = NoteIndexEntry(
                    noteId: mdFile.noteId,
                    fileName: entry.fileName,
                    mode: actualMode,
                    location: entry.location,
                    deletedAt: entry.deletedAt,
                    purgeAfter: entry.purgeAfter,
                    originalLocation: entry.originalLocation
                )
                survivingEntries.append(normalizedEntry)
                if mdFile.noteId != entry.noteId || actualMode != entry.mode {
                    changed = true
                }
            } catch StorageError.iCloudDownloadPending {
                pendingDownloadKeys.insert(currentFileKey)
                if seenNoteIds.insert(entry.noteId).inserted {
                    survivingEntries.append(entry)
                } else {
                    changed = true
                }
                continue
            } catch {
                if preservesTemporarilyMissingFiles {
                    pendingDownloadKeys.insert(currentFileKey)
                    if seenNoteIds.insert(entry.noteId).inserted {
                        survivingEntries.append(entry)
                    } else {
                        changed = true
                    }
                    continue
                }
                missingFiles.append(entry.fileName)
                changed = true
                continue
            }
        }

        index.entries = survivingEntries
        return ReconciledIndexResult(
            missingFiles: missingFiles,
            pendingDownloadKeys: pendingDownloadKeys,
            changed: changed
        )
    }

    nonisolated private static func discoverUnindexedMarkdownFiles(
        in index: inout NoteIndex,
        storage: VaultStorage
    ) throws -> DiscoveredIndexResult {
        var entriesById = Dictionary(uniqueKeysWithValues: index.entries.map { ($0.noteId, $0) })
        var indexedFileKeys = Set(index.entries.map { fileKey(fileName: $0.fileName, location: $0.location) })
        var discoveredFileCount = 0
        var pendingDownloadKeys = Set<String>()
        var changed = false

        for location in [NoteFileLocation.notes, .trash] {
            let urls = try storage.listMarkdownFiles(in: location)
            for url in urls {
                let currentFileKey = fileKey(fileName: url.lastPathComponent, location: location)
                guard !indexedFileKeys.contains(currentFileKey) else { continue }

                let mdFile: MarkdownNoteFile
                do {
                    mdFile = try storage.loadMarkdownFile(at: url)
                } catch StorageError.iCloudDownloadPending {
                    pendingDownloadKeys.insert(currentFileKey)
                    continue
                } catch {
                    MaintenanceLogStore.shared.record("unindexed_markdown_file_skipped", fields: [
                        "file": url.lastPathComponent,
                        "location": location.rawValue,
                        "error": error.localizedDescription
                    ])
                    continue
                }

                if let existingEntry = entriesById[mdFile.noteId] {
                    guard let existingURL = urlForEntry(existingEntry, storage: storage),
                          !FileManager.default.fileExists(atPath: existingURL.path) else {
                        MaintenanceLogStore.shared.record("duplicate_note_file_skipped", fields: [
                            "note_id": mdFile.noteId,
                            "file": url.lastPathComponent,
                            "location": location.rawValue
                        ])
                        continue
                    }
                }

                let entry = discoveredIndexEntry(
                    fileName: url.lastPathComponent,
                    location: location,
                    mdFile: mdFile
                )
                index.upsert(entry)
                entriesById[entry.noteId] = entry
                indexedFileKeys.insert(currentFileKey)
                discoveredFileCount += 1
                changed = true
            }
        }

        return DiscoveredIndexResult(
            discoveredFileCount: discoveredFileCount,
            pendingDownloadKeys: pendingDownloadKeys,
            changed: changed
        )
    }

    nonisolated private static func fileKey(fileName: String, location: NoteFileLocation) -> String {
        "\(location.rawValue)/\(fileName)"
    }

    nonisolated private static func discoveredIndexEntry(
        fileName: String,
        location: NoteFileLocation,
        mdFile: MarkdownNoteFile
    ) -> NoteIndexEntry {
        let mode: NoteFileMode = mdFile.isEncrypted ? .encrypted : .plain
        if location == .trash {
            let deletedAt = mdFile.updatedAt
            return NoteIndexEntry(
                noteId: mdFile.noteId,
                fileName: fileName,
                mode: mode,
                location: location,
                deletedAt: deletedAt,
                purgeAfter: deletedAt.addingTimeInterval(30 * 86400),
                originalLocation: .notes
            )
        }

        return NoteIndexEntry(
            noteId: mdFile.noteId,
            fileName: fileName,
            mode: mode,
            location: location
        )
    }

    private func reportMissingIndexedFiles(_ fileNames: [String]) {
        guard !fileNames.isEmpty else { return }
        let preview = fileNames.prefix(3).joined(separator: "、")
        let suffix = fileNames.count > 3 ? " 等 \(fileNames.count) 条" : ""
        lastError = "有笔记文件找不到，相关记录已自动移除：\(preview)\(suffix)"
        MaintenanceLogStore.shared.record("indexed_note_files_missing", fields: [
            "count": fileNames.count,
            "files": fileNames
        ])
    }

    private func recordPendingDownloads(_ count: Int) {
        guard count > 0 else { return }
        MaintenanceLogStore.shared.record("icloud_note_downloads_pending", fields: [
            "count": count
        ])
    }

    private func handlePendingDownloads(_ count: Int) {
        #if os(iOS)
        if isUsingICloudStorage {
            // iOS presents index entries immediately and downloads note bodies
            // only when opened. A missing/local-placeholder body is not an
            // active sync job and must not start a refresh timer.
            pendingDownloadCount = 0
            pendingDownloadRetryTask?.cancel()
            pendingDownloadRetryTask = nil
            SyncStatusStore.shared.setSaved()
            return
        }
        #endif
        pendingDownloadCount = count
        if count > 0 {
            recordPendingDownloads(count)
            SyncStatusStore.shared.setPendingDownloads(count: count)
            schedulePendingDownloadRetry()
        } else {
            pendingDownloadRetryTask?.cancel()
            pendingDownloadRetryTask = nil
            SyncStatusStore.shared.setSaved()
        }
    }

    private func schedulePendingDownloadRetry() {
        guard isUsingICloudStorage else { return }
        guard pendingDownloadRetryTask == nil else { return }
        pendingDownloadRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.pendingDownloadRetryTask = nil
            }
            await self?.refreshFromStorage()
        }
    }

    @discardableResult
    private func loadAllNotes() async -> Set<String> {
        do {
            let loadedKey: CryptoKit.SymmetricKey?
            #if os(macOS)
            loadedKey = nil
            #else
            if let vId = vaultId,
               let keyMaterial = try? keyStore.loadKey(forVaultId: vId),
               let key = try? keyManager.keyFromBase64(keyMaterial) {
                loadedKey = key
            } else {
                loadedKey = nil
            }
            #endif

            #if os(macOS)
            let preferredMode: NoteFileMode = .plain
            #else
            let preferredMode = settings.preferredNoteMode
            #endif
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
            #if os(iOS)
            cloudOnlyPlainNoteIDs = snapshot.cloudOnlyPlainNoteIDs
            #endif
            state = .ready
            MaintenanceLogStore.shared.record("vault_loaded", fields: [
                "plain": plainNotes.count,
                "decrypted": decryptedNotes.count,
                "locked": lockedEncryptedNotes.count,
                "trash": trashNotes.count,
                "pending_downloads": snapshot.pendingDownloadKeys.count,
                "index_entries": noteIndex.entries.count,
                "storage": isUsingICloudStorage ? "icloud" : "local",
                "container": storage.containerURL?.path
            ])
            return snapshot.pendingDownloadKeys
        } catch {
            state = .error(message: error.localizedDescription)
            MaintenanceLogStore.shared.record("vault_load_failed", fields: [
                "error": error.localizedDescription
            ])
            return []
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
        let updatedIndex = index
        var pendingDownloadKeys = Set<String>()
        #if os(iOS)
        var cloudOnlyPlainNoteIDs = Set<String>()
        #endif

        for entry in index.entries {
            guard let url = urlForEntry(entry, storage: storage) else { continue }
            let currentFileKey = fileKey(fileName: entry.fileName, location: entry.location)

            #if os(iOS)
            if let iCloudStorage = storage as? ICloudVaultStorage,
               (!FileManager.default.fileExists(atPath: url.path) || !iCloudStorage.isItemDownloaded(at: url)) {
                let dates = cloudPlaceholderDates(for: url)
                if entry.location == .notes, entry.mode == .plain {
                    plainNotes.append(Note(
                        id: entry.noteId,
                        body: "",
                        createdAt: dates.createdAt,
                        updatedAt: dates.updatedAt,
                        isEncrypted: false
                    ))
                    cloudOnlyPlainNoteIDs.insert(entry.noteId)
                } else if entry.location == .notes {
                    lockedEncryptedNotes.append(EncryptedNoteInfo(
                        id: entry.noteId,
                        url: url,
                        title: NoteTitleFormatter.displayTitle(fromFileName: entry.fileName, emptyTitle: "加密笔记"),
                        ciphertextPreview: "",
                        fileSize: 0,
                        createdAt: dates.createdAt,
                        updatedAt: dates.updatedAt
                    ))
                }
                continue
            }
            #endif

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
                                title: title(for: entry, mdFile: mdFile),
                                ciphertextPreview: String(mdFile.body.prefix(50)),
                                fileSize: size,
                                createdAt: mdFile.createdAt,
                                updatedAt: mdFile.updatedAt
                            ))
                        }
                    } else {
                        lockedEncryptedNotes.append(EncryptedNoteInfo(
                            id: mdFile.noteId,
                            url: url,
                            title: title(for: entry, mdFile: mdFile),
                            ciphertextPreview: String(mdFile.body.prefix(50)),
                            fileSize: size,
                            createdAt: mdFile.createdAt,
                            updatedAt: mdFile.updatedAt
                        ))
                    }
                }
            } catch StorageError.iCloudDownloadPending {
                pendingDownloadKeys.insert(currentFileKey)
                continue
            } catch {
                continue
            }
        }

        plainNotes.sort { $0.updatedAt > $1.updatedAt }
        decryptedNotes.sort { $0.updatedAt > $1.updatedAt }
        trashNotes.sort { $0.deletedAt > $1.deletedAt }

        #if os(iOS)
        return LoadedNotesSnapshot(
            currentKey: currentKey,
            resetPreferredModeToPlain: resetPreferredModeToPlain,
            plainNotes: plainNotes,
            decryptedNotes: decryptedNotes,
            lockedEncryptedNotes: lockedEncryptedNotes,
            trashNotes: trashNotes,
            noteIndex: updatedIndex,
            pendingDownloadKeys: pendingDownloadKeys,
            cloudOnlyPlainNoteIDs: cloudOnlyPlainNoteIDs
        )
        #else
        return LoadedNotesSnapshot(
            currentKey: currentKey,
            resetPreferredModeToPlain: resetPreferredModeToPlain,
            plainNotes: plainNotes,
            decryptedNotes: decryptedNotes,
            lockedEncryptedNotes: lockedEncryptedNotes,
            trashNotes: trashNotes,
            noteIndex: updatedIndex,
            pendingDownloadKeys: pendingDownloadKeys
        )
        #endif
    }

    #if os(iOS)
    nonisolated private static func cloudPlaceholderDates(for url: URL) -> (createdAt: Date, updatedAt: Date) {
        let keys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey]
        let values = try? url.resourceValues(forKeys: keys)
        let updatedAt = values?.contentModificationDate ?? values?.creationDate ?? .distantPast
        return (values?.creationDate ?? updatedAt, updatedAt)
    }
    #endif

    nonisolated private static func urlForEntry(_ entry: NoteIndexEntry, storage: VaultStorage) -> URL? {
        guard let container = storage.containerURL else { return nil }
        return entry.location == .notes
            ? container.appendingPathComponent(entry.fileName)
            : container.appendingPathComponent(entry.location.rawValue).appendingPathComponent(entry.fileName)
    }

    nonisolated private static func urlForFileName(_ fileName: String, location: NoteFileLocation = .notes, storage: VaultStorage) -> URL? {
        guard let container = storage.containerURL else { return nil }
        return location == .notes
            ? container.appendingPathComponent(fileName)
            : container.appendingPathComponent(location.rawValue).appendingPathComponent(fileName)
    }

    // MARK: - Storage-root pinning (P0-3)

    /// Decide which storage root to use, honoring the user's pin so the vault never
    /// silently forks between iCloud and local. Pure given `iCloudAvailable`.
    /// - Returns: the storage to use, the pin to persist, and whether we fell back to
    ///   local against an iCloud pin (a mismatch the UI should surface).
    nonisolated static func resolveStorage(pinned: String?, iCloudAvailable: Bool)
        -> (storage: VaultStorage, pin: String, mismatch: Bool) {
        switch pinned {
        case "local":
            // User pinned local; iCloud reappearing must not auto-switch.
            return (LocalFallbackStorage.shared, "local", false)
        case "icloud":
            if iCloudAvailable {
                return (ICloudVaultStorage.shared, "icloud", false)
            }
            // Pinned to iCloud but unavailable this launch: read/write local as a
            // temporary fallback WITHOUT changing the pin, and flag the mismatch.
            return (LocalFallbackStorage.shared, "icloud", true)
        default:
            // No pin yet: pick and pin.
            return iCloudAvailable
                ? (ICloudVaultStorage.shared, "icloud", false)
                : (LocalFallbackStorage.shared, "local", false)
        }
    }

    /// Whether a vault root already holds note data — used to detect notes stranded in
    /// a local fallback vault while the app is otherwise on iCloud.
    nonisolated static func hasVaultData(at rootURL: URL) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: rootURL.appendingPathComponent("notes.json").path) { return true }
        if let rootFiles = try? fm.contentsOfDirectory(atPath: rootURL.path),
           rootFiles.contains(where: { $0.hasSuffix(".md") }) {
            return true
        }
        let trash = rootURL.appendingPathComponent("trash")
        if let trashFiles = try? fm.contentsOfDirectory(atPath: trash.path),
           trashFiles.contains(where: { $0.hasSuffix(".md") }) {
            return true
        }
        return false
    }

    /// Move notes from `source` into `dest`, copy-verify-then-delete. A note whose id
    /// already exists in `dest` is imported as a fresh note titled "…（本机副本）"; a
    /// unique note keeps its id. Local originals are removed only after a verified
    /// read-back. Operates on two `VaultStorage` instances so it is directly testable.
    nonisolated static func mergeVaultData(from source: VaultStorage, into dest: VaultStorage) throws -> (merged: Int, conflicted: Int) {
        guard dest.containerURL != nil else { throw StorageError.iCloudUnavailable }
        var destIndex = (try? dest.loadIndex()) ?? NoteIndex()
        var sourceIndex = (try? source.loadIndex()) ?? NoteIndex()
        var merged = 0
        var conflicted = 0

        for entry in sourceIndex.entries where entry.location == .notes {
            guard let srcURL = urlForEntry(entry, storage: source),
                  let mdFile = try? source.loadMarkdownFile(at: srcURL) else { continue }

            let collision = destIndex.entry(for: entry.noteId) != nil
            let destNoteId = collision ? UUID().uuidString : entry.noteId
            let destFileName = collision ? "\(destNoteId).md" : entry.fileName
            let destTitle: String?
            if collision {
                let base = mdFile.title ?? NoteTitleFormatter.displayTitle(fromFileName: entry.fileName, emptyTitle: "")
                destTitle = base.isEmpty ? "（本机副本）" : "\(base)（本机副本）"
            } else {
                destTitle = mdFile.title
            }
            guard let destURL = urlForFileName(destFileName, storage: dest) else { continue }

            let destFile = MarkdownNoteFile(
                noteId: destNoteId,
                createdAt: mdFile.createdAt,
                updatedAt: mdFile.updatedAt,
                title: destTitle,
                body: mdFile.body
            )
            do {
                try dest.saveMarkdownFile(destFile, at: destURL)
                let readBack = try dest.loadMarkdownFile(at: destURL)
                guard readBack.body == mdFile.body else { continue }   // verify before delete
            } catch {
                continue
            }
            destIndex.upsert(NoteIndexEntry(noteId: destNoteId, fileName: destFileName, mode: entry.mode, location: .notes))
            try? source.permanentlyDeleteFile(at: srcURL)
            sourceIndex.removeEntry(for: entry.noteId)

            if collision { conflicted += 1 } else { merged += 1 }
        }
        try? dest.saveIndex(destIndex)
        try? source.saveIndex(sourceIndex)
        return (merged, conflicted)
    }

    #if os(iOS)
    /// User-initiated: merge notes that were stranded in the local fallback vault
    /// (written while iCloud was signed out) into the active iCloud vault.
    @discardableResult
    func mergeLocalDataIntoICloud() async throws -> (merged: Int, conflicted: Int) {
        guard let iCloud = storage as? ICloudVaultStorage else { throw StorageError.iCloudUnavailable }
        let result = try await Task.detached(priority: .userInitiated) {
            try Self.mergeVaultData(from: LocalFallbackStorage.shared, into: iCloud)
        }.value
        strandedLocalDataDetected = false
        await reloadAllNotes()
        return result
    }

    /// Dismiss the stranded-data prompt for this launch. The data is re-detected on the
    /// next launch while it still exists, so the user is reminded until they merge.
    func dismissStrandedDataPrompt() {
        strandedLocalDataDetected = false
    }
    #endif

    nonisolated private static func uniqueFileName(
        for body: String,
        location: NoteFileLocation = .notes,
        storage: VaultStorage,
        currentFileName: String? = nil
    ) -> String {
        let title = NoteTitleFormatter.displayTitle(from: body)
        return uniqueFileName(
            forTitle: title,
            location: location,
            storage: storage,
            currentFileName: currentFileName,
            limitsLength: !NoteTitleFormatter.firstNonEmptyLineIsMarkdownHeading(in: body)
        )
    }

    nonisolated private static func uniqueFileName(
        forTitle title: String,
        location: NoteFileLocation = .notes,
        storage: VaultStorage,
        currentFileName: String? = nil,
        limitsLength: Bool = true
    ) -> String {
        let baseName = NoteTitleFormatter.fileBaseName(forTitle: title, limitsLength: limitsLength)
        let fm = FileManager.default
        var suffix = 1

        while true {
            let fileName = suffix == 1 ? "\(baseName).md" : "\(baseName)（\(suffix)）.md"
            if fileName == currentFileName {
                return fileName
            }

            guard let url = urlForFileName(fileName, location: location, storage: storage) else {
                return fileName
            }

            if !fm.fileExists(atPath: url.path) {
                return fileName
            }

            suffix += 1
        }
    }

    nonisolated private static func title(for entry: NoteIndexEntry, mdFile: MarkdownNoteFile) -> String {
        if entry.location == .notes {
            return NoteTitleFormatter.displayTitle(fromFileName: entry.fileName, emptyTitle: "加密笔记")
        }

        if let title = mdFile.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return NoteTitleFormatter.displayTitle(fromFileName: entry.fileName, emptyTitle: "加密笔记")
    }

    nonisolated private static func title(for body: String) -> String? {
        let title = NoteTitleFormatter.displayTitle(from: body, emptyTitle: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    nonisolated private static func stableExistingTitle(for entry: NoteIndexEntry, mdFile: MarkdownNoteFile?) -> String? {
        if let title = mdFile?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty,
           title != NoteTitleFormatter.emptyTitle {
            return title
        }

        let fileTitle = NoteTitleFormatter.displayTitle(fromFileName: entry.fileName, emptyTitle: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !fileTitle.isEmpty, fileTitle != NoteTitleFormatter.emptyTitle {
            return fileTitle
        }

        return nil
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
            title: title(for: entry, mdFile: mdFile),
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
            ("欢迎使用Seal Note。\n\n你可以像写卡片一样记录想法，也可以在需要时创建加密笔记。\n\n#欢迎", now),
            ("标签写法示例：\n\n在正文中输入 #灵感 或 #日记 ，它们会出现在侧边栏的标签区域。\n\n#使用说明 #标签", now.addingTimeInterval(-1)),
            ("加密笔记适合保存更私密的内容。\n\n首次创建笔记时，你可以选择创建密钥。创建密钥后，新建笔记时可以打开\"加密笔记\"开关。\n\n#加密", now.addingTimeInterval(-2))
        ]

        for (body, date) in defaults {
            let noteId = UUID().uuidString
            let mdFile = MarkdownNoteFile(
                noteId: noteId,
                createdAt: date,
                updatedAt: date,
                title: Self.title(for: body),
                body: body
            )
            let fileName = Self.uniqueFileName(for: body, storage: storage)
            if let url = Self.urlForFileName(fileName, storage: storage) {
                try? storage.saveMarkdownFile(mdFile, at: url)
                noteIndex.upsert(NoteIndexEntry(
                    noteId: noteId,
                    fileName: fileName,
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

    private func currentEncryptionKey() throws -> CryptoKit.SymmetricKey {
        #if DEBUG
        if let currentKey {
            return currentKey
        }
        #endif
        #if os(macOS)
        return try loadConfiguredKeyFile()
        #else
        if let currentKey {
            return currentKey
        }
        do {
            let key = try loadStoredIOSKey()
            currentKey = key
            return key
        } catch KeychainError.notFound {
            throw VaultError.keyNotLoaded
        }
        #endif
    }

    #if os(macOS)
    /// Loads encrypted note bodies for an authorized CLI request without changing
    /// the UI's locked/decrypted note state.
    func encryptedNotesForCLI() throws -> [Note] {
        let key = try currentEncryptionKey()
        return try noteIndex.entries.compactMap { entry in
            guard entry.mode == .encrypted, entry.location == .notes else {
                return nil
            }
            guard let url = Self.urlForEntry(entry, storage: storage) else {
                throw StorageError.fileNotFound
            }
            let file = try storage.loadMarkdownFile(at: url)
            let body = try cryptoService.decryptMarkdownBody(file.body, using: key)
            return Note(
                id: entry.noteId,
                body: body,
                createdAt: file.createdAt,
                updatedAt: file.updatedAt,
                isEncrypted: true
            )
        }
    }
    #endif

    #if os(macOS)
    private func loadConfiguredKeyFile() throws -> CryptoKit.SymmetricKey {
        guard let reference = settings.vaultKeyFileReference else {
            throw CryptoError.keyNotFound
        }
        let resolved = try settings.resolveVaultKeyFileURL()
        guard Self.normalizedPath(resolved.url) == Self.normalizedPath(URL(fileURLWithPath: reference.displayPath)) else {
            throw VaultKeyFileError.fileMoved
        }
        if resolved.isStale {
            throw VaultKeyFileError.fileMoved
        }
        let loaded = try loadKey(from: resolved.url)
        if let expectedKeyId = reference.keyId, expectedKeyId != loaded.vaultKey.keyId {
            throw VaultKeyFileError.keyReplaced
        }
        if let expectedFingerprint = reference.keyFingerprint, expectedFingerprint != loaded.fingerprint {
            throw VaultKeyFileError.keyReplaced
        }
        try validateKeyAgainstExistingEncryptedNote(loaded.key)
        if reference.keyId == nil || reference.keyFingerprint == nil {
            try settings.saveVaultKeyFileReference(
                for: resolved.url,
                keyId: loaded.vaultKey.keyId,
                keyFingerprint: loaded.fingerprint
            )
        }
        return loaded.key
    }

    private struct LoadedKeyFile {
        let vaultKey: VaultKey
        let key: CryptoKit.SymmetricKey
        let fingerprint: String
    }

    private func loadKey(from url: URL) throws -> LoadedKeyFile {
        try validateKeyFileExtension(url)
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VaultKeyFileError.fileMissing
        }
        try requestICloudKeyDownloadIfNeeded(at: url)

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw VaultKeyFileError.permissionDenied
        }

        let vaultKey: VaultKey
        do {
            vaultKey = try JSONDecoder.default.decode(VaultKey.self, from: data)
        } catch {
            throw VaultKeyFileError.invalidFile
        }

        guard keyManager.validateVaultKey(vaultKey) else {
            throw VaultKeyFileError.invalidFile
        }

        do {
            return LoadedKeyFile(
                vaultKey: vaultKey,
                key: try keyManager.extractKey(vaultKey),
                fingerprint: try keyManager.keyFingerprint(vaultKey)
            )
        } catch {
            throw VaultKeyFileError.invalidFile
        }
    }

    nonisolated private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func validateKeyFileExtension(_ url: URL) throws {
        guard url.pathExtension.lowercased() == "snkey" else {
            throw VaultKeyFileError.unsupportedFileExtension
        }
    }

    private func requestICloudKeyDownloadIfNeeded(at url: URL) throws {
        let resourceKeys: Set<URLResourceKey> = [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        guard let values = try? url.resourceValues(forKeys: resourceKeys),
              values.isUbiquitousItem == true else {
            return
        }

        let status = values.ubiquitousItemDownloadingStatus
        if status == .current || status == .downloaded {
            return
        }

        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            MaintenanceLogStore.shared.record("vault_key_icloud_download_requested", fields: [
                "file": url.lastPathComponent
            ])
        } catch {
            MaintenanceLogStore.shared.record("vault_key_icloud_download_request_failed", fields: [
                "file": url.lastPathComponent,
                "error": error.localizedDescription
            ])
        }

        throw VaultKeyFileError.keyDownloadPending
    }

    private func validateKeyAgainstExistingEncryptedNote(_ key: CryptoKit.SymmetricKey) throws {
        for entry in noteIndex.entries where entry.mode == .encrypted {
            guard let url = Self.urlForEntry(entry, storage: storage),
                  FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            let mdFile = try storage.loadMarkdownFile(at: url)
            do {
                _ = try cryptoService.decryptMarkdownBody(mdFile.body, using: key)
            } catch {
                throw VaultKeyFileError.keyMismatch
            }
            return
        }
    }

    func createKeyFile(at url: URL) async throws {
        guard settings.vaultKeyFileReference == nil else {
            throw VaultKeyFileError.keyAlreadyConfigured
        }
        guard !hasEncryptedEntries else {
            throw VaultKeyFileError.encryptedNotesExist
        }
        try validateKeyFileExtension(url)

        let key = keyManager.generateKey()
        let vaultKey = keyManager.generateVaultKey(key: key)
        let data = try JSONEncoder.default.encode(vaultKey)
        try data.write(to: url, options: .atomic)
        try settings.saveVaultKeyFileReference(
            for: url,
            keyId: vaultKey.keyId,
            keyFingerprint: keyManager.keyFingerprint(vaultKey)
        )
        currentKey = nil
        await reloadAllNotes(keyReloadMode: .explicit(nil))
        settings.preferredNoteMode = .encrypted
    }
    #endif

    func openEncryptedNote(_ info: EncryptedNoteInfo) async throws -> Note {
        let key = try currentEncryptionKey()
        let url = info.url
        let mdFile = try await fileIO.perform { [storage] in try storage.loadMarkdownFile(at: url) }
        let decryptedBody: String
        do {
            decryptedBody = try cryptoService.decryptMarkdownBody(mdFile.body, using: key)
        } catch {
            throw VaultKeyFileError.keyMismatch
        }

        let note = Note(
            id: mdFile.noteId,
            body: decryptedBody,
            createdAt: mdFile.createdAt,
            updatedAt: mdFile.updatedAt,
            isEncrypted: true
        )
        lockedEncryptedNotes.removeAll { $0.id == info.id }
        if let index = decryptedNotes.firstIndex(where: { $0.id == note.id }) {
            decryptedNotes[index] = note
        } else {
            decryptedNotes.insert(note, at: 0)
        }
        return note
    }

    @discardableResult
    func decryptNotePermanently(_ note: Note) async throws -> Note {
        guard let entry = noteIndex.entry(for: note.id),
              entry.mode == .encrypted,
              let url = Self.urlForEntry(entry, storage: storage) else {
            throw StorageError.fileNotFound
        }

        let key = try currentEncryptionKey()
        let mdFile = try storage.loadMarkdownFile(at: url)
        let decryptedBody: String
        do {
            decryptedBody = try cryptoService.decryptMarkdownBody(mdFile.body, using: key)
        } catch {
            throw VaultKeyFileError.keyMismatch
        }

        return try await saveReadableNote(
            Note(
                id: mdFile.noteId,
                body: decryptedBody,
                createdAt: mdFile.createdAt,
                updatedAt: mdFile.updatedAt,
                isEncrypted: true
            ),
            body: decryptedBody,
            mode: .plain,
            sourceUpdatedAt: note.updatedAt
        ).note
    }

    func permanentlyDeleteAllEncryptedNotes() async throws -> Int {
        let encryptedEntries = noteIndex.entries.filter { $0.mode == .encrypted }
        for entry in encryptedEntries {
            if let url = Self.urlForEntry(entry, storage: storage) {
                try? storage.permanentlyDeleteFile(at: url)
            }
            noteIndex.removeEntry(for: entry.noteId)
        }
        try storage.saveIndex(noteIndex)
        try clearLoadedKeyReference()
        decryptedNotes.removeAll()
        lockedEncryptedNotes.removeAll()
        await reloadAllNotes(keyReloadMode: .explicit(nil))
        settings.preferredNoteMode = .plain
        return encryptedEntries.count
    }

    func decryptAllEncryptedNotesAndRemoveKey() async throws -> Int {
        let decrypted = try preflightDecryptAllEncryptedNotes()
        for item in decrypted {
            try convertEncryptedEntryToPlain(item.entry, mdFile: item.mdFile, decryptedBody: item.body)
        }
        try storage.saveIndex(noteIndex)
        try clearLoadedKeyReference()
        await reloadAllNotes(keyReloadMode: .explicit(nil))
        settings.preferredNoteMode = .plain
        return decrypted.count
    }

    func exportPlaintextEncryptedNotesAndRemoveLocalNotes(to destinationURL: URL? = nil) async throws -> (url: URL, exportedCount: Int) {
        let decrypted = try preflightDecryptAllEncryptedNotes()
        let export = try exportPlaintextNotes(decrypted, to: destinationURL)

        for item in decrypted {
            if let url = Self.urlForEntry(item.entry, storage: storage) {
                try? storage.permanentlyDeleteFile(at: url)
            }
            noteIndex.removeEntry(for: item.entry.noteId)
        }
        try storage.saveIndex(noteIndex)
        try clearLoadedKeyReference()
        await reloadAllNotes(keyReloadMode: .explicit(nil))
        settings.preferredNoteMode = .plain
        return export
    }

    private struct DecryptedEncryptedNote {
        let entry: NoteIndexEntry
        let mdFile: MarkdownNoteFile
        let body: String
    }

    private func preflightDecryptAllEncryptedNotes() throws -> [DecryptedEncryptedNote] {
        let key = try currentEncryptionKey()
        var decrypted: [DecryptedEncryptedNote] = []
        for entry in noteIndex.entries where entry.mode == .encrypted {
            guard let url = Self.urlForEntry(entry, storage: storage) else { continue }
            let mdFile = try storage.loadMarkdownFile(at: url)
            let body: String
            do {
                body = try cryptoService.decryptMarkdownBody(mdFile.body, using: key)
            } catch {
                throw VaultKeyFileError.keyMismatch
            }
            decrypted.append(DecryptedEncryptedNote(entry: entry, mdFile: mdFile, body: body))
        }
        return decrypted
    }

    private func convertEncryptedEntryToPlain(_ entry: NoteIndexEntry, mdFile: MarkdownNoteFile, decryptedBody: String) throws {
        guard let currentURL = Self.urlForEntry(entry, storage: storage) else {
            throw StorageError.fileNotFound
        }
        let newFileName = Self.uniqueFileName(
            for: decryptedBody,
            location: entry.location,
            storage: storage,
            currentFileName: entry.fileName
        )
        guard let targetURL = Self.urlForFileName(newFileName, location: entry.location, storage: storage) else {
            throw StorageError.iCloudUnavailable
        }

        let plainFile = MarkdownNoteFile(
            noteId: mdFile.noteId,
            createdAt: mdFile.createdAt,
            updatedAt: Date(),
            title: Self.title(for: decryptedBody),
            body: decryptedBody
        )
        try storage.saveMarkdownFile(plainFile, at: targetURL)
        if currentURL != targetURL && FileManager.default.fileExists(atPath: currentURL.path) {
            try? storage.permanentlyDeleteFile(at: currentURL)
        }
        noteIndex.upsert(NoteIndexEntry(
            noteId: entry.noteId,
            fileName: newFileName,
            mode: .plain,
            location: entry.location,
            deletedAt: entry.deletedAt,
            purgeAfter: entry.purgeAfter,
            originalLocation: entry.originalLocation
        ))
    }

    private func exportPlaintextNotes(_ notes: [DecryptedEncryptedNote], to destinationURL: URL? = nil) throws -> (url: URL, exportedCount: Int) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Seal Note-解密笔记-\(dateStr)-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        for (index, item) in notes.enumerated() {
            let safeIndex = String(format: "%03d", index + 1)
            let fileName = "\(safeIndex)-\(NoteTitleFormatter.fileName(for: item.body))"
            let fileURL = tmpDir.appendingPathComponent(fileName)
            let mdFile = MarkdownNoteFile(
                noteId: item.mdFile.noteId,
                createdAt: item.mdFile.createdAt,
                updatedAt: item.mdFile.updatedAt,
                title: Self.title(for: item.body),
                body: item.body
            )
            try mdFile.render().write(to: fileURL, options: .atomic)
        }

        let zipURL = destinationURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("Seal Note-解密笔记-\(dateStr).zip")
        try? FileManager.default.removeItem(at: zipURL)
        try ZipUtility.createZip(from: tmpDir, to: zipURL)
        try? FileManager.default.removeItem(at: tmpDir)
        return (zipURL, notes.count)
    }

    private func clearLoadedKeyReference() throws {
        #if os(macOS)
        settings.clearVaultKeyFileReference()
        currentKey = nil
        #else
        if let vId = vaultId {
            try keyStore.deleteKey(forVaultId: vId)
        }
        currentKey = nil
        #endif
    }

    func createKey() async throws {
        #if os(macOS)
        throw CryptoError.keyNotFound
        #else
        guard !hasEncryptedEntries else {
            throw VaultKeyFileError.encryptedNotesExist
        }
        guard let vId = vaultId else { throw VaultError.notReady }

        let key = keyManager.generateKey()
        let vaultKey = keyManager.generateVaultKey(key: key)
        try keyStore.saveKey(
            vaultKey.keyMaterial,
            forVaultId: vId,
            keyId: vaultKey.keyId,
            keyFingerprint: try keyManager.keyFingerprint(vaultKey)
        )
        currentKey = key

        await reloadAllNotes(keyReloadMode: .explicit(key))

        needsKeyExport = true
        settings.preferredNoteMode = .encrypted
        #endif
    }

    func importKeyFile(from url: URL) async throws -> Bool {
        #if os(macOS)
        let loaded = try loadKey(from: url)
        try validateKeyAgainstExistingEncryptedNote(loaded.key)
        try settings.saveVaultKeyFileReference(
            for: url,
            keyId: loaded.vaultKey.keyId,
            keyFingerprint: loaded.fingerprint
        )
        currentKey = nil
        await reloadAllNotes(keyReloadMode: .explicit(nil))
        settings.preferredNoteMode = .encrypted
        return true
        #else
        guard let vId = vaultId else { throw VaultError.notReady }
        guard url.pathExtension.lowercased() == "snkey" else {
            throw VaultKeyFileError.unsupportedFileExtension
        }

        let hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        try requestSelectedKeyDownloadIfNeeded(at: url)

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw VaultKeyFileError.permissionDenied
        }

        let vaultKey: VaultKey
        do {
            vaultKey = try JSONDecoder.default.decode(VaultKey.self, from: data)
        } catch {
            throw VaultKeyFileError.invalidFile
        }

        guard keyManager.validateVaultKey(vaultKey) else {
            throw VaultKeyFileError.invalidFile
        }

        let key: CryptoKit.SymmetricKey
        do {
            key = try keyManager.extractKey(vaultKey)
        } catch {
            throw VaultKeyFileError.invalidFile
        }
        try validateIOSKeyAgainstExistingEncryptedNote(key)

        try keyStore.saveKey(
            vaultKey.keyMaterial,
            forVaultId: vId,
            keyId: vaultKey.keyId,
            keyFingerprint: try keyManager.keyFingerprint(vaultKey)
        )
        currentKey = key

        await reloadAllNotes(keyReloadMode: .explicit(key))

        settings.preferredNoteMode = .encrypted
        return true
        #endif
    }

    func unloadKey() async throws {
        #if os(macOS)
        guard !hasEncryptedEntries else {
            throw VaultKeyFileError.encryptedNotesExist
        }
        settings.clearVaultKeyFileReference()
        currentKey = nil
        decryptedNotes = []
        await reloadAllNotes(keyReloadMode: .explicit(nil))
        settings.preferredNoteMode = .plain
        if let tag = selectedTag, !allTags.contains(where: { $0.tag == tag }) {
            selectedTag = nil
        }
        #else
        guard !hasEncryptedEntries else {
            throw VaultKeyFileError.encryptedNotesExist
        }
        guard let vId = vaultId else { return }
        try keyStore.deleteKey(forVaultId: vId)
        currentKey = nil
        decryptedNotes = []

        await reloadAllNotes(keyReloadMode: .explicit(nil))
        settings.preferredNoteMode = .plain

        if let tag = selectedTag, !allTags.contains(where: { $0.tag == tag }) {
            selectedTag = nil
        }
        #endif
    }

    private var hasEncryptedEntries: Bool {
        noteIndex.entries.contains { $0.mode == .encrypted }
    }

    #if os(iOS)
    /// Non-destructive session lock: forget the in-memory key and re-project encrypted
    /// notes to "locked", leaving the Keychain key intact (P0-4). Reverse of `unlockSession()`.
    func lockSession() async {
        currentKey = nil
        decryptedNotes = []
        await reloadAllNotes(keyReloadMode: .explicit(nil))
    }

    /// Reload the key from the Keychain and decrypt the vault again.
    func unlockSession() async throws {
        let key = try loadStoredIOSKey()
        currentKey = key
        await reloadAllNotes(keyReloadMode: .explicit(key))
    }
    #endif

    #if os(iOS)
    private func loadStoredIOSKey() throws -> CryptoKit.SymmetricKey {
        guard let vId = vaultId else { throw KeychainError.notFound }
        let keyMaterial = try keyStore.loadKey(forVaultId: vId)
        let key = try keyManager.keyFromBase64(keyMaterial)
        let fingerprint = try keyManager.keyMaterialFingerprint(keyMaterial)

        if let storedFingerprint = keyStore.loadKeyFingerprint(forVaultId: vId),
           storedFingerprint != fingerprint {
            throw VaultKeyFileError.keyReplaced
        }

        if keyStore.loadKeyFingerprint(forVaultId: vId) == nil {
            try? keyStore.saveKeyMetadata(
                keyId: keyStore.loadKeyId(forVaultId: vId),
                keyFingerprint: fingerprint,
                forVaultId: vId
            )
        }

        try validateIOSKeyAgainstExistingEncryptedNote(key)
        return key
    }

    private func validateIOSKeyAgainstExistingEncryptedNote(_ key: CryptoKit.SymmetricKey) throws {
        for entry in noteIndex.entries where entry.mode == .encrypted {
            guard let url = Self.urlForEntry(entry, storage: storage),
                  FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            let mdFile = try storage.loadMarkdownFile(at: url)
            do {
                _ = try cryptoService.decryptMarkdownBody(mdFile.body, using: key)
            } catch {
                throw VaultKeyFileError.keyMismatch
            }
            return
        }
    }
    #endif

    /// Whether the Keychain key stored under `candidate` decrypts an existing
    /// encrypted note. Used by `VaultIdentityStore` to validate a legacy vault id
    /// before adopting it. Cross-platform signature; only iOS can validate.
    private func canDecryptExistingEncryptedNote(withCandidate candidate: String) -> Bool {
        #if os(iOS)
        guard let keyMaterial = try? keyStore.loadKey(forVaultId: candidate),
              let key = try? keyManager.keyFromBase64(keyMaterial) else {
            return false
        }
        do {
            try validateIOSKeyAgainstExistingEncryptedNote(key)
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    func resetKey() async throws {
        guard let vId = vaultId else { throw VaultError.notReady }

        try keyStore.deleteKey(forVaultId: vId)

        let encEntries = noteIndex.entries.filter { $0.mode == .encrypted }
        for entry in encEntries {
            if let url = Self.urlForEntry(entry, storage: storage) {
                try? storage.permanentlyDeleteFile(at: url)
            }
            noteIndex.removeEntry(for: entry.noteId)
        }
        try storage.saveIndex(noteIndex)

        let key = keyManager.generateKey()
        let vaultKey = keyManager.generateVaultKey(key: key)
        try keyStore.saveKey(
            vaultKey.keyMaterial,
            forVaultId: vId,
            keyId: vaultKey.keyId,
            keyFingerprint: try keyManager.keyFingerprint(vaultKey)
        )
        currentKey = key

        await reloadAllNotes(keyReloadMode: .explicit(key))

        needsKeyExport = true
        settings.preferredNoteMode = .encrypted
    }

    private func reloadAllNotes(keyReloadMode: KeyReloadMode = .keychain) async {
        do {
            let prepared = try await Task.detached(priority: .userInitiated) { [storage, noteIndex] in
                try await Self.prepareIndex(storage: storage, fallbackIndex: noteIndex, initializeStorage: false)
            }.value
            noteIndex = prepared.index
            reportMissingIndexedFiles(prepared.removedMissingFiles)

            let loadedKey: CryptoKit.SymmetricKey?
            switch keyReloadMode {
            case .keychain:
            #if os(macOS)
            loadedKey = nil
            #else
            loadedKey = try? loadStoredIOSKey()
            #endif
            case .explicit(let key):
                loadedKey = key
            }

            #if os(macOS)
            let preferredMode: NoteFileMode = .plain
            #else
            let preferredMode = settings.preferredNoteMode
            #endif
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
            #if os(iOS)
            cloudOnlyPlainNoteIDs = snapshot.cloudOnlyPlainNoteIDs
            #endif
            handlePendingDownloads(prepared.pendingDownloadKeys.union(snapshot.pendingDownloadKeys).count)
        } catch {
            state = .error(message: error.localizedDescription)
            pendingDownloadRetryTask?.cancel()
            pendingDownloadRetryTask = nil
            pendingDownloadCount = 0
        }
    }

    func refreshFromStorage() async {
        SyncStatusStore.shared.setSyncing()
        #if os(macOS)
        let decryptedNoteIDs = Set(decryptedNotes.map(\.id))
        #endif
        await reloadAllNotes()

        #if os(macOS)
        // A local save also reaches the external-change monitor. Keep notes that
        // are already open in this session decrypted across that disk refresh;
        // otherwise their body (and therefore their tags) disappears moments
        // after a successful save.
        let notesToRestore = lockedEncryptedNotes.filter { decryptedNoteIDs.contains($0.id) }
        for info in notesToRestore {
            do {
                _ = try await openEncryptedNote(info)
            } catch {
                MaintenanceLogStore.shared.record("decrypted_note_restore_failed", fields: [
                    "note_id": info.id,
                    "error": error.localizedDescription
                ])
            }
        }
        #endif

        if case .error(let message) = state {
            SyncStatusStore.shared.setFailed(message: message)
        } else {
            state = .ready
            if pendingDownloadCount > 0 {
                SyncStatusStore.shared.setPendingDownloads(count: pendingDownloadCount)
            } else {
                SyncStatusStore.shared.setSaved()
            }
        }
    }

    func exportKeyFile() throws -> URL {
        let key = try currentEncryptionKey()
        let keyMaterial = keyManager.keyToBase64(key)
        let keyId: String
        #if os(iOS)
        keyId = vaultId.flatMap { keyStore.loadKeyId(forVaultId: $0) } ?? UUID().uuidString
        #else
        keyId = settings.vaultKeyFileReference?.keyId ?? UUID().uuidString
        #endif
        let vaultKey = VaultKey(
            version: 2,
            app: VaultKey.appName,
            type: "vault_key",
            keyId: keyId,
            algorithm: VaultKey.algorithmAES256,
            createdAt: Date(),
            keyMaterial: keyMaterial
        )
        let data = try JSONEncoder.default.encode(vaultKey)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Seal Note-密钥-\(dateStr).snkey")
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
            let key = try currentEncryptionKey()
            finalBody = try cryptoService.encryptMarkdownBody(body, using: key)
        } else {
            finalBody = body
        }

        let mdFile = MarkdownNoteFile(
            noteId: noteId,
            createdAt: now,
            updatedAt: now,
            title: Self.title(for: body),
            body: finalBody
        )

        let fileName = Self.uniqueFileName(for: body, storage: storage)
        guard let url = Self.urlForFileName(fileName, storage: storage) else {
            throw StorageError.iCloudUnavailable
        }
        try storage.saveMarkdownFile(mdFile, at: url)

        let entry = NoteIndexEntry(
            noteId: noteId,
            fileName: fileName,
            mode: isEncrypted ? .encrypted : .plain,
            location: .notes
        )
        noteIndex.upsert(entry)
        try storage.saveIndex(noteIndex)
        MaintenanceLogStore.shared.record("note_created", fields: [
            "note_id": noteId,
            "file": fileName,
            "mode": isEncrypted ? "encrypted" : "plain",
            "body_bytes": body.utf8.count
        ])

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

    func updateNote(_ note: Note, body: String, renameIfUntitled: Bool = true) async throws {
        guard let _ = vaultId else { throw VaultError.notReady }
        let latestNote = readableNotes.first(where: { $0.id == note.id }) ?? note
        _ = try await saveReadableNote(
            latestNote,
            body: body,
            mode: latestNote.isEncrypted ? .encrypted : .plain,
            sourceUpdatedAt: note.updatedAt,
            renameIfUntitled: renameIfUntitled
        )
    }

    @discardableResult
    func updateNoteMode(_ note: Note, body: String, mode: NoteMode) async throws -> Note {
        guard let _ = vaultId else { throw VaultError.notReady }
        let latestNote = readableNotes.first(where: { $0.id == note.id }) ?? note
        let fileMode: NoteFileMode = mode == .encrypted ? .encrypted : .plain
        return try await saveReadableNote(
            latestNote,
            body: body,
            mode: fileMode,
            sourceUpdatedAt: note.updatedAt
        ).note
    }

    func encryptNoteForEditing(_ note: Note, body: String) async throws -> (note: Note, ciphertext: String) {
        guard let _ = vaultId else { throw VaultError.notReady }
        _ = try currentEncryptionKey()
        let latestNote = readableNotes.first(where: { $0.id == note.id }) ?? note
        return try await saveReadableNote(latestNote, body: body, mode: .encrypted, sourceUpdatedAt: note.updatedAt)
    }

    func decryptEncryptedNoteBody(_ note: Note) async throws -> String {
        let key = try currentEncryptionKey()
        guard let entry = noteIndex.entry(for: note.id),
              entry.mode == .encrypted,
              let url = Self.urlForEntry(entry, storage: storage) else {
            throw StorageError.fileNotFound
        }
        let mdFile = try await fileIO.perform { [storage] in try storage.loadMarkdownFile(at: url) }
        return try cryptoService.decryptMarkdownBody(mdFile.body, using: key)
    }

    private func logicalBody(for file: MarkdownNoteFile, key: CryptoKit.SymmetricKey?) throws -> String {
        guard file.isEncrypted else { return file.body }
        let resolvedKey = try key ?? currentEncryptionKey()
        return try cryptoService.decryptMarkdownBody(file.body, using: resolvedKey)
    }

    // ponytail: single global IO lane; per-note lanes only if profiling demands
    private func saveReadableNote(
        _ note: Note,
        body: String,
        mode: NoteFileMode,
        sourceUpdatedAt: Date? = nil,
        renameIfUntitled: Bool = true
    ) async throws -> (note: Note, ciphertext: String) {
        let now = Date()
        let isEncrypted = mode == .encrypted
        // Resolve the key on the main actor (throws if missing); the actual disk work
        // runs off-main on the serial IO lane.
        let encryptionKey: CryptoKit.SymmetricKey? = isEncrypted ? try currentEncryptionKey() : nil
        let indexSnapshot = noteIndex
        let autoRename = settings.autoRenameNotesOnSave

        let outcome = try await fileIO.perform { [storage] in
            try Self.executeSave(
                note: note,
                body: body,
                mode: mode,
                sourceUpdatedAt: sourceUpdatedAt,
                renameIfUntitled: renameIfUntitled,
                autoRename: autoRename,
                encryptionKey: encryptionKey,
                storage: storage,
                index: indexSnapshot,
                now: now
            )
        }

        noteIndex = outcome.updatedIndex
        let updatedNote = outcome.updatedNote
        if isEncrypted {
            plainNotes.removeAll { $0.id == note.id }
            if let index = decryptedNotes.firstIndex(where: { $0.id == note.id }) {
                decryptedNotes[index] = updatedNote
            } else {
                decryptedNotes.insert(updatedNote, at: 0)
            }
        } else {
            decryptedNotes.removeAll { $0.id == note.id }
            if let index = plainNotes.firstIndex(where: { $0.id == note.id }) {
                plainNotes[index] = updatedNote
            } else {
                plainNotes.insert(updatedNote, at: 0)
            }
        }
        lockedEncryptedNotes.removeAll { $0.id == note.id }

        // Surface the disk version that would otherwise be silently overwritten as a
        // real, visible note (P1-2).
        if let conflict = outcome.conflictNote {
            if conflict.isEncrypted {
                decryptedNotes.insert(conflict, at: 0)
            } else {
                plainNotes.insert(conflict, at: 0)
            }
        }

        return (updatedNote, outcome.finalBody)
    }

    nonisolated struct SaveOutcome: Sendable {
        let updatedIndex: NoteIndex
        let updatedNote: Note
        let finalBody: String
        let conflictNote: Note?
    }

    /// Off-main disk work for a save: conflict check, conflict-preserve, write, delete
    /// stale file, persist index. Pure over its inputs so the serial IO lane can run it.
    nonisolated private static func executeSave(
        note: Note,
        body: String,
        mode: NoteFileMode,
        sourceUpdatedAt: Date?,
        renameIfUntitled: Bool,
        autoRename: Bool,
        encryptionKey: CryptoKit.SymmetricKey?,
        storage: VaultStorage,
        index inputIndex: NoteIndex,
        now: Date
    ) throws -> SaveOutcome {
        var index = inputIndex
        let isEncrypted = mode == .encrypted
        let finalBody: String
        if isEncrypted {
            guard let key = encryptionKey else { throw CryptoError.keyNotFound }
            finalBody = try CryptoService.shared.encryptMarkdownBody(body, using: key)
        } else {
            finalBody = body
        }

        guard let currentEntry = index.entry(for: note.id),
              let currentURL = urlForEntry(currentEntry, storage: storage) else {
            throw StorageError.iCloudUnavailable
        }

        func decryptedIfPossible(_ file: MarkdownNoteFile) -> String {
            guard file.isEncrypted, let key = encryptionKey else { return file.body }
            return (try? CryptoService.shared.decryptMarkdownBody(file.body, using: key)) ?? file.body
        }

        let diskFile = try? storage.loadMarkdownFile(at: currentURL)
        let stableTitle = stableExistingTitle(for: currentEntry, mdFile: diskFile)
        let shouldRename = autoRename || (stableTitle == nil && renameIfUntitled)
        let existingTitle = autoRename ? nil : stableTitle
        let newFileName = shouldRename
            ? uniqueFileName(for: body, storage: storage, currentFileName: currentEntry.fileName)
            : currentEntry.fileName
        guard let targetURL = urlForFileName(newFileName, storage: storage) else {
            throw StorageError.iCloudUnavailable
        }

        var conflictNote: Note?
        if let diskFile {
            let baselineUpdatedAt = sourceUpdatedAt ?? note.updatedAt
            let diskIsNewer = diskFile.updatedAt.timeIntervalSince(baselineUpdatedAt) > 1
            let diskLogical = decryptedIfPossible(diskFile)
            let bodyDiffers = diskLogical != note.body
            MaintenanceLogStore.shared.record("note_save_conflict_check", fields: [
                "note_id": note.id,
                "current_file": currentURL.lastPathComponent,
                "target_file": targetURL.lastPathComponent,
                "mode": mode.rawValue,
                "disk_is_newer": diskIsNewer,
                "body_differs": bodyDiffers,
                "body_bytes": body.utf8.count
            ])
            if diskIsNewer && bodyDiffers {
                // Keep the disk version as a visible "conflict copy" note instead of
                // overwriting it into an invisible conflicts/ folder.
                let conflictId = UUID().uuidString
                let baseTitle = diskFile.title
                    ?? NoteTitleFormatter.displayTitle(fromFileName: currentEntry.fileName, emptyTitle: "")
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
                let suffix = "（冲突副本 \(formatter.string(from: now))）"
                let conflictTitle = baseTitle.isEmpty ? suffix : "\(baseTitle)\(suffix)"
                let conflictFileName = "\(conflictId).md"
                if let conflictURL = urlForFileName(conflictFileName, storage: storage) {
                    let conflictFile = MarkdownNoteFile(
                        noteId: conflictId,
                        createdAt: diskFile.createdAt,
                        updatedAt: diskFile.updatedAt,
                        title: conflictTitle,
                        body: diskFile.body    // raw disk body — keeps encryption
                    )
                    try? storage.saveMarkdownFile(conflictFile, at: conflictURL)
                    index.upsert(NoteIndexEntry(noteId: conflictId, fileName: conflictFileName, mode: currentEntry.mode, location: .notes))
                    conflictNote = Note(
                        id: conflictId,
                        body: decryptedIfPossible(conflictFile),
                        createdAt: diskFile.createdAt,
                        updatedAt: diskFile.updatedAt,
                        isEncrypted: currentEntry.mode == .encrypted
                    )
                    MaintenanceLogStore.shared.record("note_save_conflict_preserved", fields: [
                        "note_id": note.id,
                        "conflict_note_id": conflictId,
                        "conflict_file": conflictFileName
                    ])
                }
            }
        }

        let mdFile = MarkdownNoteFile(
            noteId: note.id,
            createdAt: note.createdAt,
            updatedAt: now,
            title: existingTitle ?? (shouldRename ? title(for: body) : nil),
            body: finalBody
        )
        try storage.saveMarkdownFile(mdFile, at: targetURL)

        if currentURL != targetURL && FileManager.default.fileExists(atPath: currentURL.path) {
            try? storage.permanentlyDeleteFile(at: currentURL)
        }

        if let entry = index.entry(for: note.id) {
            index.upsert(NoteIndexEntry(
                noteId: entry.noteId,
                fileName: newFileName,
                mode: mode,
                location: entry.location,
                deletedAt: entry.deletedAt,
                purgeAfter: entry.purgeAfter,
                originalLocation: entry.originalLocation
            ))
        } else {
            index.upsert(NoteIndexEntry(noteId: note.id, fileName: newFileName, mode: mode, location: .notes))
        }
        try storage.saveIndex(index)
        MaintenanceLogStore.shared.record("note_saved", fields: [
            "note_id": note.id,
            "file": newFileName,
            "mode": mode.rawValue,
            "renamed": currentURL != targetURL,
            "body_bytes": body.utf8.count
        ])

        let updatedNote = Note(
            id: note.id,
            body: body,
            createdAt: note.createdAt,
            updatedAt: now,
            isEncrypted: isEncrypted
        )
        return SaveOutcome(updatedIndex: index, updatedNote: updatedNote, finalBody: finalBody, conflictNote: conflictNote)
    }

    func renameNote(_ note: Note, title: String, limitsLength: Bool = true) async throws {
        guard let entry = noteIndex.entry(for: note.id), entry.location == .notes else {
            throw StorageError.fileNotFound
        }
        guard let cleanedTitle = NoteTitleFormatter.sanitizedGeneratedTitle(title, limitsLength: limitsLength) else {
            throw StorageError.invalidData
        }

        let newFileName = Self.uniqueFileName(
            forTitle: cleanedTitle,
            storage: storage,
            currentFileName: entry.fileName
        )
        guard let currentURL = Self.urlForEntry(entry, storage: storage),
              let targetURL = Self.urlForFileName(newFileName, storage: storage) else {
            throw StorageError.iCloudUnavailable
        }

        var mdFile = try storage.loadMarkdownFile(at: currentURL)
        mdFile.title = cleanedTitle
        try storage.saveMarkdownFile(mdFile, at: targetURL)
        if currentURL != targetURL && FileManager.default.fileExists(atPath: currentURL.path) {
            try storage.permanentlyDeleteFile(at: currentURL)
        }
        noteIndex.upsert(NoteIndexEntry(
            noteId: entry.noteId,
            fileName: newFileName,
            mode: entry.mode,
            location: entry.location,
            deletedAt: entry.deletedAt,
            purgeAfter: entry.purgeAfter,
            originalLocation: entry.originalLocation
        ))
        try storage.saveIndex(noteIndex)
        MaintenanceLogStore.shared.record("note_renamed", fields: [
            "note_id": note.id,
            "from": entry.fileName,
            "to": newFileName
        ])
        objectWillChange.send()
    }

    func deleteNote(_ note: Note) async throws {
        let now = Date()
        let purgeAfter = now.addingTimeInterval(30 * 86400)

        guard let entry = noteIndex.entry(for: note.id),
              let srcURL = Self.urlForEntry(entry, storage: storage) else {
            throw StorageError.fileNotFound
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
            title: mdFile.title ?? Self.title(for: note.body),
            body: mdFile.body
        )
        try storage.saveMarkdownFile(trashFile, at: trashURL)
        try storage.permanentlyDeleteFile(at: srcURL)

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
        MaintenanceLogStore.shared.record("note_deleted_to_trash", fields: [
            "note_id": note.id,
            "source_file": srcURL.lastPathComponent,
            "trash_file": trashURL.lastPathComponent,
            "mode": entry.mode.rawValue
        ])

        decryptedNotes.removeAll { $0.id == note.id }
        plainNotes.removeAll { $0.id == note.id }
        lockedEncryptedNotes.removeAll { $0.id == note.id }

        await reloadTrashOnly()
    }

    func discardEmptyNote(_ note: Note) async throws {
        try await discardEmptyNote(note, body: note.body)
    }

    func discardEmptyNote(_ note: Note, body: String) async throws {
        guard body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if let entry = noteIndex.entry(for: note.id),
           let url = Self.urlForEntry(entry, storage: storage),
           FileManager.default.fileExists(atPath: url.path) {
            try storage.permanentlyDeleteFile(at: url)
        }
        noteIndex.removeEntry(for: note.id)
        try? storage.saveIndex(noteIndex)

        decryptedNotes.removeAll { $0.id == note.id }
        plainNotes.removeAll { $0.id == note.id }
        lockedEncryptedNotes.removeAll { $0.id == note.id }
    }

    func clearEmptyReadableNotes() async throws -> Int {
        let emptyNotes = readableNotes.filter { note in
            guard note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            #if os(iOS)
            // A cloud-only placeholder has an empty body only because its content
            // hasn't downloaded yet — deleting it would lose the real note (P0-2).
            if isCloudOnly(note) { return false }
            #endif
            return true
        }
        for note in emptyNotes {
            try await deleteNote(note)
        }
        return emptyNotes.count
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
            title: mdFile.title,
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
        guard FileManager.default.fileExists(atPath: srcURL.path) else { return }

        let mdFile = try storage.loadMarkdownFile(at: srcURL)
        let restoredBody = trashNote.body ?? trashNote.title
        let restoredFileName = Self.uniqueFileName(for: restoredBody, storage: storage)
        guard let dstURL = Self.urlForFileName(restoredFileName, storage: storage) else {
            throw StorageError.iCloudUnavailable
        }
        let restoredFile = MarkdownNoteFile(
            noteId: mdFile.noteId,
            createdAt: mdFile.createdAt,
            updatedAt: Date(),
            title: mdFile.title ?? Self.title(for: restoredBody),
            body: mdFile.body
        )
        try storage.saveMarkdownFile(restoredFile, at: dstURL)
        try storage.permanentlyDeleteFile(at: srcURL)

        if let entry = noteIndex.entry(for: trashNote.id) {
            noteIndex.upsert(NoteIndexEntry(
                noteId: entry.noteId,
                fileName: restoredFileName,
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
        do {
            let loadedIndex = try await Task.detached(priority: .utility) { [storage, noteIndex] in
                var index = noteIndex
                let changed = Self.purgeExpiredTrash(in: &index, storage: storage)
                if changed {
                    try storage.saveIndex(index)
                }
                return index
            }.value
            noteIndex = loadedIndex
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    nonisolated private static func purgeExpiredTrash(
        in index: inout NoteIndex,
        storage: VaultStorage,
        now: Date = Date()
    ) -> Bool {
        var purgedIds: [String] = []
        for entry in index.entries where entry.location == .trash {
            if let purgeAfter = entry.purgeAfter, purgeAfter <= now {
                if let url = storage.trashFileURL(for: entry.noteId) {
                    try? storage.permanentlyDeleteFile(at: url)
                }
                purgedIds.append(entry.noteId)
            }
        }
        if !purgedIds.isEmpty {
            for id in purgedIds {
                index.removeEntry(for: id)
            }
            return true
        }
        return false
    }

    private func requestSelectedKeyDownloadIfNeeded(at url: URL) throws {
        let resourceKeys: Set<URLResourceKey> = [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        guard let values = try? url.resourceValues(forKeys: resourceKeys),
              values.isUbiquitousItem == true else {
            return
        }

        let status = values.ubiquitousItemDownloadingStatus
        if status == .current || status == .downloaded {
            return
        }

        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            MaintenanceLogStore.shared.record("vault_key_icloud_download_requested", fields: [
                "file": url.lastPathComponent
            ])
        } catch {
            MaintenanceLogStore.shared.record("vault_key_icloud_download_request_failed", fields: [
                "file": url.lastPathComponent,
                "error": error.localizedDescription
            ])
        }

        throw VaultKeyFileError.keyDownloadPending
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
                if note.isEncrypted || isCloudOnly(note) {
                    // Encrypted, or a not-yet-downloaded cloud placeholder (empty body) — skip (P0-2).
                    skipped += 1
                } else {
                    let copiedBody = settings.copyAddsParagraphSpacing
                        ? MarkdownFormatter.stringByAddingMarkdownParagraphSpacing(to: note.body)
                        : note.body
                    plainBodies.append(copiedBody)
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
        let sortedPlain = plainNotes.sorted { $0.updatedAt > $1.updatedAt }
        #if os(iOS)
        // Cloud-only placeholders have empty bodies until downloaded — exporting them
        // would ship blank files, so skip and count them (no on-the-fly download). (P0-2)
        let plainOnly = sortedPlain.filter { !isCloudOnly($0) }
        let cloudOnlySkipped = sortedPlain.count - plainOnly.count
        #else
        let plainOnly = sortedPlain
        let cloudOnlySkipped = 0
        #endif
        let skippedCount = decryptedNotes.count + lockedEncryptedNotes.count + cloudOnlySkipped

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Seal Note-笔记-\(dateStr)-\(UUID().uuidString.prefix(8))")
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
                title: Self.title(for: note.body),
                body: note.body
            )
            let data = try mdFile.render()
            try data.write(to: fileURL, options: .atomic)
        }

        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Seal Note-笔记-\(dateStr).zip")
        try ZipUtility.createZip(from: tmpDir, to: zipURL)
        try? FileManager.default.removeItem(at: tmpDir)

        return (zipURL, plainOnly.count, skippedCount)
    }

    func handleEnterBackground() {
        guard settings.autoUnloadKeyOnForeground == false else { return }
    }

    func handleEnterForeground() async {
        // Never destroys the key. Non-destructive session unlock happens via
        // AppLockStore.unlock() (Face ID / passcode) → unlockSession() (P0-4).
        await purgeExpiredTrash()
    }
}

nonisolated enum NoteListItem: Identifiable, Equatable {
    case readable(Note)
    case locked(EncryptedNoteInfo)

    var id: String {
        switch self {
        case .readable(let note): return note.id
        case .locked(let info): return info.id
        }
    }

    var createdAt: Date {
        switch self {
        case .readable(let note): return note.createdAt
        case .locked(let info): return info.createdAt
        }
    }

    var updatedAt: Date {
        switch self {
        case .readable(let note): return note.updatedAt
        case .locked(let info): return info.updatedAt
        }
    }
}

nonisolated enum VaultError: Error, LocalizedError {
    case notReady
    case keyNotLoaded

    var errorDescription: String? {
        switch self {
        case .notReady: return "加密空间未就绪"
        case .keyNotLoaded: return "密钥未加载，无法创建或编辑加密笔记"
        }
    }
}

nonisolated enum VaultKeyFileError: Error, LocalizedError, Equatable {
    case fileMissing
    case fileMoved
    case permissionDenied
    case invalidFile
    case unsupportedFileExtension
    case keyReplaced
    case keyMismatch
    case keyAlreadyConfigured
    case encryptedNotesExist
    case keyDownloadPending

    var errorDescription: String? {
        switch self {
        case .fileMissing:
            return "找不到密钥，请确认 U 盘、同步盘或文件位置可用。"
        case .fileMoved:
            return "密钥已不在原位置，请将它移回原路径，或重新定位密钥。"
        case .permissionDenied:
            return "无法读取密钥，请重新选择密钥。"
        case .invalidFile:
            return "密钥格式无效。"
        case .unsupportedFileExtension:
            return "请选择有效的 Seal Note 密钥。"
        case .keyReplaced:
            return "密钥已被替换或内容被修改，请重新定位原密钥。"
        case .keyMismatch:
            return "密钥不匹配，无法解密当前加密笔记。"
        case .keyAlreadyConfigured:
            return "已经存在密钥引用，请先移除当前密钥引用。"
        case .encryptedNotesExist:
            return "仍有加密笔记，请先删除全部加密笔记，或先全部解密成明文。"
        case .keyDownloadPending:
            return "密钥仍在从 iCloud 下载，请稍后再试。"
        }
    }
}

/// Serial IO lane. Actor methods are mutually exclusive and `op` runs synchronously
/// inside `perform` (no suspension), so disk mutations never interleave and never run
/// on the main actor (P0/P1-2).
actor VaultFileIO {
    func perform<T: Sendable>(_ op: @Sendable () throws -> T) async throws -> T {
        try op()
    }
}
