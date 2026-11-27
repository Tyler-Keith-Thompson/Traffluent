import EventMacros
import Foundation
import HeapEncoding
import Instrumentation
import Sessions
import StandardContext
import Testing
import TrackingPlans

@Suite("HeapBatchEncoder: identity")
struct HeapIdentityTests {
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

    @Test("identity is the record's session as a lowercase UUID, and idempotency_key the record's id", arguments: [
        "01A208B7-E840-7A3E-8B4D-5C6E7F801234",
        "00000000-0000-0000-0000-000000000000",
        "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF",
    ])
    func identityIsTheSession(session: String) throws {
        let sut = try HeapBatchEncoder(appID: "12343283", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: session)!
        let record = EventRecord(id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!, event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        let expectedIdentity = session.lowercased()
        let expectedKey = "6f9619ff-8b86-d011-b42d-00c04fc964ff"

        let actual = sut.requests(for: [record])

        let body = try #require(actual.requests.first).body.body
        let request = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let event = try #require((request["events"] as? [[String: Any]])?.first)
        #expect(event["identity"] as? String == expectedIdentity)
        #expect(event["idempotency_key"] as? String == expectedKey)
    }

    @Test("Records of one session share an identity, and records of two sessions don't")
    func sessionsGroup() throws {
        let sut = try HeapBatchEncoder(appID: "12343283", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var first = ServiceContext.topLevel
        first[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        var second = ServiceContext.topLevel
        second[SessionKey.self] = UUID(uuidString: "00000000-0000-4000-8000-00000000000C")!
        let batch = [first, first, second].map { context in
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        }
        let expectedIdentities: [String?] = ["01a208b7-e840-7a3e-8b4d-5c6e7f801234", "01a208b7-e840-7a3e-8b4d-5c6e7f801234", "00000000-0000-4000-8000-00000000000c"]
        let expectedKeys: [String?] = batch.map { $0.id.uuidString.lowercased() }

        let actual = sut.requests(for: batch)

        let body = try #require(actual.requests.first).body.body
        let request = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let events = try #require(request["events"] as? [[String: Any]])
        #expect(events.map { $0["identity"] as? String } == expectedIdentities)
        #expect(events.map { $0["idempotency_key"] as? String } == expectedKeys)
    }

    @Test("Nothing but the session identifies a record: no user_id or session_id, and not its vendor identifier, revealed or not, an app's own context keys, its trace context or its standard context")
    func noOtherIdentifier() throws {
        let sut = try HeapBatchEncoder(appID: "12343283", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        context[VendorIdentifierKey.self] = Sensitive(UUID(uuidString: "00000000-0000-4000-8000-0000000000AA")!)
        context[AccountKey.self] = Sensitive("account-42")
        context[TraceParentKey.self] = "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
        context[DeviceKey.self] = DeviceKey.Value(model: "iPhone17,1", formFactor: .phone)
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: "418")
        var record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        record.revealsSensitiveValues = true
        let expectedNames: Set<String> = ["event", "identity", "idempotency_key", "properties", "timestamp"]
        let expectedProperties: Set<String> = ["cartSize"]
        let expectedRequestNames: Set<String> = ["app_id", "events"]

        let actual = sut.requests(for: [record])

        let body = try #require(actual.requests.first).body.body
        let text = String(decoding: body, as: UTF8.self)
        let request = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let event = try #require((request["events"] as? [[String: Any]])?.first)
        let properties = try #require(event["properties"] as? [String: Any])
        #expect(Set(request.keys) == expectedRequestNames)
        #expect(Set(event.keys) == expectedNames)
        #expect(Set(properties.keys) == expectedProperties)
        #expect(!text.lowercased().contains("00000000-0000-4000-8000-0000000000aa"))
        #expect(!text.contains("account-42"))
        #expect(!text.contains("0af7651916cd43dd8448eb211c80319c"))
        #expect(!text.contains("iPhone17,1"))
        #expect(!text.contains("com.example.shop"))
    }

    @Test("A recovered record, with no context, is sent as its own user, its id as both identity and idempotency_key")
    func recoveredRecord() throws {
        let sut = try HeapBatchEncoder(appID: "12343283", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        // As a store remakes a record after a relaunch: no context, marked redelivered.
        let record = EventRecord(
            id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!,
            event: CheckoutStarted(cartSize: 1),
            timestamp: Date(timeIntervalSince1970: 0),
            sourceLocation: nil,
            isRedelivered: true
        )
        let expected = #"{"app_id":"12343283","events":[{"event":"checkout_started","idempotency_key":"6f9619ff-8b86-d011-b42d-00c04fc964ff","identity":"6f9619ff-8b86-d011-b42d-00c04fc964ff","properties":{"cartSize":1},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#

        let actual = sut.requests(for: [record])

        #expect(actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) } == [expected])
        #expect(actual.skippedRecords.isEmpty)
    }
}
