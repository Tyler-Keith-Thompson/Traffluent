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
///   property's name, type as written and optionality, in declaration order.
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
    names: named(name), named(consentCategory), named(schema), named(encode(to:)), named(init(from:)),
    named(requireBinaryCodable), named(binaryCodableRequirements)
)
public macro Event(
    name: String? = nil,
    consent: ConsentCategory? = nil,
    version: Int = 1
) = #externalMacro(module: "EventMacrosPlugin", type: "EventMacro")
