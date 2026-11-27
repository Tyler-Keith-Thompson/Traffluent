// Must fail under -default-isolation MainActor: a struct of the app's own that an event holds takes
// the module's default isolation, so its synthesized Codable conformance is main-actor isolated,
// and the event's coding, which is nonisolated, can't use it. Marking the struct nonisolated, as
// EventDefaultMainActorControl does, fixes it.

import EventMacros

struct Coordinate: Codable {
    var latitude: Double
    var longitude: Double
}

@Event(name: "store_located")
struct StoreLocated {
    var location: Coordinate
}
