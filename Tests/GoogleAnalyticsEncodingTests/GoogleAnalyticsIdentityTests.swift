// The module is compiled for macOS and Linux alone (Sources/GoogleAnalyticsEncoding).
#if os(macOS) || os(Linux)
import EventMacros
import Foundation
import GoogleAnalyticsEncoding
import Instrumentation
import Persistence
import Sessions
import StandardContext
import Testing
import TrackingPlans

@Suite("GoogleAnalyticsBatchEncoder: identity")
struct GoogleAnalyticsIdentityTests {
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

    // The validation server (/debug/mp/collect, 2026-11-27) refuses a UUID's own string: "It should
    // be in <number>.<number> format". The halves are worked out by hand: 0x5D1E3B2A9C4F4E6A and
    // 0x8B7D1F2E3D4C5B6A in decimal.
    @Test("client_id is the record's session, its first and last 64 bits in decimal joined by a period")
    func clientIDIsTheSession() throws {
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "5D1E3B2A-9C4F-4E6A-8B7D-1F2E3D4C5B6A")!
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        let expected = "6709865549025726058.10051224226818186090"

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        let request = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(request["client_id"] as? String == expected)
    }

    @Test("client_id holds the UUID's every bit: the smallest and largest halves are written in full", arguments: [
        ("00000000-0000-0000-0000-000000000000", "0.0"),
        ("FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF", "18446744073709551615.18446744073709551615"),
        ("00000000-0000-0001-8000-000000000000", "1.9223372036854775808"),
    ])
    func clientIDBounds(session: String, expected: String) throws {
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: session)!
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        let request = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(request["client_id"] as? String == expected)
    }

    @Test("A recovered record, with no context, is sent with its own id as client_id, no session_id, and in a request of its own")
    func recoveredRecord() throws {
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        // As a store remakes records after a relaunch: no context, marked redelivered.
        let batch = [
            EventRecord(id: UUID(uuidString: "2B4C6D8E-1A3F-4B5C-9D7E-0F1A2B3C4D5E")!, event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, isRedelivered: true),
            EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: CheckoutStarted(cartSize: 2), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil, isRedelivered: true),
        ]
        let expected = [
            #"{"client_id":"3119989098954050396.11348524716089167198","consent":{"ad_personalization":"DENIED","ad_user_data":"DENIED"},"events":[{"name":"checkout_started","params":{"cartSize":1},"timestamp_micros":1795442607000000}]}"#,
            #"{"client_id":"16384.9223372036854775809","consent":{"ad_personalization":"DENIED","ad_user_data":"DENIED"},"events":[{"name":"checkout_started","params":{"cartSize":2},"timestamp_micros":1795442608000000}]}"#,
        ]

        let actual = sut.requests(for: batch)

        #expect(actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) } == expected)
        #expect(actual.skippedRecords.isEmpty)
    }

    @Test("Records of several sessions are sent a session to a request, in the order of each session's first record, each session's in the batch's order")
    func requestPerSession() throws {
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let sessions = [UUID(uuidString: "00000000-0000-4000-8000-00000000000B")!, UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!]
        let batch = [1, 0, 1, 0, 1].enumerated().map { index, session in
            var context = ServiceContext.topLevel
            context[SessionKey.self] = sessions[session]
            return EventRecord(event: CheckoutStarted(cartSize: index), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil, context: context)
        }
        let expectedRecordIDs = [[batch[0].id, batch[2].id, batch[4].id], [batch[1].id, batch[3].id]]
        let expectedClientIDs: [String?] = ["16384.9223372036854775818", "16384.9223372036854775819"]

        let actual = sut.requests(for: batch).requests

        let actualClientIDs = try actual.map { try (JSONSerialization.jsonObject(with: $0.body.body) as? [String: Any])?["client_id"] as? String }
        #expect(actual.map(\.recordIDs) == expectedRecordIDs)
        #expect(actualClientIDs == expectedClientIDs)
    }

    @Test("session_id is a version 7 session's start in Unix milliseconds, and is left out for a session key of another version or variant", arguments: [
        ("01A208B7-E840-7A3E-8B4D-5C6E7F801234", Int64?(1_795_442_600_000)),
        ("0190C3B2-7A5E-7C41-9A3B-5D2E8F1C0A11", 1_721_270_172_254),
        ("FFFFFFFF-FFFF-7FFF-BFFF-FFFFFFFFFFFF", 281_474_976_710_655),
        ("00000000-0000-7000-8000-000000000000", 0),
        ("01A208B7-E840-4A3E-8B4D-5C6E7F801234", nil),
        ("01A208B7-E840-8A3E-8B4D-5C6E7F801234", nil),
        ("01A208B7-E840-6A3E-8B4D-5C6E7F801234", nil),
        ("01A208B7-E840-7A3E-CB4D-5C6E7F801234", nil),
        ("01A208B7-E840-7A3E-4B4D-5C6E7F801234", nil),
    ])
    func sessionID(session: String, expected: Int64?) throws {
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: session)!
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        let request = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let params = try #require((request["events"] as? [[String: Any]])?.first?["params"] as? [String: Any])
        let actual = (params["session_id"] as? NSNumber)?.int64Value
        #expect(actual == expected)
    }

    @Test("No identifier but the session is sent: no user_id or user properties, no location, device or user agent, and not the vendor identifier, an app's account key or the trace")
    func noOtherIdentifier() throws {
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let session = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        let vendorIdentifier = UUID(uuidString: "00000000-0000-4000-8000-00000000000B")!
        let recordID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        var context = ServiceContext.topLevel
        context[SessionKey.self] = session
        context[VendorIdentifierKey.self] = Sensitive(vendorIdentifier)
        context[AccountKey.self] = Sensitive("account-42")
        context[TraceParentKey.self] = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        context[DeviceKey.self] = DeviceKey.Value(model: "iPhone17,1", formFactor: .phone)
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
        var record = EventRecord(id: recordID, event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        record.revealsSensitiveValues = true
        let expectedRequestKeys = ["client_id", "consent", "events"]
        let expectedEventKeys = ["name", "params", "timestamp_micros"]
        let expectedParamKeys = ["cartSize", "session_id"]

        let text = String(decoding: try #require(sut.requests(for: [record]).requests.first).body.body, as: UTF8.self)

        let request = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let event = try #require((request["events"] as? [[String: Any]])?.first)
        let params = try #require(event["params"] as? [String: Any])
        #expect(request.keys.sorted() == expectedRequestKeys)
        #expect(event.keys.sorted() == expectedEventKeys)
        #expect(params.keys.sorted() == expectedParamKeys)
        #expect(!text.contains("user_id"))
        #expect(!text.lowercased().contains(vendorIdentifier.uuidString.lowercased()))
        #expect(!text.lowercased().contains(recordID.uuidString.lowercased()))
        #expect(!text.contains("account-42"))
        #expect(!text.contains("4bf92f3577b34da6a3ce929d0e0e4736"))
        #expect(!text.contains("iPhone17,1"))
    }
}
#endif
