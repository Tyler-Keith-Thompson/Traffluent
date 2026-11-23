#if canImport(SwiftUI)
public import Instrumentation

/// The `ServiceContext` key of the screen an event was tracked from: the name given to
/// `trackScreen(_:)`.
///
/// A destination reads it from each record's context:
///
/// ```swift
/// let screen = record.context[ScreenKey.self]  // "Checkout"
/// ```
public enum ScreenKey: ServiceContextKey {
    /// The screen's name.
    public typealias Value = String
}
#endif
