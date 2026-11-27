import Events
import Foundation
import HTTPDestinations
import TelemetryDeckEncoding
import Testing
import TrackingPlans

@Suite("HTTPDestination.telemetryDeck and TelemetryDeckBatchEncoder: setup errors")
struct TelemetryDeckSetupErrorTests {
    @Test("The factory and the encoder throw emptyAppID for an app ID that is empty or only whitespace, and accept one with a character besides it", arguments: [
        ("", true), (" ", true), ("\n", true), (" \t\r\n ", true),
        ("a", false), (" a ", false), ("B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE\n", false),
    ])
    func emptyAppID(appID: String, throwsError: Bool) throws {
        let plan = try TrackingPlan(schemas: [])
        let expected: TelemetryDeckSetupError? = throwsError ? .emptyAppID : nil

        let actualFactory: TelemetryDeckSetupError?
        do {
            _ = try HTTPDestination.telemetryDeck(appID: appID, namespace: "com.example", testMode: false, plan: plan)
            actualFactory = nil
        } catch {
            actualFactory = error
        }
        let actualEncoder: TelemetryDeckSetupError?
        do {
            _ = try TelemetryDeckBatchEncoder(appID: appID, testMode: false, plan: plan)
            actualEncoder = nil
        } catch {
            actualEncoder = error
        }

        #expect(actualFactory == expected)
        #expect(actualEncoder == expected)
    }

    // Ingest API v3: "A namespace may only contain letters, digits, dots, underscores, and
    // hyphens" and "you cannot use `w` as a namespace"; the endpoint answers 422 for a namespace
    // holding a space. Only ASCII letters count, as for keys.
    @Test("The factory throws invalidNamespace for a namespace TelemetryDeck doesn't take, and accepts one it does", arguments: [
        ("", true), (" ", true), ("com example", true), ("com/example", true), ("com.exämple", true), ("com.example:1", true),
        ("com.example/", true), ("%41", true), ("w", true), (".", true), ("..", true), ("com.example\n", true),
        ("a", false), ("W", false), ("ww", false), ("...", false), ("-", false), ("_", false), ("0", false),
        ("com.example", false), ("Acme_Corp-2.app", false), ("com.telemetrydeck", false),
    ])
    func invalidNamespace(namespace: String, throwsError: Bool) throws {
        let plan = try TrackingPlan(schemas: [])
        let expected: TelemetryDeckSetupError? = throwsError ? .invalidNamespace : nil

        let actual: TelemetryDeckSetupError?
        do {
            _ = try HTTPDestination.telemetryDeck(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", namespace: namespace, testMode: false, plan: plan)
            actual = nil
        } catch {
            actual = error
        }

        #expect(actual == expected)
    }

    @Test("The factory checks the namespace before the app ID")
    func order() throws {
        let plan = try TrackingPlan(schemas: [])

        #expect(throws: TelemetryDeckSetupError.invalidNamespace) {
            try HTTPDestination.telemetryDeck(appID: "", namespace: "", testMode: false, plan: plan)
        }
        #expect(throws: TelemetryDeckSetupError.emptyAppID) {
            try HTTPDestination.telemetryDeck(appID: "", namespace: "com.example", testMode: false, plan: plan)
        }
    }

    @Test("A plan holding an event or property TelemetryDeck refuses or reserves still sets up: only its records are skipped")
    func planWithRefusedNames() throws {
        let refusedName = EventSchema(name: "Order Completed", version: 1, consentCategory: .analytics, properties: [])
        let reservedName = EventSchema(name: "TelemetryDeck.Session.started", version: 1, consentCategory: .analytics, properties: [])
        let reservedProperty = EventSchema(name: "rated", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: "floatValue", typeName: "Double", isOptional: false)])
        let plan = try TrackingPlan(schemas: [refusedName, reservedName, reservedProperty])

        #expect(throws: Never.self) {
            try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: plan)
        }
        #expect(throws: Never.self) {
            try HTTPDestination.telemetryDeck(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", namespace: "com.example", testMode: false, plan: plan)
        }
    }
}
