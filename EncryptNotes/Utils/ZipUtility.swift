import Foundation
import Compression

enum ZipError: Error, LocalizedError {
    case createFailed
    case addEntryFailed(String)
    case invalidSource

    var errorDescription: String? {
        switch self {
        case .createFailed: return "无法创建 zip 文件"
        case .addEntryFailed(let name): return "无法添加文件到 zip: \(name)"
        case .invalidSource: return "无效的源路径"
        }
    }
}

enum ZipUtility {
    static func createZip(from sourceDirectory: URL, to destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        guard let archive = Archive(url: destinationURL, accessMode: .create) else {
            throw ZipError.createFailed
        }

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ZipError.invalidSource
        }

        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }

            do {
                try archive.addEntry(
                    with: fileURL.lastPathComponent,
                    relativeTo: sourceDirectory,
                    compressionMethod: .deflate
                )
            } catch {
                throw ZipError.addEntryFailed(fileURL.lastPathComponent)
            }
        }
    }
}
