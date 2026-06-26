import Foundation
import SwiftUI
import Combine

enum SyncStatus: Equatable {
    case saved
    case syncing
    case failed(message: String)

    var displayText: String {
        switch self {
        case .saved: return "已保存"
        case .syncing: return "正在同步…"
        case .failed: return "同步失败"
        }
    }
}

@MainActor
final class SyncStatusStore: ObservableObject {
    static let shared = SyncStatusStore()

    @Published private(set) var status: SyncStatus = .saved

    private init() {}

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
