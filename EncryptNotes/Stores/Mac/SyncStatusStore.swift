import Foundation
import SwiftUI
import Combine
import Network

enum SyncStatus {
    case syncing
    case saved
    case failed(message: String)
}

@MainActor
final class SyncStatusStore: ObservableObject {
    static let shared = SyncStatusStore()

    @Published private(set) var status: SyncStatus = .saved
    @Published private(set) var isNetworkAvailable: Bool = true

    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.biekanwo.network-monitor")

    private init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let isAvailable = path.status == .satisfied
            Task { @MainActor in
                self?.isNetworkAvailable = isAvailable
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
