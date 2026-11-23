/// Something that happened, recorded as a typed value.
///
/// An event is a value type whose stored properties are its properties, so a misspelled or
/// mistyped property is a compile error rather than a bad row in a destination.
///
/// ```swift
/// struct SignedUp: Event {
///     var plan: String
/// }
/// ```
///
/// A property destinations shouldn't see unless they must, such as an email address, is a
/// ``Sensitive`` value.
public protocol Event: Sendable {
    /// The name destinations record the event under. Defaults to the type's name.
    static var name: String { get }

    /// The purpose the event is collected for, whose consent decides whether it is delivered.
    /// Defaults to ``ConsentCategory/analytics``.
    static var consentCategory: ConsentCategory { get }

    /// The first property whose value breaks a constraint declared on it, and the keyword it
    /// breaks; `nil` when every property satisfies its constraints. Defaults to `nil`.
    ///
    /// A tracker calls it on its worker for each event, before anything else, and rejects an event
    /// that returns a violation: it is never held, written or delivered, and is reported on
    /// `Tracker.rejectionReports`. `@Event` (module `EventMacros`) writes it from the constraints
    /// `@Constrained` declares beside each property. A ``Refined`` property's rule needs no check
    /// here: its value satisfied it when it was made.
    ///
    /// - Returns: The first violation, in declaration order, or `nil`.
    func constraintViolation() -> ConstraintViolation?
}

extension Event {
    /// The type's name, as written in source.
    public static var name: String { String(describing: Self.self) }

    /// ``ConsentCategory/analytics``.
    public static var consentCategory: ConsentCategory { .analytics }

    /// `nil`: no property declares a constraint.
    public func constraintViolation() -> ConstraintViolation? { nil }
}
