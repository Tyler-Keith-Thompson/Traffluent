// The control for DuplicateEventNameInOneModule: two events of different names in one module
// compile, link and run, and the program discovers both.

import EventMacros

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

@Event(name: "order_placed")
struct OrderPlaced {}

@Event(name: "order_shipped", version: 2)
struct OrderShipped {}

let names = DiscoveredEvent.all.map { $0.type.name }
guard names.contains("order_placed"), names.contains("order_shipped") else {
    print("Events discovered: \(names)")
    exit(1)
}
