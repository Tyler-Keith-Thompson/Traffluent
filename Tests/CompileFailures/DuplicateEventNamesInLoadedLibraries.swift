// Must build and run: Orders and Checkout, each a shared library of its own that the program opens
// with dlopen, declare an event named OrderPlaced. No linker compares two images, so both load; the
// stores and the plan refuse the name when they read the events, which is the check that covers
// separate images. The program exits 0 only when each refuses it, naming both types.

import Events
import Foundation
import Persistence
import SystemPackage
import TrackingPlans

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

func fail(_ message: String) -> Never {
    print(message)
    exit(1)
}

func load(_ path: String) {
    guard dlopen(path, RTLD_NOW) != nil else {
        fail("dlopen(\(path)) failed: \(dlerror().map { String(cString: $0) } ?? "no reason given")")
    }
}

func placedOrders() -> [String] {
    DiscoveredEvent.all.filter { $0.type.name == "OrderPlaced" }.map { String(reflecting: $0.type) }
}

let libraries = Array(CommandLine.arguments.dropFirst())
guard libraries.count == 2 else { fail("Expected two libraries, not \(libraries)") }
let directory = FilePath(NSTemporaryDirectory()).appending("DuplicateEventNamesInLoadedLibraries-\(UUID().uuidString)")

// One library: its event is found, and a store and a plan of every discovered event open.
load(libraries[0])
guard placedOrders().count == 1 else { fail("Events named OrderPlaced after one library: \(placedOrders())") }
do throws(SegmentStoreError) {
    _ = try SegmentStore(directory: directory)
} catch {
    fail("SegmentStore() with one library threw \(error)")
}
do throws(TrackingPlanError) {
    _ = try TrackingPlan()
} catch {
    fail("TrackingPlan() with one library threw \(error)")
}

// Both libraries: two types of one name, which the stores and the plan refuse.
load(libraries[1])
let expected = ["Checkout.OrderPlaced", "Orders.OrderPlaced"]
guard placedOrders() == expected else { fail("Events named OrderPlaced after both libraries: \(placedOrders())") }
do throws(SegmentStoreError) {
    _ = try SegmentStore(directory: directory)
    fail("SegmentStore() opened with two events named OrderPlaced")
} catch .duplicateEventName(let name, let firstType, let secondType) {
    guard [name, firstType, secondType] == ["OrderPlaced"] + expected else {
        fail("SegmentStore() threw duplicateEventName(\(name), \(firstType), \(secondType))")
    }
} catch {
    fail("SegmentStore() threw \(error)")
}
do throws(TrackingPlanError) {
    _ = try TrackingPlan()
    fail("TrackingPlan() accepted two events named OrderPlaced")
} catch .duplicateEvent(let name, let version, let firstType, let secondType) {
    guard name == "OrderPlaced", version == 1, firstType == expected[0], secondType == expected[1] else {
        fail("TrackingPlan() threw duplicateEvent(\(name), \(version), \(String(describing: firstType)), \(String(describing: secondType)))")
    }
} catch {
    fail("TrackingPlan() threw \(error)")
}
try? FileManager.default.removeItem(atPath: directory.string)
