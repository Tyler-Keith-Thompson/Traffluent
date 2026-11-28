#if canImport(Network)
package import Events
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
