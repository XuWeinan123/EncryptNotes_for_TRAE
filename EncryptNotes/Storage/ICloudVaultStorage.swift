import Foundation

final class ICloudVaultStorage: VaultStorage, @unchecked Sendable {
    static let shared = ICloudVaultStorage()

    private let containerIdentifier = "iCloud.com.biekanwo.EncryptNotes"

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
            ?? Self.developmentContainerURL()
        ubiquityContainerURL = ubiquityURL
        _containerURL = Self.publicICloudDriveFolderURL()
            ?? ubiquityURL?.appendingPathComponent("Documents")
    }

    nonisolated private static func developmentContainerURL() -> URL? {
        #if os(macOS)
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/iCloud~com~biekanwo~EncryptNotes")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
        #else
        return nil
        #endif
    }

    nonisolated private static func publicICloudDriveFolderURL() -> URL? {
        #if os(macOS)
        let cloudDocsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        return cloudDocsURL.appendingPathComponent("别看我")
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

        let directories = [
            container,
            container.appendingPathComponent("trash"),
            container.appendingPathComponent(".meta")
        ]

        for directory in directories {
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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

        let data = try Data(contentsOf: url)
        return try JSONDecoder.default.decode(NoteIndex.self, from: data)
    }

    func saveIndex(_ index: NoteIndex) throws {
        guard let url = notesIndexURL else {
            throw StorageError.iCloudUnavailable
        }

        let data = try JSONEncoder.default.encode(index)
        try atomicWrite(data: data, to: url)
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
        let data = try Data(contentsOf: url)
        return try MarkdownNoteFile.parse(from: data)
    }

    func saveMarkdownFile(_ file: MarkdownNoteFile, at url: URL) throws {
        let data = try file.render()
        try atomicWrite(data: data, to: url)
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
    }

    func permanentlyDeleteFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StorageError.fileNotFound
        }
        try FileManager.default.removeItem(at: url)
    }

    func createConflictCopy(for url: URL) throws -> URL {
        guard let container = containerURL else {
            throw StorageError.iCloudUnavailable
        }
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = url.deletingPathExtension().lastPathComponent
        let conflictFilename = "\(filename)-conflict-\(timestamp).md"
        let conflictURL = container.appendingPathComponent(conflictFilename)
        try FileManager.default.copyItem(at: url, to: conflictURL)
        return conflictURL
    }

    private func atomicWrite(data: Data, to url: URL) throws {
        let tempURL = url.appendingPathExtension("tmp")
        try data.write(to: tempURL, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: tempURL, to: url)
    }
}
