// Must fail to compile: two events of one name, at different versions, in one module. The compiler
// refuses the second definition of the symbol that stands for the name.

import EventMacros

@Event(name: "order_placed")
struct OrderPlaced {}

@Event(name: "order_placed", version: 2)
struct PlacedOrder {}
