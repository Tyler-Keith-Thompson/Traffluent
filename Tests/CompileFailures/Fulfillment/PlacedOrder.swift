import EventMacros

// An event of Orders' event's name at another version: the name alone is the key, so the two clash
// all the same.

/// An order was placed, in its second shape.
@Event(name: "OrderPlaced", version: 2)
public struct PlacedOrder {}
