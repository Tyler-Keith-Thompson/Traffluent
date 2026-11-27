// @Event on a struct declared in a function: the compiler refuses the extension macro there, and
// that is the only error, as the macro adds no record and says nothing of its own.

import EventMacros

func open() {
    @Event
    struct Opened {
        var screen: String
    }
}
