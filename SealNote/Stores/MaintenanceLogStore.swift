import Foundation

final class MaintenanceLogStore: @unchecked Sendable {
    nonisolated static let shared = MaintenanceLogStore()

    private let defaultsKey = "SNMaintenanceLoggingEnabled"
    private let lock = NSLock()

    private init() {}

    nonisolated var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? false
    }

    nonisolated var logFileURL: URL {
        logsDirectory.appendingPathComponent("seal-note-maintenance.log")
    }

    nonisolated var logsDirectory: URL {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return baseURL.appendingPathComponent("Seal Note/Logs", isDirectory: true)
    }

    nonisolated func record(_ event: String, fields: [String: CustomStringConvertible?] = [:]) {
        guard isEnabled || event == "maintenance_logging_enabled" else { return }

        var payload: [String: String] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "event": event
        ]
        for (key, value) in fields {
            if let value {
                payload[key] = value.description
            }
        }

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: logFileURL.path) {
                fileManager.createFile(atPath: logFileURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: logFileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let lineData = (line + "\n").data(using: .utf8) {
                try handle.write(contentsOf: lineData)
            }
        } catch {
            #if DEBUG
            print("Seal Note maintenance log failed: \(error.localizedDescription)")
            #endif
        }
    }

    nonisolated func exportLogFile() throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: logFileURL.path) {
            fileManager.createFile(atPath: logFileURL.path, contents: nil)
        }
        return logFileURL
    }
}
