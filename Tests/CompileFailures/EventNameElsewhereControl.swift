// The same events without names of their own compile: each takes the name @Event declares, and a
// static member of another name in an extension or under #if is left alone.

import EventMacros

@Event
struct Opened {}

extension Opened {
    static var screen: String { "home" }
}

@Event
struct Closed {
    #if true
        static var screen: String { "home" }
    #endif
}

let names: [String] = [Opened.name, Closed.name]
