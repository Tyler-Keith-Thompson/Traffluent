/// A property value that a destination reads only through the record it arrived in, and not at all
/// once the record is redacted.
///
/// Mark an event's personal or secret properties sensitive by giving them this type:
///
/// ```swift
/// struct SignedUp: Event {
///     var plan: String
///     var email: Sensitive<String>
/// }
///
/// tracker.track(SignedUp(plan: "pro", email: Sensitive("ada@example.com")))
/// ```
///
/// The value has no public accessor. A destination that needs it asks the record for it with
/// `EventRecord.reveal(_:)`, which answers `nil` for a record a delivery redacted
/// (`redactingSensitiveValues()` on the destination). Printing, interpolating, dumping or mirroring
/// the value shows `<redacted>`, so a destination that writes events out as text never writes it.
///
/// It isn't `Equatable`: comparing it with a guess would reveal it.
public struct Sensitive<Value: Sendable>: Sendable {
    /// The value, for the library's own encodings (a store's, say); destinations go through
    /// `EventRecord.reveal(_:)`.
    package let value: Value

    /// `value`, marked sensitive.
    ///
    /// - Parameter value: The sensitive value.
    public init(_ value: Value) {
        self.value = value
    }
}

extension Sensitive: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// `<redacted>`, whatever the value.
    public var description: String {
        "<redacted>"
    }

    /// `Sensitive(<redacted>)`, whatever the value.
    public var debugDescription: String {
        "Sensitive(<redacted>)"
    }

    /// A mirror with no children, so `dump` and reflection never reach the value.
    public var customMirror: Mirror {
        Mirror(self, children: [], displayStyle: .struct)
    }
}
