import EventMacros
import Foundation
import Instrumentation
import Persistence
import SegmentSpecEncoding
import Sessions
import StandardContext
import Testing
import TrackingPlans

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("SegmentSpecBatchEncoder: identity")
private struct SegmentSpecIdentityTests {
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

    @Test("anonymousId is the record's session, lowercase")
    func anonymousIDIsTheSession() throws {
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "5D1E3B2A-9C4F-4E6A-8B7D-1F2E3D4C5B6A")!
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        let expected = "5d1e3b2a-9c4f-4e6a-8b7d-1f2e3d4c5b6a"

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        let call = try #require(((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["batch"] as? [[String: Any]])?.first)
        #expect(call["anonymousId"] as? String == expected)
    }

    @Test("A record with no session, from a tracker without the sessions enricher, is sent with its own id as anonymousId and messageId")
    func sessionlessRecord() throws {
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        // No session in its context, and marked redelivered, as a store can hand one over.
        let record = EventRecord(
            id: UUID(uuidString: "2B4C6D8E-1A3F-4B5C-9D7E-0F1A2B3C4D5E")!,
            event: CheckoutStarted(cartSize: 1),
            timestamp: Date(timeIntervalSince1970: 1_795_442_607),
            sourceLocation: nil,
            isRedelivered: true
        )
        let expected = #"{"batch":[{"anonymousId":"2b4c6d8e-1a3f-4b5c-9d7e-0f1a2b3c4d5e","context":{"ip":"0.0.0.0"},"event":"checkout_started","messageId":"2b4c6d8e-1a3f-4b5c-9d7e-0f1a2b3c4d5e","properties":{"cartSize":1},"timestamp":"2026-11-23T14:03:27.000Z","type":"track"}]}"#

        let actual = sut.requests(for: [record])

        #expect(actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) } == [expected])
        #expect(actual.skippedRecords.isEmpty)
    }

    // Segment: "unique messageId values with fewer than 100 characters"; Customer.io: at most 191.
    @Test("messageId is the record's id: 36 lowercase hexadecimal digits and dashes, under every endpoint's limit")
    func messageIDFormat() throws {
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let ids = [UUID(uuidString: "FFFFFFFF-FFFF-4FFF-BFFF-FFFFFFFFFFFF")!, UUID(uuidString: "00000000-0000-4000-8000-000000000001")!]
        let batch = ids.map { EventRecord(id: $0, event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil) }
        let expected: [String?] = ["ffffffff-ffff-4fff-bfff-ffffffffffff", "00000000-0000-4000-8000-000000000001"]
        let allowed = /[0-9a-f-]{36}/

        let body = try #require(sut.requests(for: batch).requests.first).body.body

        let calls = try #require((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["batch"] as? [[String: Any]])
        let actual = calls.map { $0["messageId"] as? String }
        #expect(actual == expected)
        #expect(actual.allSatisfy { ($0?.wholeMatch(of: allowed)) != nil })
    }

    @Test("No identifier but the session is sent: no userId, traits or device.id, and not the vendor identifier, an app's account key or the trace")
    func noOtherIdentifier() throws {
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let session = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        let vendorIdentifier = UUID(uuidString: "00000000-0000-4000-8000-00000000000B")!
        let recordID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        var context = ServiceContext.topLevel
        context[SessionKey.self] = session
        context[VendorIdentifierKey.self] = Sensitive(vendorIdentifier)
        context[AccountKey.self] = Sensitive("account-42")
        context[TraceParentKey.self] = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        context[DeviceKey.self] = DeviceKey.Value(model: "iPhone17,1", formFactor: .phone)
        var record = EventRecord(id: recordID, event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        record.revealsSensitiveValues = true
        // The session, as anonymousId, then the record's own messageId, which names the call
        // rather than anyone, in the order of the members' names.
        let expectedIdentifiers = [session.uuidString.lowercased(), recordID.uuidString.lowercased()]
        let expectedKeys = ["anonymousId", "context", "event", "messageId", "properties", "timestamp", "type"]
        let uuidPattern = /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/

        let text = String(decoding: try #require(sut.requests(for: [record]).requests.first).body.body, as: UTF8.self)

        let call = try #require(((try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])?["batch"] as? [[String: Any]])?.first)
        let actual = text.matches(of: uuidPattern).map { String($0.output) }
        #expect(actual == expectedIdentifiers)
        #expect(call.keys.sorted() == expectedKeys)
        #expect(!text.contains("userId"))
        #expect(!text.contains("traits"))
        #expect(!text.contains("advertisingId"))
        #expect(!text.contains(#""id""#))
        #expect(!text.lowercased().contains(vendorIdentifier.uuidString.lowercased()))
        #expect(!text.contains("account-42"))
        #expect(!text.contains("4bf92f3577b34da6a3ce929d0e0e4736"))
    }

    @Test("Every call's context.ip is \"0.0.0.0\", with or without a session, and no call has context.direct")
    func ipZero() throws {
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
        let batch = [
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context),
            EventRecord(event: CheckoutStarted(cartSize: 2), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil),
        ]
        let expected: [String?] = ["0.0.0.0", "0.0.0.0"]

        let body = try #require(sut.requests(for: batch).requests.first).body.body

        let calls = try #require((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["batch"] as? [[String: Any]])
        let actual = calls.map { ($0["context"] as? [String: Any])?["ip"] as? String }
        #expect(actual == expected)
        #expect(calls.allSatisfy { ($0["context"] as? [String: Any])?["direct"] == nil })
    }
}
