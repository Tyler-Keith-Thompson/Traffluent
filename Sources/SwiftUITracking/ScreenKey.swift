public import Instrumentation

/// The `ServiceContext` key of the screen an event was tracked from: the name given to
/// `trackScreen(_:)`.
///
/// A destination reads it from each record's context:
///
/// ```swift
/// let screen = record.context[ScreenKey.self]  // "Checkout"
/// ```
///
/// It builds on every platform, so a destination off Apple platforms can read it too.
public enum ScreenKey: ServiceContextKey {
    /// The screen's name.
    public typealias Value = String
}
