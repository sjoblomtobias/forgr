import Foundation
import Combine
import Network

/// Tracks whether the device currently has a usable network path (Wi-Fi/cellular).
/// `nil` means no reading has come in yet (used by the launch splash gate to wait
/// for a definitive answer instead of assuming either way).
@MainActor
final class NetworkMonitor: ObservableObject, @unchecked Sendable {
    @Published private(set) var isConnected: Bool?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let connected = path.status == .satisfied
            Task { @MainActor in
                self.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
