// Must not compile: an @Event struct whose name is declared where the macro can't read it, in an
// extension or under #if. The macro always declares the event's name, the one its record's unique
// key checks, so the compiler refuses the second declaration rather than let the name differ from
// the key.

import EventMacros

@Event
struct Opened {}

extension Opened {
    static var name: String { "opened" }
}

@Event
struct Closed {
    #if true
        static var name: String { "closed" }
    #endif
}
