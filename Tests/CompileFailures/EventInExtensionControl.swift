// Must compile: the same @Event struct in an extension of a type that isn't generic, so the check
// above fails for the generic type alone.

import EventMacros

struct Shelf {}

extension Shelf {
    @Event
    struct Opened {
        var screen: String
    }
}
