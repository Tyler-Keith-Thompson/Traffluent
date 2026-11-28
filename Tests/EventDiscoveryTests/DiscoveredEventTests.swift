import AutomaticControlTracking
import DiscoveryFixtures
import EventMacros
import Events
import LifecycleTracking
import LinkerSets
import Sessions
import SwiftUITracking
import Testing

// This target's binary holds the events of its three files, DiscoveryFixtures' three (one nested
// in a class) and the library's own of the modules it links, and no two of one name.

@Event(name: "discovery_signed_up")
struct DiscoverySignedUp {
    var plan: String
}

enum DiscoveryScreens {
    @Event(name: "discovery_screen_shown", version: 3)
    struct Shown {
        var title: String
    }
}

@Event(name: "discovery_wrapped")
struct DiscoveryWrapped<Value: Codable & Sendable> {
    var value: Value
}

/// An event that conforms by hand, without `@Event`.
struct DiscoveryHandWritten: Event, Codable {
    static let name = "discovery_hand_written"
    static let schema = EventSchema(name: name, version: schemaVersion, consentCategory: consentCategory, properties: [])
}

/// An event conforming by hand whose record, in LinkerSets' section, is of another kind.
struct DiscoveryOtherKind: __DiscoverableEvent {
    static let name = "discovery_other_kind"
    static let schema = EventSchema(name: name, version: schemaVersion, consentCategory: consentCategory, properties: [])
}

// A record that holds DiscoveryOtherKind as an event's record would, but of a kind other than
// the events' ("test", not "evnt"), as another library's records in the same section are, so
// the reader must skip it.
extension DiscoveryOtherKind {
    @LinkerSetEntry(kind: 0x7465_7374)
    private static let otherKindRecord: any __DiscoverableEvent.Type = DiscoveryOtherKind.self
}

// A second record of DiscoverySignedUp, beside the one @Event gave it, as a type whose record's
// object file is linked twice would have.
extension DiscoverySignedUp {
    @LinkerSetEntry(kind: 0x6576_6E74)
    private static let repeatedRecord: any __DiscoverableEvent.Type = DiscoverySignedUp.self
}

// A record of the events' kind that holds a String, as another library that picked the same number
// would place: LinkerSet hands over only values of the type it is asked for, so all skips it, and
// everyEvent's list is the same with it.
enum DiscoveryForeignRecords {
    @LinkerSetEntry(kind: 0x6576_6E74)
    static let foreign = "x"
}

@Suite("DiscoveredEvent")
struct DiscoveredEventTests {
    @Test("all lists every @Event of every module the program links and the library's own, by the UTF-8 bytes of their names")
    func everyEvent() {
        let expected = [
            "ApplicationBackgrounded",
            "ApplicationInstalled",
            "ApplicationOpened",
            "ApplicationTerminated",
            "ApplicationUpdated",
            "ControlActivated",
            "ScreenViewed",
            "SessionEnded",
            "SessionStarted",
            "discovery_item_stored",
            "discovery_plan_viewed",
            "discovery_screen_shown",
            "discovery_signed_up",
            "fixture_cart_emptied",
            "fixture_checkout_started",
            "fixture_opened",
        ]

        let actual = DiscoveredEvent.all.map { $0.type.name }

        #expect(actual == expected)
    }

    @Test("Each discovered event carries its type's schema, its version included")
    func schemas() {
        let expected = [
            ApplicationBackgrounded.schema,
            ApplicationInstalled.schema,
            ApplicationOpened.schema,
            ApplicationTerminated.schema,
            ApplicationUpdated.schema,
            ControlActivated.schema,
            ScreenViewed.schema,
            SessionEnded.schema,
            SessionStarted.schema,
            DiscoveryItemStored.schema,
            DiscoveryPlanViewed.schema,
            DiscoveryScreens.Shown.schema,
            DiscoverySignedUp.schema,
            EventSchema(name: "fixture_cart_emptied", version: 1, consentCategory: .analytics, properties: [
                EventSchema.Property(name: "itemCount", typeName: "Int", isOptional: false),
            ]),
            EventSchema(name: "fixture_checkout_started", version: 1, consentCategory: .analytics, properties: [
                EventSchema.Property(name: "cartSize", typeName: "Int", isOptional: false),
            ]),
            EventSchema(name: "fixture_opened", version: 2, consentCategory: .analytics, properties: [
                EventSchema.Property(name: "screen", typeName: "String", isOptional: false),
            ]),
        ]

        let actual = DiscoveredEvent.all.map(\.schema)

        #expect(actual == expected)
    }

    @Test("Each discovered event's type is the type that declared it")
    func types() {
        let expected = [
            String(reflecting: DiscoverySignedUp.self),
            String(reflecting: FixtureOpened.self),
            String(reflecting: SessionStarted.self),
        ]

        let actual = DiscoveredEvent.all.map { String(reflecting: $0.type) }

        #expect(expected.allSatisfy(actual.contains))
    }

    @Test("A generic @Event and a hand-written conformance aren't discovered")
    func notDiscovered() {
        let undiscovered = [DiscoveryWrapped<Int>.name, DiscoveryHandWritten.name]

        let actual = DiscoveredEvent.all.map { $0.type.name }

        #expect(undiscovered.allSatisfy { !actual.contains($0) })
    }

    @Test("A type with two records is listed once")
    func repeatedRecordListedOnce() {
        let expectedCount = 1

        let actual = DiscoveredEvent.all.filter { ObjectIdentifier($0.type) == ObjectIdentifier(DiscoverySignedUp.self) }.count

        #expect(actual == expectedCount)
    }

    @Test("A record of another kind in the events' section is skipped")
    func otherKindSkipped() {
        let skipped = DiscoveryOtherKind.name

        let actual = DiscoveredEvent.all.map { $0.type.name }

        #expect(!actual.contains(skipped))
    }
}
