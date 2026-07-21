import Foundation
import SwiftUI
import Combine
import Network

enum SyncStatus: Equatable {
    case syncing
    case saved
    case pendingDownloads(count: Int)
    case failed(message: String)

    static func == (lhs: SyncStatus, rhs: SyncStatus) -> Bool {
        switch (lhs, rhs) {
        case (.syncing, .syncing): return true
        case (.saved, .saved): return true
        case (.pendingDownloads(let l), .pendingDownloads(let r)): return l == r
        case (.failed(let l), .failed(let r)): return l == r
        default: return false
        }
    }
}

@MainActor
final class SyncStatusStore: ObservableObject {
    static let shared = SyncStatusStore()

    @Published private(set) var status: SyncStatus = .saved
    @Published private(set) var isNetworkAvailable: Bool = true

    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.xuweinan.sealnote.network-monitor")

    private init() {
        pathMonitor.pathUpdateHandler = { path in
            let isAvailable = path.status == .satisfied
            Task { @MainActor in
                SyncStatusStore.shared.isNetworkAvailable = isAvailable
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

    func setPendingDownloads(count: Int) {
        status = .pendingDownloads(count: count)
    }

    func setFailed(message: String) {
        status = .failed(message: message)
    }
}
