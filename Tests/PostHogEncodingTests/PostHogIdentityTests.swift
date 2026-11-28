import EventMacros
import Foundation
import Instrumentation
import Persistence
import PostHogEncoding
import Sessions
import StandardContext
import Testing
import TrackingPlans

@Suite("PostHogBatchEncoder: identity")
struct PostHogIdentityTests {
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

    /// Writes the names PostHog reads as identity and settings, which no `@Event` property can be.
    struct ClaimsAnIdentity: Event, Encodable {
        static let name = "claims_an_identity"

        enum Key: String, CodingKey {
            case processPersonProfile = "$process_person_profile"
            case geoIPDisable = "$geoip_disable"
            case sessionID = "$session_id"
            case distinctID = "distinct_id"
            case set = "$set"
            case count
        }

        init() {}

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            try container.encode(true, forKey: .processPersonProfile)
            try container.encode(false, forKey: .geoIPDisable)
            try container.encode("someone-else", forKey: .sessionID)
            try container.encode("someone-else", forKey: .distinctID)
            try container.encode("ada@example.com", forKey: .set)
            try container.encode(1, forKey: .count)
        }
    }

    @Test("distinct_id is the record's session, lowercase, and $session_id the same session")
    func distinctIDIsTheSession() throws {
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "5D1E3B2A-9C4F-4E6A-8B7D-1F2E3D4C5B6A")!
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expected = "5d1e3b2a-9c4f-4e6a-8b7d-1f2e3d4c5b6a"

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let event = try #require((object["batch"] as? [[String: Any]])?.first)
        let properties = try #require(event["properties"] as? [String: Any])
        let actual = event["distinct_id"] as? String
        let actualSessionID = properties["$session_id"] as? String
        #expect(actual == expected)
        #expect(actualSessionID == expected)
    }

    @Test("A record with no session, from a tracker without the sessions enricher, is sent with its own id as distinct_id and no $session_id")
    func sessionlessRecord() throws {
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        // No session in its context, and marked redelivered, as a store can hand one over.
        let record = EventRecord(
            id: UUID(uuidString: "2B4C6D8E-1A3F-4B5C-9D7E-0F1A2B3C4D5E")!,
            event: CheckoutStarted(cartSize: 1),
            timestamp: Date(timeIntervalSince1970: 0),
            sourceLocation: nil,
            isRedelivered: true
        )
        let expected = #"{"api_key":"phc_test","batch":[{"distinct_id":"2b4c6d8e-1a3f-4b5c-9d7e-0f1a2b3c4d5e","event":"checkout_started","properties":{"$geoip_disable":true,"$process_person_profile":false,"cartSize":1},"timestamp":"1970-01-01T00:00:00.000Z","uuid":"2b4c6d8e-1a3f-4b5c-9d7e-0f1a2b3c4d5e"}]}"#

        let actual = sut.requests(for: [record])

        #expect(actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) } == [expected])
        #expect(actual.skippedRecords.isEmpty)
    }

    @Test("Every event is anonymous and without GeoIP: $process_person_profile false and $geoip_disable true")
    func anonymous() throws {
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let properties = try #require((object["batch"] as? [[String: Any]])?.first?["properties"] as? [String: Any])
        let actualPersonProfile = properties["$process_person_profile"] as? Bool
        let actualGeoIPDisable = properties["$geoip_disable"] as? Bool
        #expect(actualPersonProfile == false)
        #expect(actualGeoIPDisable == true)
    }

    @Test("No identifier but the session is sent: not the vendor identifier, an app's account key or the trace")
    func noOtherIdentifier() throws {
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let session = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
        let vendorIdentifier = UUID(uuidString: "00000000-0000-4000-8000-00000000000B")!
        let recordID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        var context = ServiceContext.topLevel
        context[SessionKey.self] = session
        context[VendorIdentifierKey.self] = Sensitive(vendorIdentifier)
        context[AccountKey.self] = Sensitive("account-42")
        context[TraceParentKey.self] = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        var record = EventRecord(id: recordID, event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        record.revealsSensitiveValues = true
        // The session, as distinct_id and as $session_id, and the record's own uuid, which names the
        // event rather than anyone.
        let expectedIdentifiers = [session.uuidString.lowercased(), session.uuidString.lowercased(), recordID.uuidString.lowercased()]
        let expectedTopLevelKeys = ["distinct_id", "event", "properties", "timestamp", "uuid"]
        let uuidPattern = /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/

        let text = String(decoding: try #require(sut.requests(for: [record]).requests.first).body.body, as: UTF8.self)

        let object = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let event = try #require((object["batch"] as? [[String: Any]])?.first)
        let actual = text.matches(of: uuidPattern).map { String($0.output) }
        let actualTopLevelKeys = event.keys.sorted()
        #expect(actual == expectedIdentifiers)
        #expect(actualTopLevelKeys == expectedTopLevelKeys)
        #expect(!text.lowercased().contains(vendorIdentifier.uuidString.lowercased()))
        #expect(!text.contains("account-42"))
        #expect(!text.contains("4bf92f3577b34da6a3ce929d0e0e4736"))
    }

    @Test("An event's $-prefixed and distinct_id properties are left out, so it can't change the identity or the forced settings")
    func dollarPropertiesDropped() throws {
        let schema = EventSchema(name: "claims_an_identity", version: 1, consentCategory: .analytics, properties: [])
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [schema]))
        let session = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
        var context = ServiceContext.topLevel
        context[SessionKey.self] = session
        let record = EventRecord(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            event: ClaimsAnIdentity(),
            timestamp: Date(timeIntervalSince1970: 0),
            sourceLocation: nil,
            context: context
        )
        let expected = #"{"api_key":"phc_test","batch":[{"distinct_id":"00000000-0000-4000-8000-00000000000a","event":"claims_an_identity","properties":{"$geoip_disable":true,"$process_person_profile":false,"$session_id":"00000000-0000-4000-8000-00000000000a","count":1},"timestamp":"1970-01-01T00:00:00.000Z","uuid":"00000000-0000-4000-8000-000000000001"}]}"#

        let actual = try #require(sut.requests(for: [record]).requests.first).body

        #expect(String(decoding: actual.body, as: UTF8.self) == expected)
    }
}
