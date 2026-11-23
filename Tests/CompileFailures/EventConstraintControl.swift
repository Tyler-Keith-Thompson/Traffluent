// Compiles: each keyword applies to its property's type, so the check above fails for the
// mismatched keyword alone and not because this rule can't build a constrained event.

import EventMacros

@Event
struct Searched {
    @Constrained(.minLength(1))
    var query: String
    @Constrained(.minimum(0))
    var resultCount: Int
}
