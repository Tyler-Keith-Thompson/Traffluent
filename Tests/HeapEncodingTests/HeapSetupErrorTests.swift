import Events
import Foundation
import HeapEncoding
import HTTPDestinations
import Testing
import TrackingPlans

@Suite("HTTPDestination.heap and HeapBatchEncoder: setup errors")
struct HeapSetupErrorTests {
    @Test("The factory and the encoder throw emptyAppID for an app ID that is empty or only whitespace", arguments: [
        "", " ", "\n", " \t\r\n ",
    ])
    func emptyAppID(appID: String) throws {
        let plan = try TrackingPlan(schemas: [])
        let expected = HeapSetupError.emptyAppID

        #expect(throws: expected) {
            try HTTPDestination.heap(appID: appID, region: .us, plan: plan)
        }
        #expect(throws: expected) {
            try HeapBatchEncoder(appID: appID, plan: plan)
        }
    }

    // Heap's environment IDs are numbers ("11" and "12343283" in
    // https://developers.heap.io/reference/track-1 and /bulk-track, read 2026-11-27). The digits'
    // range is checked at both ends and just past them: '/' and ':' are the characters around
    // '0'...'9' in ASCII.
    @Test("The factory and the encoder throw malformedAppID for an app ID holding anything but ASCII digits, and accept one of digits alone", arguments: [
        ("a", true), ("12a", true), ("/", true), (":", true), ("12 34", true), ("-1", true), ("1.5", true),
        ("١٢", true), ("１２", true), ("B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", true),
        ("0", false), ("9", false), ("11", false), ("12343283", false), (" 12343283\n", false), ("0123456789", false),
    ])
    func malformedAppID(appID: String, throwsError: Bool) throws {
        let plan = try TrackingPlan(schemas: [])
        let expected: HeapSetupError? = throwsError ? .malformedAppID : nil

        let actualFactory: HeapSetupError?
        do {
            _ = try HTTPDestination.heap(appID: appID, region: .eu, plan: plan)
            actualFactory = nil
        } catch {
            actualFactory = error
        }
        let actualEncoder: HeapSetupError?
        do {
            _ = try HeapBatchEncoder(appID: appID, plan: plan)
            actualEncoder = nil
        } catch {
            actualEncoder = error
        }

        #expect(actualFactory == expected)
        #expect(actualEncoder == expected)
    }

    @Test("The app ID is sent trimmed of whitespace and newlines")
    func trimmedAppID() throws {
        let schema = EventSchema(name: "opened", version: 1, consentCategory: .analytics, properties: [])
        struct Opened: Event, Codable {
            static let name = "opened"
        }
        let sut = try HeapBatchEncoder(appID: " \t12343283\n", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: Opened(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expectedPrefix = #"{"app_id":"12343283","events":["#

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        #expect(String(decoding: body, as: UTF8.self).hasPrefix(expectedPrefix))
    }

    @Test("A plan holding an event or property Heap refuses or reserves still sets up: only its records are skipped")
    func planWithRefusedNames() throws {
        let longName = EventSchema(name: String(repeating: "e", count: 1_025), version: 1, consentCategory: .analytics, properties: [])
        let reservedProperty = EventSchema(name: "viewed", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: "screen_name", typeName: "String", isOptional: false)])
        let longProperty = EventSchema(name: "searched", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: String(repeating: "p", count: 1_024), typeName: "String", isOptional: false)])
        let plan = try TrackingPlan(schemas: [longName, reservedProperty, longProperty])

        #expect(throws: Never.self) {
            try HeapBatchEncoder(appID: "12343283", plan: plan)
        }
        #expect(throws: Never.self) {
            try HTTPDestination.heap(appID: "12343283", region: .us, plan: plan)
        }
    }
}
