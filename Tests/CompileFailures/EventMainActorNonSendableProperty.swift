// Must fail: a struct marked @MainActor holds a stored property of a type that isn't Sendable.
// Nonisolated code, which the event's coding and schema are, may read a main-actor struct's stored
// property only when its type is Sendable, so the expansion can't reach it.

import EventMacros

final class Box: Codable {
    var value = 0
}

@MainActor
@Event(name: "box_opened")
struct BoxOpened {
    var box: Box
}
