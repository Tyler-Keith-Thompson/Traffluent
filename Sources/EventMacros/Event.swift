// The generated code names these modules' types, so a file that imports EventMacros alone can
// expand the macro.
@_exported public import Events
@_exported public import Persistence

/// Makes a struct an event: derives its `Event` and `BinaryCodable` conformances, its name and its
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
/// - `static var schema`: an ``/Events/EventSchema`` with the event's name, `version` and each stored
///   property's name, type as written, optionality and validation keywords (its
///   ``/Events/Refined`` type's rule's, then those ``Constrained(_:)`` declares), in declaration
///   order.
/// - `constraintViolation()`, when a property declares constraints with ``Constrained(_:)``: the
///   first property, in declaration order, whose value breaks one, which a tracker rejects.
/// - `encode(to:)` and `init(from:)`, which write and read each stored property in declaration
///   order, as a hand-written conformance would. A ``/Events/Sensitive`` property goes through its
///   own conformance, so only a store's encoder writes its value.
///
/// Every stored instance property is encoded, and needs a type annotation. Static and computed
/// properties are left out, and so is a `let` with an initial value, which every value shares.
/// The struct keeps its memberwise initializer.
///
/// A stored property whose type isn't `BinaryCodable` is a compile error naming it:
/// `static method 'requireBinaryCodable(bad:)' requires that 'Foo' conform to 'BinaryCodable'` for
/// a property `bad` of type `Foo`. Applying the macro to anything but a struct, a property with no
/// type annotation, a `lazy` property, a destructuring pattern, a name that isn't a non-empty string
/// literal and a version that isn't a positive integer literal are compile errors too.
///
/// Changing an event's stored properties changes its binary format, which records a store holds
/// may still be in: add a new event type, or raise `version` and give the new shape a new `name`.
///
/// - Parameters:
///   - name: The name destinations record the event under, a string literal; the type's name when
///     `nil`.
///   - consent: The purpose the event is collected for; ``/Events/ConsentCategory/analytics`` when `nil`.
///   - version: The schema version, a positive integer literal; 1 by default.
@attached(
    extension,
    conformances: Event, BinaryCodable,
    names: named(name), named(consentCategory), named(schema), named(constraintViolation), named(encode(to:)),
    named(init(from:)), named(requireBinaryCodable), named(binaryCodableRequirements)
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
