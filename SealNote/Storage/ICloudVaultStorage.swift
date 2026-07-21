import Foundation

final class ICloudVaultStorage: VaultStorage, @unchecked Sendable {
    static let shared = ICloudVaultStorage()

    private let containerIdentifier = "iCloud.com.xuweinan.sealnote"
    private static let indexDownloadTimeout: TimeInterval = 8
    private static let noteDownloadTimeout: TimeInterval = 0.8
    private static let downloadPollInterval: TimeInterval = 0.2

    private let ubiquityContainerURL: URL?
    private let _containerURL: URL?

    nonisolated var containerURL: URL? {
        _containerURL
    }

    nonisolated var isAvailable: Bool {
        containerURL != nil
    }

    private init() {
        let ubiquityURL = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier)
        ubiquityContainerURL = ubiquityURL
        _containerURL = ubiquityURL?.appendingPathComponent("Documents", isDirectory: true)
        MaintenanceLogStore.shared.record("icloud_storage_init", fields: [
            "container": _containerURL?.path,
            "ubiquity_container": ubiquityURL?.path
        ])
    }

    nonisolated private static func sandboxedPublicICloudDriveFolderURL() -> URL? {
        #if os(macOS)
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        guard homeURL.path.contains("/Library/Containers/") else { return nil }
        return homeURL
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
            .appendingPathComponent("Seal Note", isDirectory: true)
        #else
        return nil
        #endif
    }

    func initializeVault() async throws {
        guard let ubiquityContainer = ubiquityContainerURL,
              let container = containerURL else {
            throw StorageError.iCloudUnavailable
        }

        try migrateVaultIfNeeded(from: ubiquityContainer, to: container)
        try migrateVaultIfNeeded(from: ubiquityContainer.appendingPathComponent("Documents"), to: container)
        if let sandboxedPublicFolder = Self.sandboxedPublicICloudDriveFolderURL() {
            try migrateVaultIfNeeded(from: sandboxedPublicFolder, to: container)
        }

        let directories = [
            container,
            container.appendingPathComponent("trash"),
            container.appendingPathComponent(".meta")
        ]

        for directory in directories {
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                MaintenanceLogStore.shared.record("storage_directory_created", fields: [
                    "path": directory.path
                ])
            }
        }
    }

    nonisolated private func migrateVaultIfNeeded(from oldRoot: URL, to publicRoot: URL) throws {
        let fm = FileManager.default
        guard oldRoot.standardizedFileURL != publicRoot.standardizedFileURL else { return }
        guard fm.fileExists(atPath: oldRoot.path) else { return }

        if !fm.fileExists(atPath: publicRoot.path) {
            try fm.createDirectory(at: publicRoot, withIntermediateDirectories: true)
        }

        moveMarkdownFiles(from: oldRoot, to: publicRoot, fileManager: fm)

        let folderMappings = [
            ("notes", ""),
            ("trash", "trash"),
            ("conflicts", "conflicts"),
            ("meta", ".meta"),
            (".meta", ".meta")
        ]

        for (sourceFolderName, destinationFolderName) in folderMappings {
            let source = oldRoot.appendingPathComponent(sourceFolderName)
            let destination = destinationFolderName.isEmpty
                ? publicRoot
                : publicRoot.appendingPathComponent(destinationFolderName)
            moveContents(from: source, to: destination, fileManager: fm)
        }

        for oldFolderName in ["notes", "meta"] {
            let oldFolder = oldRoot.appendingPathComponent(oldFolderName)
            if let children = try? fm.contentsOfDirectory(atPath: oldFolder.path), children.isEmpty {
                try? fm.removeItem(at: oldFolder)
            }
        }

        let sourceIndex = oldRoot.appendingPathComponent("notes.json")
        let destinationIndex = publicRoot.appendingPathComponent("notes.json")
        if fm.fileExists(atPath: sourceIndex.path), !fm.fileExists(atPath: destinationIndex.path) {
            try fm.moveItem(at: sourceIndex, to: destinationIndex)
        }
    }

    nonisolated private func moveMarkdownFiles(from sourceDir: URL, to destinationDir: URL, fileManager fm: FileManager) {
        guard let children = try? fm.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        for child in children where child.pathExtension == "md" {
            let target = destinationDir.appendingPathComponent(child.lastPathComponent)
            guard !fm.fileExists(atPath: target.path) else { continue }
            try? fm.moveItem(at: child, to: target)
        }
    }

    nonisolated private func moveContents(from source: URL, to destination: URL, fileManager fm: FileManager) {
        guard fm.fileExists(atPath: source.path) else { return }

        if !fm.fileExists(atPath: destination.path) {
            try? fm.createDirectory(at: destination, withIntermediateDirectories: true)
        }

        guard let children = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        for child in children {
            let target = destination.appendingPathComponent(child.lastPathComponent)
            guard !fm.fileExists(atPath: target.path) else { continue }
            try? fm.moveItem(at: child, to: target)
        }

        if let remaining = try? fm.contentsOfDirectory(atPath: source.path), remaining.isEmpty {
            try? fm.removeItem(at: source)
        }
    }

    func loadIndex() throws -> NoteIndex? {
        guard let url = notesIndexURL else {
            throw StorageError.iCloudUnavailable
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try readUbiquitousData(at: url, timeout: Self.indexDownloadTimeout)
        return try JSONDecoder.default.decode(NoteIndex.self, from: data)
    }

    func saveIndex(_ index: NoteIndex) throws {
        guard let url = notesIndexURL else {
            throw StorageError.iCloudUnavailable
        }

        let data = try JSONEncoder.default.encode(index)
        try atomicWrite(data: data, to: url)
        postVaultStorageMutation(at: url)
        MaintenanceLogStore.shared.record("index_saved", fields: [
            "entries": index.entries.count,
            "file": url.lastPathComponent,
            "bytes": data.count
        ])
    }

    func listMarkdownFiles(in location: NoteFileLocation) throws -> [URL] {
        guard let container = containerURL else {
            throw StorageError.iCloudUnavailable
        }
        let dirURL = location == .notes ? container : container.appendingPathComponent(location.rawValue)
        return try listMarkdownFilesInDirectory(dirURL)
    }

    func loadMarkdownFile(at url: URL) throws -> MarkdownNoteFile {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StorageError.fileNotFound
        }
        let data = try readUbiquitousData(at: url, timeout: Self.noteDownloadTimeout)
        return try MarkdownNoteFile.parse(from: data)
    }

    nonisolated func isItemDownloaded(at url: URL) -> Bool {
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isUbiquitousItem == true else {
            return true
        }
        return values.ubiquitousItemDownloadingStatus == .current
            || values.ubiquitousItemDownloadingStatus == .downloaded
    }

    func saveMarkdownFile(_ file: MarkdownNoteFile, at url: URL) throws {
        let data = try file.render()
        try atomicWrite(data: data, to: url)
        postVaultStorageMutation(at: url)
        MaintenanceLogStore.shared.record("markdown_saved", fields: [
            "note_id": file.noteId,
            "file": url.lastPathComponent,
            "updated_at": ISO8601DateFormatter().string(from: file.updatedAt),
            "bytes": data.count
        ])
    }

    func moveFile(from srcURL: URL, to dstURL: URL) throws {
        guard FileManager.default.fileExists(atPath: srcURL.path) else {
            throw StorageError.fileNotFound
        }
        let dstDir = dstURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dstDir.path) {
            try FileManager.default.createDirectory(at: dstDir, withIntermediateDirectories: true)
        }
        if FileManager.default.fileExists(atPath: dstURL.path) {
            try FileManager.default.removeItem(at: dstURL)
        }
        try FileManager.default.moveItem(at: srcURL, to: dstURL)
        postVaultStorageMutation(at: dstURL)
        MaintenanceLogStore.shared.record("file_moved", fields: [
            "from": srcURL.lastPathComponent,
            "to": dstURL.lastPathComponent
        ])
    }

    func permanentlyDeleteFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StorageError.fileNotFound
        }
        try FileManager.default.removeItem(at: url)
        postVaultStorageMutation(at: url)
        MaintenanceLogStore.shared.record("file_deleted", fields: [
            "file": url.lastPathComponent
        ])
    }

    func createConflictCopy(for url: URL) throws -> URL {
        guard let container = containerURL else {
            throw StorageError.iCloudUnavailable
        }
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = url.deletingPathExtension().lastPathComponent
        let conflictFilename = "\(filename)-conflict-\(timestamp).md"
        let conflictDir = container.appendingPathComponent("conflicts")
        if !FileManager.default.fileExists(atPath: conflictDir.path) {
            try FileManager.default.createDirectory(at: conflictDir, withIntermediateDirectories: true)
        }
        let conflictURL = conflictDir.appendingPathComponent(conflictFilename)
        try FileManager.default.copyItem(at: url, to: conflictURL)
        postVaultStorageMutation(at: conflictURL)
        MaintenanceLogStore.shared.record("conflict_copy_created", fields: [
            "source": url.lastPathComponent,
            "conflict": conflictURL.lastPathComponent,
            "timestamp": timestamp
        ])
        return conflictURL
    }

    private func atomicWrite(data: Data, to url: URL) throws {
        let tempURL = url.appendingPathExtension("tmp")
        try data.write(to: tempURL, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            // Atomic replace — never a window where the destination file is absent (P1-2).
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: url)
        }
    }

    private func readUbiquitousData(at url: URL, timeout: TimeInterval) throws -> Data {
        try ensureUbiquitousItemIsReadable(at: url, timeout: timeout)
        return try Data(contentsOf: url)
    }

    private func ensureUbiquitousItemIsReadable(at url: URL, timeout: TimeInterval) throws {
        let fm = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]

        func isReadableNow() -> Bool {
            guard let values = try? url.resourceValues(forKeys: resourceKeys),
                  values.isUbiquitousItem == true else {
                return true
            }

            let status = values.ubiquitousItemDownloadingStatus
            return status == .current || status == .downloaded
        }

        guard !isReadableNow() else { return }

        do {
            try fm.startDownloadingUbiquitousItem(at: url)
            MaintenanceLogStore.shared.record("icloud_download_requested", fields: [
                "file": url.lastPathComponent
            ])
        } catch {
            MaintenanceLogStore.shared.record("icloud_download_request_failed", fields: [
                "file": url.lastPathComponent,
                "error": error.localizedDescription
            ])
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: Self.downloadPollInterval)
            if isReadableNow() {
                MaintenanceLogStore.shared.record("icloud_download_ready", fields: [
                    "file": url.lastPathComponent
                ])
                return
            }
        }

        MaintenanceLogStore.shared.record("icloud_download_pending", fields: [
            "file": url.lastPathComponent,
            "timeout": timeout
        ])
        throw StorageError.iCloudDownloadPending
    }
}
