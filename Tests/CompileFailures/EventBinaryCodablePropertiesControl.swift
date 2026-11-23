// Must compile: the macro expands and every member it generates type-checks, so the rule's search
// paths and plugin are sound.

import EventMacros

@Event
struct Tapped {
    var screen: String
    var position: [Double]
}
