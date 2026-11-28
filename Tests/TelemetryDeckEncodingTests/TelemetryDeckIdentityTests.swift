import EventMacros
import Foundation
import Instrumentation
import Sessions
import StandardContext
import TelemetryDeckEncoding
import Testing
import TrackingPlans

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("TelemetryDeckBatchEncoder: identity")
private struct TelemetryDeckIdentityTests {
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

    // TelemetryDeck's SDKs send SHA256(identifier + salt) as 64 lowercase hex digits, the salt
    // empty by default (CryptoHashing.sha256(string:salt:) in SwiftSDK 2.14.2 and 3.0.0-beta.7;
    // "User Identification",
    // https://telemetrydeck.com/docs/sdk/official-sdk/swift/swift-user-identification/). The
    // digests are `shasum -a 256` of the lowercase session; the uppercase one's, for the second
    // row, is 2662bd5f...5e2869f6, which a missing lowercasing would send.
    @Test("clientUser is the SHA256 of the record's session as a lowercase UUID, in lowercase hex, and sessionID is the session", arguments: [
        ("01A208B7-E840-7A3E-8B4D-5C6E7F801234", "b71ff296555b5b622203e19a7ce07d650113badf9c9ba1cc2fbda6b33e645344"),
        ("00000000-0000-0000-0000-00000000000C", "2834148914b1232a363c4b97e0c8cba5d3bfb4fe50e6f6058947656623ea7297"),
        ("00000000-0000-0000-0000-000000000000", "12b9377cbe7e5c94e8a70d9d23929523d14afa954793130f8a3959c7b849aca8"),
        ("FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF", "13984ab878f915021670cd855c9399ebc339676b2581855e4efd60c685f67c8e"),
    ])
    func clientUserIsTheHashedSession(session: String, expectedClientUser: String) throws {
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: session)!
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        let expectedSessionID = session.lowercased()

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        #expect(event["clientUser"] as? String == expectedClientUser)
        #expect(event["sessionID"] as? String == expectedSessionID)
    }

    @Test("A record with no session is its own user: clientUser is the SHA256 of its own id, and it has no sessionID")
    func noSession() throws {
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let record = EventRecord(id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!, event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expectedClientUser = "2a877da80e460a1379a4ac2eaf3bc12d7c0d4b0bc545618def018c28cd178813"

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        #expect(event["clientUser"] as? String == expectedClientUser)
        #expect(event["sessionID"] == nil)
    }

    @Test("Records of one session share a clientUser and a sessionID, and records of two sessions don't")
    func sessionsGroup() throws {
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var first = ServiceContext.topLevel
        first[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        var second = ServiceContext.topLevel
        second[SessionKey.self] = UUID(uuidString: "00000000-0000-4000-8000-00000000000C")!
        let batch = [first, first, second].map { context in
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        }
        let expectedClientUsers = [
            "b71ff296555b5b622203e19a7ce07d650113badf9c9ba1cc2fbda6b33e645344",
            "b71ff296555b5b622203e19a7ce07d650113badf9c9ba1cc2fbda6b33e645344",
            "613513e3d2287211cc53de9290eee17fd93f6e0d7ad5d1544225c715dc49bd67",
        ]
        let expectedSessionIDs = ["01a208b7-e840-7a3e-8b4d-5c6e7f801234", "01a208b7-e840-7a3e-8b4d-5c6e7f801234", "00000000-0000-4000-8000-00000000000c"]

        let body = try #require(sut.requests(for: batch).requests.first).body.body

        let events = try #require(try JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        #expect(events.map { $0["clientUser"] as? String } == expectedClientUsers)
        #expect(events.map { $0["sessionID"] as? String } == expectedSessionIDs)
    }

    @Test("Nothing but the session identifies a record: not its vendor identifier, revealed or not, an app's own context keys, or its trace context")
    func noOtherIdentifier() throws {
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        context[VendorIdentifierKey.self] = Sensitive(UUID(uuidString: "00000000-0000-4000-8000-0000000000AA")!)
        context[AccountKey.self] = Sensitive("account-42")
        context[TraceParentKey.self] = "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
        var record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        record.revealsSensitiveValues = true
        let expectedNames: Set<String> = ["TelemetryDeck.SDK.name", "appID", "cartSize", "clientUser", "isTestMode", "receivedAt", "sessionID", "type"]

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        let text = String(decoding: body, as: UTF8.self)
        let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        #expect(Set(event.keys) == expectedNames)
        #expect(!text.lowercased().contains("00000000-0000-4000-8000-0000000000aa"))
        #expect(!text.contains("account-42"))
        #expect(!text.contains("0af7651916cd43dd8448eb211c80319c"))
    }

    @Test("A record with no session, from a tracker without the sessions enricher, is sent as its own user, its id hashed as clientUser, with no sessionID")
    func sessionlessRecord() throws {
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        // No session in its context, and marked redelivered, as a store can hand one over.
        let record = EventRecord(
            id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!,
            event: CheckoutStarted(cartSize: 1),
            timestamp: Date(timeIntervalSince1970: 0),
            sourceLocation: nil,
            isRedelivered: true
        )
        let expected = #"[{"TelemetryDeck.SDK.name":"Traffluent","appID":"B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE","cartSize":1,"clientUser":"2a877da80e460a1379a4ac2eaf3bc12d7c0d4b0bc545618def018c28cd178813","isTestMode":"false","receivedAt":"1970-01-01T00:00:00.000Z","type":"checkout_started"}]"#

        let actual = sut.requests(for: [record])

        #expect(actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) } == [expected])
        #expect(actual.skippedRecords.isEmpty)
    }
}
