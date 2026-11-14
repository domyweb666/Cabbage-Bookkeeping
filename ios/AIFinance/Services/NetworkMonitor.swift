import Foundation
import Network
import Observation

/// 有沒有網路。離線時只暫存原話，編輯、刪除、提問都先停用（規格 8.2）。
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var onChange: ((Bool) -> Void)?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.isOnline != online else { return }
                self.isOnline = online
                self.onChange?(online)
            }
        }
        monitor.start(queue: DispatchQueue(label: "network-monitor"))
    }

    /// 連線狀態改變時通知（用來在恢復連線後補送待處理的原話）。
    func observe(_ handler: @escaping (Bool) -> Void) {
        onChange = handler
    }
}
