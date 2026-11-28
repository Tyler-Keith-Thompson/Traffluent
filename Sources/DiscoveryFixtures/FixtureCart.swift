public import EventMacros

/// A class, so one of this module's events is nested in one: its record is a static member of the
/// class, which names the event through it.
public final class FixtureCart {
    /// An event nested in a class, declared internal: discovered all the same.
    @Event(name: "fixture_cart_emptied")
    struct Emptied {
        var itemCount: Int
    }
}
