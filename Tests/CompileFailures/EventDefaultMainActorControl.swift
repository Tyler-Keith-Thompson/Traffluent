// Must compile under -default-isolation MainActor, the default for a new app target in Xcode 26:
// @Event structs declared in such a module, with every kind of member the macro generates, used
// from nonisolated code as the tracker's worker uses them. The structs themselves are main-actor
// isolated there, by the default or by their own attribute; the generated conformance and its
// members must not be.

import EventMacros
import Foundation

enum Priority: Int, Codable, CaseIterable {
    case low
    case high
}

// A type of the app's own that an event holds is nonisolated, as the event's coding reads it off
// the main actor; EventMainActorPropertyType pins the error when it isn't.
nonisolated struct Coordinate: Codable, Equatable {
    var latitude: Double
    var longitude: Double
}

// Every argument, so name, consentCategory and schemaVersion are generated; a constraint, so
// constraintViolation() is; an enum nested in the event and one outside it, for the schema's
// enumerations; dates and an array of optional dates, read through the container's own methods;
// a type of the app's own, plain and optional, read through the generated decode functions; and a
// defaulted property, read only when its key is present. Marked @MainActor as well, which the
// extension's members would take from it, so a member the macro writes outside the nonisolated
// extension fails here; the module's default doesn't reach a macro's expansion in Swift 6.4.
@MainActor
@Event(name: "checkout_started", consent: .functional, version: 2)
struct CheckoutStarted {
    enum Reason: String, Codable {
        case cart
        case buyNow = "buy_now"
    }
    @Constrained(.minLength(1))
    var plan: String
    @Constrained(.minimum(0))
    var seats: Int?
    var reason: Reason
    var priority: Priority
    var startedAt: Date
    var reminders: [Date?]
    var origin: Coordinate
    var destination: Coordinate?
    var currency: String = "USD"
}

// No properties: the empty CodingKeys and coding.
@Event(name: "app_idle")
struct AppIdle {}

// Nested in a type, whose record is a static property of that type.
enum Checkout {
    @Event(name: "checkout_viewed")
    struct Viewed {
        var screen: String
    }
}

// What the tracker's worker does with an event, from outside the main actor: its requirements,
// its schema, its coding, and its stored properties.
nonisolated func describe<Tracked: Events.__DiscoverableEvent>(_ event: Tracked) throws -> (String, Int, Bool, Tracked) {
    let name = Tracked.name
    let version = Tracked.schemaVersion
    let consent = Tracked.consentCategory
    let schema = Tracked.schema
    let violated = event.constraintViolation() != nil
    let data = try JSONEncoder().encode(event)
    let decoded = try JSONDecoder().decode(Tracked.self, from: data)
    _ = (consent, schema.properties.count)
    return (name, version, violated, decoded)
}

nonisolated func readFromWorker(_ event: CheckoutStarted) throws -> String {
    let plan = event.plan
    let origin = event.origin
    let schema = CheckoutStarted.schema
    let encoded = try JSONEncoder().encode(event)
    let decoded = try JSONDecoder().decode(CheckoutStarted.self, from: encoded)
    _ = (origin, decoded.currency, schema.version)
    return plan + CheckoutStarted.name
}

nonisolated func encodeElsewhere(_ events: [any Events.Event]) -> Int {
    events.count
}

// Handed to a concurrent function, as track(_:) hands an event to the worker.
@concurrent nonisolated func sendToWorker(_ event: CheckoutStarted, _ idle: AppIdle, _ viewed: Checkout.Viewed) async throws -> Int {
    _ = try describe(event)
    _ = try describe(idle)
    _ = try describe(viewed)
    _ = try readFromWorker(event)
    return encodeElsewhere([event, idle, viewed])
}

func track() async throws {
    let event = CheckoutStarted(plan: "pro", seats: 2, reason: .buyNow, priority: .high, startedAt: Date(), reminders: [nil], origin: Coordinate(latitude: 0, longitude: 0), destination: nil)
    _ = try await sendToWorker(event, AppIdle(), Checkout.Viewed(screen: "cart"))
}

// Main-actor isolated by its own attribute, which an extension's members take from the type it
// extends whatever the module's default.
@MainActor
@Event(name: "cart_opened")
struct CartOpened {
    var itemCount: Int
}

// Nested in a main-actor type, whose record is a static property of that type.
@MainActor
final class CartModel {
    @Event(name: "cart_closed")
    struct Closed {
        var itemCount: Int
    }
}

nonisolated func readExplicitlyIsolated(_ opened: CartOpened, _ closed: CartModel.Closed) throws -> Int {
    _ = try describe(opened)
    _ = try describe(closed)
    return opened.itemCount + closed.itemCount + CartOpened.schema.properties.count + CartModel.Closed.name.count
}
