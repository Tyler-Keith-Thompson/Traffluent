public import Instrumentation

/// The `ServiceContext` key of the screen an event was tracked from: the name given to
/// `trackScreen(_:)` (module `SwiftUITracking`), or to a screen tracked automatically.
///
/// A destination reads it from each record's context:
///
/// ```swift
/// let screen = record.context[ScreenKey.self]  // "Checkout"
/// ```
///
/// It builds on every platform, so a destination off Apple platforms can read it too. A store
/// keeps it beside its record, so a record recovered after a relaunch carries the screen it was
/// tracked from. The store writes it whatever set it, so don't build a screen name from user
/// data, such as an email address or a search term.
public enum ScreenKey: ServiceContextKey {
    /// The screen's name.
    public typealias Value = String
}
