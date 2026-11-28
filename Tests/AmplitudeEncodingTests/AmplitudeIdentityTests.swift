import AmplitudeEncoding
import EventMacros
import Foundation
import Instrumentation
import Persistence
import Sessions
import StandardContext
import Testing
import TrackingPlans

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("AmplitudeBatchEncoder: identity")
private struct AmplitudeIdentityTests {
    @Event(name: "checkout_started")
    struct CheckoutStarted {
        var cartSize: Int
    }

    enum AccountKey: ServiceContextKey {
        typealias Value = Sensitive<String>
    }

    enum TraceParentKey: ServiceContextKey {
        typealias Value = String
    }

    @Test("device_id is the record's session, lowercase")
    func deviceIDIsTheSession() throws {
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "5D1E3B2A-9C4F-4E6A-8B7D-1F2E3D4C5B6A")!
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expected = "5d1e3b2a-9c4f-4e6a-8b7d-1f2e3d4c5b6a"

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let event = try #require((object["events"] as? [[String: Any]])?.first)
        let actual = event["device_id"] as? String
        #expect(actual == expected)
    }

    @Test("A record with no session, from a tracker without the sessions enricher, is sent with its own id as device_id and no session_id")
    func sessionlessRecord() throws {
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        // No session in its context, and marked redelivered, as a store can hand one over.
        let record = EventRecord(
            id: UUID(uuidString: "2B4C6D8E-1A3F-4B5C-9D7E-0F1A2B3C4D5E")!,
            event: CheckoutStarted(cartSize: 1),
            timestamp: Date(timeIntervalSince1970: 0),
            sourceLocation: nil,
            isRedelivered: true
        )
        let expected = #"{"api_key":"test-api-key","events":[{"device_id":"2b4c6d8e-1a3f-4b5c-9d7e-0f1a2b3c4d5e","event_properties":{"cartSize":1},"event_type":"checkout_started","insert_id":"2b4c6d8e-1a3f-4b5c-9d7e-0f1a2b3c4d5e","time":0}]}"#

        let actual = sut.requests(for: [record])

        #expect(actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) } == [expected])
        #expect(actual.skippedRecords.isEmpty)
    }

    // SessionKey is a version 7 UUID: its first 48 bits are the session's start in Unix
    // milliseconds (RFC 9562, section 5.7), which is what Amplitude's session_id holds.
    @Test("session_id is the first 48 bits of a version 7 session, from the earliest to the latest time they hold", arguments: [
        ("01A208B7-E840-7A3E-8B4D-5C6E7F801234", Int64(1_795_442_600_000)),
        ("00000000-0000-7000-8000-000000000000", 0),
        ("00000000-0001-7FFF-BFFF-FFFFFFFFFFFF", 1),
        ("FFFFFFFF-FFFF-7000-8000-000000000000", 281_474_976_710_655),
    ])
    func sessionIDFromVersion7(session: String, expected: Int64) throws {
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let uuid = try #require(UUID(uuidString: session))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = uuid
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let event = try #require((object["events"] as? [[String: Any]])?.first)
        let actual = (event["session_id"] as? NSNumber)?.int64Value
        #expect(actual == expected)
    }

    @Test("A session of another version or variant, whose first bits are no time, has no session_id", arguments: [
        "01A208B7-E840-6A3E-8B4D-5C6E7F801234", "01A208B7-E840-8A3E-8B4D-5C6E7F801234", "01A208B7-E840-4A3E-8B4D-5C6E7F801234",
        "01A208B7-E840-7A3E-4B4D-5C6E7F801234", "01A208B7-E840-7A3E-CB4D-5C6E7F801234",
    ])
    func noSessionIDForOtherVersions(session: String) throws {
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        let uuid = try #require(UUID(uuidString: session))
        context[SessionKey.self] = uuid
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expectedDeviceID = session.lowercased()

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let event = try #require((object["events"] as? [[String: Any]])?.first)
        #expect(event["session_id"] == nil)
        #expect(event["device_id"] as? String == expectedDeviceID)
    }

    @Test("No identifier but the session is sent: no user_id, and not the vendor identifier, an app's account key or the trace")
    func noOtherIdentifier() throws {
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let session = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        let vendorIdentifier = UUID(uuidString: "00000000-0000-4000-8000-00000000000B")!
        let recordID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        var context = ServiceContext.topLevel
        context[SessionKey.self] = session
        context[VendorIdentifierKey.self] = Sensitive(vendorIdentifier)
        context[AccountKey.self] = Sensitive("account-42")
        context[TraceParentKey.self] = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        var record = EventRecord(id: recordID, event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        record.revealsSensitiveValues = true
        // The session, as device_id, and the record's own insert_id, which names the event rather
        // than anyone.
        let expectedIdentifiers = [session.uuidString.lowercased(), recordID.uuidString.lowercased()]
        let expectedTopLevelKeys = ["device_id", "event_properties", "event_type", "insert_id", "session_id", "time"]
        let uuidPattern = /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/

        let text = String(decoding: try #require(sut.requests(for: [record]).requests.first).body.body, as: UTF8.self)

        let object = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let event = try #require((object["events"] as? [[String: Any]])?.first)
        let actual = text.matches(of: uuidPattern).map { String($0.output) }
        let actualTopLevelKeys = event.keys.sorted()
        #expect(actual == expectedIdentifiers)
        #expect(actualTopLevelKeys == expectedTopLevelKeys)
        #expect(event["user_id"] == nil)
        #expect(!text.contains("user_id"))
        #expect(!text.lowercased().contains(vendorIdentifier.uuidString.lowercased()))
        #expect(!text.contains("account-42"))
        #expect(!text.contains("4bf92f3577b34da6a3ce929d0e0e4736"))
    }
}
