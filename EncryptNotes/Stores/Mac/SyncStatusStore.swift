import Foundation
import SwiftUI
import Combine
import Network

@MainActor
final class SyncStatusStore: ObservableObject {
    static let shared = SyncStatusStore()

    @Published private(set) var status: SyncStatus = .saved
    @Published private(set) var isNetworkAvailable: Bool = true

    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.biekanwo.network-monitor")

    private init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isNetworkAvailable = path.status == .satisfied
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    func setSyncing() {
        status = .syncing
    }

    func setSaved() {
        status = .saved
    }

    func setFailed(message: String) {
        status = .failed(message: message)
    }
}
