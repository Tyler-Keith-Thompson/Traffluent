// The generated code names this module's types, so a file that imports EventMacros alone can
// expand the macro.
@_exported public import Events

/// Makes a struct an event: derives its `Event` and `Codable` conformances, its name and its
/// ``/Events/EventSchema`` from its declaration.
///
/// ```swift
/// import EventMacros
///
/// @Event(name: "signed_up", consent: .functional, version: 2)
/// struct SignedUp {
///     var plan: String
///     var seats: Int?
///     var email: Sensitive<String>
/// }
/// ```
///
/// The macro adds an extension holding:
///
/// - `static var name`, when `name` is given; otherwise the type's name, `Event`'s default.
/// - `static var consentCategory`, when `consent` is given; otherwise ``/Events/ConsentCategory/analytics``.
/// - `static var schemaVersion`, when `version` is given; otherwise 1, `Event`'s default.
/// - `static var schema`: an ``/Events/EventSchema`` with the event's name, version and each stored
///   property's name, type as written, optionality, whether it has a default value and validation
///   keywords (its ``/Events/Refined`` type's rule's, then those ``Constrained(_:)`` declares), in
///   declaration order.
/// - `constraintViolation()`, when a property declares constraints with ``Constrained(_:)``: the
///   first property, in declaration order, whose value breaks one, which a tracker rejects.
/// - `CodingKeys`, `encode(to:)`, `init(from:)` and the private functions it reads some types
///   through, which write a keyed container of the stored
///   properties, each under its name, and read each back by its name, as a hand-written
///   conformance would. A store writes the container as a CBOR map. An optional property's `nil`
///   is left out, and an optional property missing from the map reads as `nil`; one with a
///   default value reads as that value, so its `nil` is written. A `Date` property, optional or
///   not, and each date in a `[Date]` or `[Date?]` property, is written as the seconds since 2001
///   it stores, so it reads back exactly. A `Date` inside a `Codable` type of your own takes the
///   CBOR package's own form, seconds since 1970, and reads back to within a rounding of a
///   microsecond's scale. A
///   ``/Events/Sensitive`` property goes through its own conformance, so only a store writes its
///   value.
///
/// Every stored instance property is encoded, and needs a type annotation. Static and computed
/// properties are left out, and so is a `let` with an initial value, which every value shares.
/// The struct keeps its memberwise initializer.
///
/// A stored property whose type isn't `Codable` is a compile error naming it:
/// `static method 'requireCodable(bad:)' requires that 'Foo' conform to 'Decodable'` for a
/// property `bad` of type `Foo`. Applying the macro to anything but a struct, a property with no
/// type annotation, a `lazy` property, a destructuring pattern, a name that isn't a non-empty string
/// literal and a version that isn't a positive integer literal are compile errors too.
///
/// ## Changing an event
///
/// A store may still hold records written before an event's stored properties changed: an app
/// updates with records on disk it hasn't delivered. `version` counts the changes those records
/// can't be read through, and only those. Each record carries the version it was stored at, and a
/// store drops one stored at another version than the type's now without reading it, reporting the
/// event and both versions (`DropReport.versionMismatch`). A tracking plan's check
/// (module `TrackingPlans`) fails on a change that needs a new version while the version stayed
/// the same, naming the event, the property and the change.
///
/// These changes are compatible. Keep the version, and the records stored before the change are
/// read by each property's name, in any order:
///
/// ```swift
/// // Version 1, as released.
/// @Event(name: "checkout_started")
/// struct CheckoutStarted {
///     var cartSize: Int
///     var screen: String
/// }
///
/// // Still version 1: a record stored above reads with coupon nil, currency "USD" and screen
/// // skipped.
/// @Event(name: "checkout_started")
/// struct CheckoutStarted {
///     var cartSize: Int
///     var coupon: String?          // an optional property added: nil
///     var currency: String = "USD" // a property with a default value added: the default
///                                  // screen removed: its stored value is skipped
/// }
/// ```
///
/// These changes are breaking. Raise the version with each, and the records stored at the earlier
/// one are dropped and reported:
///
/// ```swift
/// @Event(name: "checkout_started", version: 2)
/// struct CheckoutStarted {
///     var cartSize: Double  // a property's type changed (it was Int)
///     var coupon: String    // an optional property made required (it was String?)
///     var paymentMethod: String // a required property added, with no default value
/// }
/// ```
///
/// A version raised for a change whose bytes would still read, such as a property that keeps its
/// type but changes its meaning, drops the earlier records all the same, so they are never read
/// as the new shape. Records are never migrated from one version to another.
///
/// - Parameters:
///   - name: The name destinations record the event under, a string literal; the type's name when
///     `nil`.
///   - consent: The purpose the event is collected for; ``/Events/ConsentCategory/analytics`` when `nil`.
///   - version: The schema version, `Event.schemaVersion`: a positive integer literal, raised for
///     each breaking change; 1 by default.
@attached(
    extension,
    conformances: Event, Encodable, Decodable,
    names: named(name), named(consentCategory), named(schemaVersion), named(schema), named(constraintViolation), named(CodingKeys),
    named(encode(to:)), named(init(from:)), named(decodeValue), named(decodeIfPresentValue),
    named(requireCodable), named(codableRequirements)
)
public macro Event(
    name: String? = nil,
    consent: ConsentCategory? = nil,
    version: Int = 1
) = #externalMacro(module: "EventMacrosPlugin", type: "EventMacro")

/// Declares the constraints a stored property of an `@Event` struct satisfies, which `@Event`
/// checks and lists in the event's schema.
///
/// ```swift
/// @Event
/// struct SearchPerformed {
///     @Constrained(.minLength(1), .maxLength(200))
///     var query: String
///     @Constrained(.minimum(0), .maximum(100))
///     var resultCount: Int
///     @Constrained(.pattern("^[a-z]{2}-[A-Z]{2}$", example: "en-GB"))
///     var locale: String?
///     @Constrained(.minItems(1))
///     var filters: [String]
/// }
/// ```
///
/// A tracker checks the event on its worker before anything else and rejects one whose property
/// breaks a constraint, reporting it on `Tracker.rejectionReports`. An optional property's
/// constraints apply only when it holds a value.
///
/// Each argument is a keyword written out with literals, so the macro checks it as it expands:
/// `.minLength`, `.maxLength`, `.minItems` and `.maxItems` take a non-negative integer,
/// `.minimum` and `.maximum` a number, and `.pattern` a regular expression that compiles and an
/// example it matches. A lower bound above its upper bound, or an example another keyword of the
/// property rejects, is a compile error. So is a keyword that doesn't apply to the property's
/// type: strings take the lengths and patterns, integers and floating-point numbers the bounds,
/// arrays the counts. A ``/Events/Sensitive`` property takes none, as checking it would reveal
/// it; give it a ``/Events/Refined`` value instead, whose rule its type enforces. The attribute
/// anywhere but on a stored instance property of an `@Event` struct is an error.
///
/// - Parameter constraints: The keywords, checked in order.
@attached(peer)
public macro Constrained(_ constraints: ValidationKeyword...) = #externalMacro(module: "EventMacrosPlugin", type: "ConstrainedMacro")
