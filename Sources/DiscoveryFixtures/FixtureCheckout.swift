public import EventMacros

/// A namespace, so one of this module's events is nested in a type.
public enum FixtureCheckout {
    /// An event nested in a type, declared internal: discovered all the same.
    @Event(name: "fixture_checkout_started")
    struct Started {
        var cartSize: Int
    }
}
