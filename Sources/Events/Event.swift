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
///
/// A store keeps an event on disk only when it is also `Codable`. Swift's synthesized
/// conformance works, as does `@Event`'s (module `EventMacros`) or one written by hand.
///
/// ```swift
/// struct SignedUp: Event, Codable {
///     var plan: String
/// }
/// ```
public protocol Event: Sendable {
    /// The name destinations record the event under. Defaults to the type's name.
    static var name: String { get }

    /// The purpose the event is collected for, whose consent decides whether it is delivered.
    /// Defaults to ``ConsentCategory/analytics``.
    static var consentCategory: ConsentCategory { get }

    /// The version of the event's shape, raised only for a change a record stored at the earlier
    /// version can't be read through: a property's type changed, a required property added
    /// without a default value, or an optional property made required. Defaults to 1.
    ///
    /// A store writes it with each record, and drops a record stored at another version than its
    /// type's now, reporting both versions. A tracking plan exports it, and its check fails on a
    /// change that needs a new version when the version stayed the same. A compatible change, an
    /// optional property or one with a default value added or a property removed, keeps it, and
    /// records stored before the change are read as they are.
    ///
    /// ```swift
    /// struct SignedUp: Event {
    ///     // Version 1's seats was an Int?, which version 2 requires.
    ///     static let schemaVersion = 2
    ///     var seats: Int
    /// }
    /// ```
    static var schemaVersion: Int { get }

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

    /// 1: the event's shape has had no change that needs a new version.
    public static var schemaVersion: Int { 1 }

    /// `nil`: no property declares a constraint.
    public func constraintViolation() -> ConstraintViolation? { nil }
}
