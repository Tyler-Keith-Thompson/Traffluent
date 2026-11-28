// The control for DuplicateEventNames: Orders and Shipping declare events of different names, so
// the program links, runs and discovers both.

import Events
import Orders
import Shipping

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

// Shipping's archive is read on demand: this reference brings in the member that holds its event.
let shipped = Shipping.OrderShipped.self
let names = DiscoveredEvent.all.map { $0.type.name }
guard names.contains(Orders.OrderPlaced.name), names.contains(shipped.name) else {
    print("Events discovered: \(names)")
    exit(1)
}
