#if os(macOS)
import AppKit
import Darwin
import Foundation

@MainActor
final class VaultExternalChangeMonitor {
    static let shared = VaultExternalChangeMonitor()

    private let queue = DispatchQueue(label: "com.xuweinan.sealnote.vault-external-change-monitor", qos: .utility)
    private var sources: [DispatchSourceFileSystemObject] = []
    private var localMutationObserver: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?
    private var monitoredRoot: URL?
    private var lastLocalMutationAt = Date.distantPast

    private let debounceInterval: TimeInterval = 1.2
    private let localMutationQuietInterval: TimeInterval = 1.8

    private init() {}

    func start() {
        guard sources.isEmpty else { return }
        guard let root = VaultStore.shared.storageContainerURL else { return }

        monitoredRoot = root
        installLocalMutationObserver()
        addDirectorySource(for: root)
        addDirectorySource(for: root.appendingPathComponent("trash", isDirectory: true))

        MaintenanceLogStore.shared.record("vault_external_change_monitor_started", fields: [
            "root": root.path
        ])
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil

        for source in sources {
            source.cancel()
        }
        sources.removeAll()

        if let localMutationObserver {
            NotificationCenter.default.removeObserver(localMutationObserver)
            self.localMutationObserver = nil
        }

        monitoredRoot = nil
    }

    private func installLocalMutationObserver() {
        guard localMutationObserver == nil else { return }
        localMutationObserver = NotificationCenter.default.addObserver(
            forName: .vaultStorageDidMutate,
            object: nil,
            queue: .main
        ) { _ in
            let mutationDate = Date()
            Task { @MainActor in
                VaultExternalChangeMonitor.shared.lastLocalMutationAt = mutationDate
            }
        }
    }

    private func addDirectorySource(for url: URL) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            MaintenanceLogStore.shared.record("vault_external_change_monitor_failed", fields: [
                "path": url.path,
                "errno": errno
            ])
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.handleFileSystemEvent()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        sources.append(source)
    }

    private func handleFileSystemEvent() {
        let elapsedSinceLocalMutation = Date().timeIntervalSince(lastLocalMutationAt)
        let quietDelay = max(0, localMutationQuietInterval - elapsedSinceLocalMutation)
        scheduleRefresh(after: debounceInterval + quietDelay)
    }

    private func scheduleRefresh(after delay: TimeInterval) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            let nanoseconds = UInt64(max(0.1, delay) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await self?.refreshFromExternalChange()
        }
    }

    private func refreshFromExternalChange() async {
        MaintenanceLogStore.shared.record("vault_external_change_refresh_started", fields: [
            "root": monitoredRoot?.path
        ])
        await VaultStore.shared.refreshFromStorage()
    }
}
#endif
