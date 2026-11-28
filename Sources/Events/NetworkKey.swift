public import Instrumentation

/// The `ServiceContext` key of the network connection an event was tracked over, which
/// `Enricher.network()` (module `StandardContext`) sets on every record's context.
///
/// A destination reads it from each record's context:
///
/// ```swift
/// let connection = record.context[NetworkKey.self]  // .wifi
/// ```
///
/// A store keeps it beside its record, so a record recovered after a relaunch carries the
/// connection it was tracked over, not the one it is uploaded over.
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
