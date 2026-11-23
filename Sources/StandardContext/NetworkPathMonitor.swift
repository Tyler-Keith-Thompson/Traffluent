#if canImport(Network)
import Dispatch
internal import Network
import Synchronization

/// The device's current connection, as the `NWPathMonitor` it owns reports it: started when it is
/// made, cancelled when the last enricher holding it goes.
final class NetworkPathMonitor: Sendable {
    private let monitor = NWPathMonitor()
    // A Mutex rather than an actor: a tracker's worker calls its enrichers synchronously, so it
    // can't await one. The monitor's queue writes it when the path changes, rarely, and the worker
    // reads it once per event, so the lock is held only for a copy and seldom contended.
    private let latest = Mutex<NetworkKey.Value?>(nil)

    init() {
        // Weak, so the monitor holding its handler doesn't keep this alive: its deinit cancels it.
        monitor.pathUpdateHandler = { [weak self] path in
            let connection = NetworkKey.Value(status: path.status, usesInterfaceType: path.usesInterfaceType)
            self?.latest.withLock { $0 = connection }
        }
        monitor.start(queue: DispatchQueue(label: "StandardContext.NetworkPathMonitor", qos: .utility))
    }

    deinit {
        monitor.cancel()
    }

    /// The connection of the latest path, or `nil` before the monitor reports the first.
    var connection: NetworkKey.Value? {
        latest.withLock { $0 }
    }
}
#endif
