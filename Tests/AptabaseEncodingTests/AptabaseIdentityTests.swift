import AptabaseEncoding
import EventMacros
import Foundation
import Instrumentation
import Sessions
import StandardContext
import Testing
import TrackingPlans

@Suite("AptabaseBatchEncoder: identity")
struct AptabaseIdentityTests {
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

    // Aptabase takes a session ID of up to 36 characters that isn't a number
    // (github.com/aptabase/aptabase at 89d36185, EventBody.ValidateSessionId, read 2026-11-27): a
    // UUID's lowercase string is 36.
    @Test("sessionId is the record's session as a lowercase UUID, 36 characters", arguments: [
        "01A208B7-E840-7A3E-8B4D-5C6E7F801234",
        "00000000-0000-0000-0000-000000000000",
        "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF",
    ])
    func sessionIdIsTheSession(session: String) throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { tracked })
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: session)!
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: tracked, sourceLocation: nil, context: context)
        let expected = session.lowercased()
        let expectedLength = 36

        let actual = sut.requests(for: [record])

        let body = try #require(actual.requests.first).body.body
        let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        let sessionId = try #require(event["sessionId"] as? String)
        #expect(sessionId == expected)
        #expect(sessionId.utf16.count == expectedLength)
    }

    @Test("Records of one session share a sessionId, and records of two sessions don't")
    func sessionsGroup() throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { tracked })
        var first = ServiceContext.topLevel
        first[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        var second = ServiceContext.topLevel
        second[SessionKey.self] = UUID(uuidString: "00000000-0000-4000-8000-00000000000C")!
        let batch = [first, first, second].map { context in
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: tracked, sourceLocation: nil, context: context)
        }
        let expected: [String?] = ["01a208b7-e840-7a3e-8b4d-5c6e7f801234", "01a208b7-e840-7a3e-8b4d-5c6e7f801234", "00000000-0000-4000-8000-00000000000c"]

        let actual = sut.requests(for: batch)

        let body = try #require(actual.requests.first).body.body
        let events = try #require(try JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        #expect(events.map { $0["sessionId"] as? String } == expected)
    }

    @Test("Nothing but the session identifies a record: not its id, its vendor identifier, revealed or not, an app's own context keys or its trace context")
    func noOtherIdentifier() throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { tracked })
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        context[VendorIdentifierKey.self] = Sensitive(UUID(uuidString: "00000000-0000-4000-8000-0000000000AA")!)
        context[AccountKey.self] = Sensitive("account-42")
        context[TraceParentKey.self] = "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: "418")
        var record = EventRecord(id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!, event: CheckoutStarted(cartSize: 1), timestamp: tracked, sourceLocation: nil, context: context)
        record.revealsSensitiveValues = true
        let expectedNames: Set<String> = ["eventName", "props", "sessionId", "systemProps", "timestamp"]
        let expectedSystemNames: Set<String> = ["appBuildNumber", "appVersion", "isDebug", "sdkVersion"]

        let actual = sut.requests(for: [record])

        let body = try #require(actual.requests.first).body.body
        let text = String(decoding: body, as: UTF8.self)
        let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        let system = try #require(event["systemProps"] as? [String: Any])
        #expect(Set(event.keys) == expectedNames)
        #expect(Set(system.keys) == expectedSystemNames)
        #expect(!text.contains("6f9619ff-8b86-d011-b42d-00c04fc964ff"))
        #expect(!text.lowercased().contains("00000000-0000-4000-8000-0000000000aa"))
        #expect(!text.contains("account-42"))
        #expect(!text.contains("0af7651916cd43dd8448eb211c80319c"))
        #expect(!text.contains("com.example.shop"))
    }

    @Test("A recovered record, with no context, is sent as a session of its own, its id as sessionId, with only isDebug and sdkVersion as systemProps")
    func recoveredRecord() throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { tracked })
        // As a store remakes a record after a relaunch: no context, marked redelivered.
        let record = EventRecord(
            id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!,
            event: CheckoutStarted(cartSize: 1),
            timestamp: tracked,
            sourceLocation: nil,
            isRedelivered: true
        )
        let expected = #"[{"eventName":"checkout_started","props":{"cartSize":1},"sessionId":"6f9619ff-8b86-d011-b42d-00c04fc964ff","systemProps":{"isDebug":false,"sdkVersion":"Traffluent"},"timestamp":"2026-11-23T14:03:27.000Z"}]"#

        let actual = sut.requests(for: [record])

        #expect(actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) } == [expected])
        #expect(actual.skippedRecords.isEmpty)
    }
}
