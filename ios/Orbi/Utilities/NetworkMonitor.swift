import Foundation
import Network
import Combine

/// Monitors network connectivity using NWPathMonitor and publishes state changes.
/// Requirements: 14.3
@MainActor
final class NetworkMonitor: ObservableObject {

    static let shared = NetworkMonitor()

    /// Whether the device currently has network connectivity.
    @Published private(set) var isConnected: Bool = true

    /// Fires once each time connectivity is restored after being offline.
    /// APIClient subscribes to this to auto-retry queued requests.
    let connectivityRestored = PassthroughSubject<Void, Never>()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.orbi.networkmonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasConnected = self.isConnected
                let nowConnected = path.status == .satisfied
                self.isConnected = nowConnected

                // Fire restoration event when transitioning from offline → online
                if !wasConnected && nowConnected {
                    self.connectivityRestored.send()
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
