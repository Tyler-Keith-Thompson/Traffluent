// Must not compile: Coordinate isn't BinaryCodable, so @Event's requirement for `position` fails.

import EventMacros

struct Coordinate: Sendable {
    var latitude: Double
    var longitude: Double
}

@Event
struct Tapped {
    var screen: String
    var position: Coordinate
}
