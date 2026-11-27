// Must not compile: an @Event struct declared in an extension of a generic type. The macro can't
// tell from the extension that the type it extends is generic, so it gives the struct its
// discovery record, a static stored property, which a type nested in a generic one can't hold.
// Declare the event outside the generic type, or in the generic type's own body, where the macro
// leaves the record out with a note.

import EventMacros

struct Box<Value> {}

extension Box {
    @Event
    struct Opened {
        var screen: String
    }
}
