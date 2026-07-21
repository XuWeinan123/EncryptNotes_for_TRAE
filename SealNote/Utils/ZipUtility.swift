import Foundation

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

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ZipError.invalidSource
        }

        var entries: [URL] = []
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }
            entries.append(fileURL)
        }
        entries.sort { $0.path < $1.path }

        var output = Data()
        var centralDirectory = Data()

        for fileURL in entries {
            do {
                let relativePath = fileURL.path
                    .replacingOccurrences(of: sourceDirectory.path + "/", with: "")
                    .replacingOccurrences(of: "\\", with: "/")
                let nameData = Data(relativePath.utf8)
                let fileData = try Data(contentsOf: fileURL)
                guard fileData.count <= Int(UInt32.max),
                      nameData.count <= Int(UInt16.max),
                      output.count <= Int(UInt32.max) else {
                    throw ZipError.addEntryFailed(fileURL.lastPathComponent)
                }

                let crc = CRC32.checksum(fileData)
                let localOffset = UInt32(output.count)
                let dos = dosDateTime(for: fileURL)

                output.appendUInt32LE(0x04034b50)
                output.appendUInt16LE(20)
                output.appendUInt16LE(1 << 11)
                output.appendUInt16LE(0)
                output.appendUInt16LE(dos.time)
                output.appendUInt16LE(dos.date)
                output.appendUInt32LE(crc)
                output.appendUInt32LE(UInt32(fileData.count))
                output.appendUInt32LE(UInt32(fileData.count))
                output.appendUInt16LE(UInt16(nameData.count))
                output.appendUInt16LE(0)
                output.append(nameData)
                output.append(fileData)

                centralDirectory.appendUInt32LE(0x02014b50)
                centralDirectory.appendUInt16LE(20)
                centralDirectory.appendUInt16LE(20)
                centralDirectory.appendUInt16LE(1 << 11)
                centralDirectory.appendUInt16LE(0)
                centralDirectory.appendUInt16LE(dos.time)
                centralDirectory.appendUInt16LE(dos.date)
                centralDirectory.appendUInt32LE(crc)
                centralDirectory.appendUInt32LE(UInt32(fileData.count))
                centralDirectory.appendUInt32LE(UInt32(fileData.count))
                centralDirectory.appendUInt16LE(UInt16(nameData.count))
                centralDirectory.appendUInt16LE(0)
                centralDirectory.appendUInt16LE(0)
                centralDirectory.appendUInt16LE(0)
                centralDirectory.appendUInt16LE(0)
                centralDirectory.appendUInt32LE(0)
                centralDirectory.appendUInt32LE(localOffset)
                centralDirectory.append(nameData)
            } catch {
                throw ZipError.addEntryFailed(fileURL.lastPathComponent)
            }
        }

        guard centralDirectory.count <= Int(UInt32.max),
              output.count <= Int(UInt32.max),
              entries.count <= Int(UInt16.max) else {
            throw ZipError.createFailed
        }

        let centralDirectoryOffset = UInt32(output.count)
        output.append(centralDirectory)
        output.appendUInt32LE(0x06054b50)
        output.appendUInt16LE(0)
        output.appendUInt16LE(0)
        output.appendUInt16LE(UInt16(entries.count))
        output.appendUInt16LE(UInt16(entries.count))
        output.appendUInt32LE(UInt32(centralDirectory.count))
        output.appendUInt32LE(centralDirectoryOffset)
        output.appendUInt16LE(0)

        try output.write(to: destinationURL, options: .atomic)
    }

    private static func dosDateTime(for url: URL) -> (date: UInt16, time: UInt16) {
        let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: modifiedAt)
        let year = max((components.year ?? 1980), 1980)
        let dosDate = UInt16(((year - 1980) << 9) | ((components.month ?? 1) << 5) | (components.day ?? 1))
        let dosTime = UInt16(((components.hour ?? 0) << 11) | ((components.minute ?? 0) << 5) | ((components.second ?? 0) / 2))
        return (dosDate, dosTime)
    }
}

private enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = (crc & 1) == 1 ? (0xedb88320 ^ (crc >> 1)) : (crc >> 1)
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
        }
        return crc ^ 0xffffffff
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
