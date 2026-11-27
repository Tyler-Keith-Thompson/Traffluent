import EventMacros
import Foundation
import Instrumentation
import MixpanelEncoding
import Persistence
import Sessions
import StandardContext
import Testing
import TrackingPlans

@Suite("MixpanelBatchEncoder: identity")
struct MixpanelIdentityTests {
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

    @Test("distinct_id and $device_id are the record's session, lowercase")
    func distinctIDIsTheSession() throws {
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "5D1E3B2A-9C4F-4E6A-8B7D-1F2E3D4C5B6A")!
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        let expected = "5d1e3b2a-9c4f-4e6a-8b7d-1f2e3d4c5b6a"

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        let properties = try #require(event["properties"] as? [String: Any])
        #expect(properties["distinct_id"] as? String == expected)
        #expect(properties["$device_id"] as? String == expected)
    }

    @Test("A recovered record, with no context, is sent with its own id as distinct_id and no $device_id")
    func recoveredRecord() throws {
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        // As a store remakes a record after a relaunch: no context, marked redelivered.
        let record = EventRecord(
            id: UUID(uuidString: "2B4C6D8E-1A3F-4B5C-9D7E-0F1A2B3C4D5E")!,
            event: CheckoutStarted(cartSize: 1),
            timestamp: Date(timeIntervalSince1970: 1_795_442_607),
            sourceLocation: nil,
            isRedelivered: true
        )
        let expected = #"[{"event":"checkout_started","properties":{"$insert_id":"2b4c6d8e-1a3f-4b5c-9d7e-0f1a2b3c4d5e","cartSize":1,"distinct_id":"2b4c6d8e-1a3f-4b5c-9d7e-0f1a2b3c4d5e","ip":"0","time":1795442607000,"token":"testprojecttoken"}}]"#

        let actual = sut.requests(for: [record])

        #expect(actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) } == [expected])
        #expect(actual.skippedRecords.isEmpty)
    }

    // https://developer.mixpanel.com/reference/import-events, "properties.$insert_id": at most 36
    // bytes, only alphanumeric characters or "-".
    @Test("$insert_id is the record's id in a form Mixpanel accepts: 36 bytes of lowercase hexadecimal digits and dashes")
    func insertIDFormat() throws {
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let ids = [UUID(uuidString: "FFFFFFFF-FFFF-4FFF-BFFF-FFFFFFFFFFFF")!, UUID(uuidString: "00000000-0000-4000-8000-000000000001")!]
        let batch = ids.map { EventRecord(id: $0, event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil) }
        let expected: [String?] = ["ffffffff-ffff-4fff-bfff-ffffffffffff", "00000000-0000-4000-8000-000000000001"]
        let allowed = /[0-9a-z-]{1,36}/

        let body = try #require(sut.requests(for: batch).requests.first).body.body

        let events = try #require(try JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        let actual = events.map { ($0["properties"] as? [String: Any])?["$insert_id"] as? String }
        #expect(actual == expected)
        #expect(actual.allSatisfy { ($0?.utf8.count ?? 0) <= 36 && ($0?.wholeMatch(of: allowed) != nil) })
    }

    @Test("No identifier but the session is sent: no $user_id, and not the vendor identifier, an app's account key or the trace")
    func noOtherIdentifier() throws {
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let session = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        let vendorIdentifier = UUID(uuidString: "00000000-0000-4000-8000-00000000000B")!
        let recordID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        var context = ServiceContext.topLevel
        context[SessionKey.self] = session
        context[VendorIdentifierKey.self] = Sensitive(vendorIdentifier)
        context[AccountKey.self] = Sensitive("account-42")
        context[TraceParentKey.self] = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        var record = EventRecord(id: recordID, event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        record.revealsSensitiveValues = true
        // The session, as $device_id, the record's own $insert_id, which names the event rather
        // than anyone, then the session again as distinct_id, in the order of the members' names.
        let expectedIdentifiers = [session.uuidString.lowercased(), recordID.uuidString.lowercased(), session.uuidString.lowercased()]
        let expectedKeys = ["$device_id", "$insert_id", "cartSize", "distinct_id", "ip", "time", "token"]
        let uuidPattern = /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/

        let text = String(decoding: try #require(sut.requests(for: [record]).requests.first).body.body, as: UTF8.self)

        let event = try #require((try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])?.first)
        let actual = text.matches(of: uuidPattern).map { String($0.output) }
        let actualKeys = try #require(event["properties"] as? [String: Any]).keys.sorted()
        #expect(actual == expectedIdentifiers)
        #expect(actualKeys == expectedKeys)
        #expect(event.keys.sorted() == ["event", "properties"])
        #expect(!text.contains("user_id"))
        #expect(!text.lowercased().contains(vendorIdentifier.uuidString.lowercased()))
        #expect(!text.contains("account-42"))
        #expect(!text.contains("4bf92f3577b34da6a3ce929d0e0e4736"))
    }

    @Test("Every event's ip is \"0\", so Mixpanel adds no location from the request's address, with or without a session")
    func ipZero() throws {
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
        let batch = [
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context),
            EventRecord(event: CheckoutStarted(cartSize: 2), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil),
        ]
        let expected: [String?] = ["0", "0"]

        let body = try #require(sut.requests(for: batch).requests.first).body.body

        let events = try #require(try JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        let actual = events.map { ($0["properties"] as? [String: Any])?["ip"] as? String }
        #expect(actual == expected)
    }
}
