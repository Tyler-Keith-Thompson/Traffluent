import EventMacros
import Foundation
import HTTPDestinations
import Instrumentation
import MatomoEncoding
import PropertyBased
import Sessions
import StandardContext
import Testing
import TrackingPlans
import TraffluentTestSupport

// Matomo's Tracking HTTP API reference (https://developer.matomo.org/api-reference/tracking-api,
// read 2026-11-27): "_id ... must be a 16 characters hexadecimal string"; uid and cid set a user
// and a forced visitor, and cip and cdt older than 24 hours need token_auth. D4: the session is
// the only identifier sent.
@Suite("MatomoBatchEncoder: identity")
struct MatomoIdentityTests {
    @Event(name: "checkout_started")
    struct CheckoutStarted {
        var cartSize: Int
    }

    @Test("A record's visitor is the last 64 bits of its session, in 16 lowercase hexadecimal digits", arguments: [
        ("01A208B7-E840-7A3E-8B4D-5C6E7F801234", "8b4d5c6e7f801234"),
        ("00000000-0000-4000-8000-00000000000C", "800000000000000c"),
        ("FFFFFFFF-FFFF-7FFF-BFFF-FFFFFFFFFFFF", "bfffffffffffffff"),
        ("00000000-0000-0000-0000-000000000000", "0000000000000000"),
    ])
    func sessionVisitor(session: String, visitor: String) throws {
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: session)!
        let record = EventRecord(id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!, event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        let expected = #"{"requests":["?idsite=1&rec=1&apiv=1&_id="# + visitor + #"&cdt=1795442607&ca=1&e_c=Shop&e_a=checkout_started"]}"#

        let actual = sut.requests(for: [record])

        let actualBodies = actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) }
        #expect(actualBodies == [expected])
    }

    @Test("A record without a session is its own visitor: the last 64 bits of its own ID")
    func sessionlessVisitor() throws {
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let record = EventRecord(id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!, event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = #"{"requests":["?idsite=1&rec=1&apiv=1&_id=b42d00c04fc964ff&cdt=1795442607&ca=1&e_c=Shop&e_a=checkout_started"]}"#

        let actual = sut.requests(for: [record])

        let actualBodies = actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) }
        #expect(actualBodies == [expected])
    }

    @Test("Records of one session share a visitor, and records of two sessions don't")
    func sessionsAreVisitors() throws {
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        var first = ServiceContext.topLevel
        first[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        var second = ServiceContext.topLevel
        second[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-9B4D-5C6E7F801234")!
        let batch = [
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: first),
            EventRecord(event: CheckoutStarted(cartSize: 2), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: first),
            EventRecord(event: CheckoutStarted(cartSize: 3), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: second),
        ]
        let expected = #"{"requests":["?idsite=1&rec=1&apiv=1&_id=8b4d5c6e7f801234&cdt=1795442607&ca=1&e_c=Shop&e_a=checkout_started","?idsite=1&rec=1&apiv=1&_id=8b4d5c6e7f801234&cdt=1795442607&ca=1&e_c=Shop&e_a=checkout_started","?idsite=1&rec=1&apiv=1&_id=9b4d5c6e7f801234&cdt=1795442607&ca=1&e_c=Shop&e_a=checkout_started"]}"#

        let actual = sut.requests(for: batch)

        let actualBodies = actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) }
        #expect(actualBodies == [expected])
    }

    @Test("A request holds exactly idsite, rec, apiv, _id, cdt, ca, e_c, e_a and lang, in that order: no uid, cid, token_auth, cip or device identifier, whatever the context holds")
    func onlyTheSession() throws {
        let sut = try MatomoBatchEncoder(siteID: 7, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        context[VendorIdentifierKey.self] = Sensitive(UUID(uuidString: "11111111-2222-3333-4444-555555555555")!)
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: "418")
        context[DeviceKey.self] = DeviceKey.Value(model: "iPhone17,1", formFactor: .phone)
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
        context[NetworkKey.self] = .wifi
        context[LocaleKey.self] = Locale(identifier: "fr_CA")
        var record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        record.revealsSensitiveValues = true
        let expected = #"{"requests":["?idsite=7&rec=1&apiv=1&_id=8b4d5c6e7f801234&cdt=1795442607&ca=1&e_c=Shop&e_a=checkout_started&lang=fr-CA"]}"#

        let actual = sut.requests(for: [record])

        let actualBodies = actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) }
        #expect(actualBodies == [expected])
    }

    @Test("Every visitor is 16 lowercase hexadecimal digits, the last 16 of the session's UUID", .tags(.randomized))
    func visitorProperty() async {
        await propertyCheck(count: 300, input: Gen.uint8().array(of: 16 ... 16)) { bytes in
            try check(bytes: bytes)
        }

        // A nested function rather than the closure's body: AGENTS.md, closures inside #expect
        // inside another closure.
        func check(bytes: [UInt8]) throws {
            let session = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
            let sut = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
            var context = ServiceContext.topLevel
            context[SessionKey.self] = session
            let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
            // The naive reference: the UUID's string, lowercased, without its hyphens, from the
            // 17th digit on.
            let visitor = String(session.uuidString.lowercased().filter { $0 != "-" }.suffix(16))
            let expected = #"{"requests":["?idsite=1&rec=1&apiv=1&_id="# + visitor + #"&cdt=1795442607&ca=1&e_c=Shop&e_a=checkout_started"]}"#

            let actual = sut.requests(for: [record])

            let actualBodies = actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) }
            #expect(actualBodies == [expected])
        }
    }
}
