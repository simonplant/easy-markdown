import Foundation
import Network

/// Monitors network connectivity for AI download and cloud inference decisions.
/// Uses NWPathMonitor per structured concurrency conventions [A-013].
public final class NetworkMonitor: @unchecked Sendable {
    /// The current network path, updated by the monitor.
    private let currentPath: OSAllocatedUnfairLock<NWPath?>
    private let monitor: NWPathMonitor
    private let queue: DispatchQueue

    public init() {
        self.currentPath = OSAllocatedUnfairLock(initialState: nil)
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: "com.easymarkdown.emai.network")
        self.monitor.pathUpdateHandler = { [currentPath] path in
            currentPath.withLock { $0 = path }
        }
        self.monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    /// Whether any network connection is available.
    public var isConnected: Bool {
        currentPath.withLock { $0?.status == .satisfied }
    }

    /// Whether the current connection is cellular (not Wi-Fi or wired).
    public var isCellular: Bool {
        currentPath.withLock { path in
            guard let path else { return false }
            return path.usesInterfaceType(.cellular)
        }
    }

    /// Whether Wi-Fi or wired Ethernet is available.
    public var isWiFiAvailable: Bool {
        currentPath.withLock { path in
            guard let path else { return false }
            return path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
        }
    }

    /// Whether the current network is constrained (e.g., Low Data Mode).
    public var isConstrained: Bool {
        currentPath.withLock { $0?.isConstrained ?? false }
    }
}
