public import Instrumentation

/// The `ServiceContext` key of the network connection an event was tracked over, which
/// `Enricher.network()` sets on every record's context.
///
/// A destination reads it from each record's context:
///
/// ```swift
/// let connection = record.context[NetworkKey.self]  // .wifi
/// ```
public enum NetworkKey: ServiceContextKey {
    /// The kind of connection the device's network path uses.
    public enum Value: Hashable, Sendable, CaseIterable {
        /// Wi-Fi.
        case wifi
        /// A cellular network.
        case cellular
        /// Wired Ethernet.
        case wiredEthernet
        /// A connection of another kind, such as a VPN's or a loopback one.
        case other
        /// No connection: the path can't reach the network.
        case offline
    }
}

#if canImport(Network)
package import Network

extension NetworkKey.Value {
    /// The connection a path with `status` uses: none unless it is satisfied, then the first of
    /// Wi-Fi, cellular and wired Ethernet it uses, or another kind.
    ///
    /// - Parameters:
    ///   - status: Whether the path can reach the network.
    ///   - usesInterfaceType: Whether the path uses an interface of a type.
    package init(status: NWPath.Status, usesInterfaceType: (NWInterface.InterfaceType) -> Bool) {
        guard status == .satisfied else {
            self = .offline
            return
        }
        if usesInterfaceType(.wifi) {
            self = .wifi
        } else if usesInterfaceType(.cellular) {
            self = .cellular
        } else if usesInterfaceType(.wiredEthernet) {
            self = .wiredEthernet
        } else {
            self = .other
        }
    }
}
#endif
