// Must not compile: minLength applies to strings, not to an Int, so @Constrained's keyword fails
// to type-check in the Constraint<Int> context @Event copies it into.

import EventMacros

@Event
struct Searched {
    @Constrained(.minLength(1))
    var resultCount: Int
}
