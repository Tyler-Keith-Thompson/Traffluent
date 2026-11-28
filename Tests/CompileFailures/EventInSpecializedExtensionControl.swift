// Compiles: @Event structs in extensions that show the type is generic, by its generic arguments or
// a where clause. The macro sees it, so it leaves the discovery record out with a note, and the
// events are listed by hand where they are needed.

import EventMacros

struct Box<Value> {}

extension Box<Int> {
    @Event
    struct Opened {
        var screen: String
    }
}

extension Box where Value == String {
    @Event
    struct Closed {
        var screen: String
    }
}

let names: [String] = [Box<Int>.Opened.name, Box<String>.Closed.name]
