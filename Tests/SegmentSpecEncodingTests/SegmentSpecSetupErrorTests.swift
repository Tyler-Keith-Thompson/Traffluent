import Foundation
import HTTPDestinations
import SegmentSpecEncoding
import Testing
import TrackingPlans

@Suite("HTTPDestination.segment, .rudderStack and .customerIO: setup errors")
struct SegmentSpecSetupErrorTests {
    @Test("Segment's factory throws emptyWriteKey for a key that is empty or only whitespace", arguments: ["", " ", " \n\t"])
    func segmentEmptyWriteKey(writeKey: String) throws {
        let plan = try TrackingPlan(schemas: [])

        #expect(throws: SegmentSetupError.emptyWriteKey) {
            try HTTPDestination.segment(writeKey: writeKey, region: .us, plan: plan)
        }
    }

    @Test("Segment's factory accepts a one-character write key, the shortest that isn't empty, in every region", arguments: [SegmentRegion.us, .eu])
    func segmentShortestWriteKey(region: SegmentRegion) throws {
        let plan = try TrackingPlan(schemas: [])

        #expect(throws: Never.self) {
            try HTTPDestination.segment(writeKey: "a", region: region, plan: plan)
        }
    }

    @Test("RudderStack's factory throws emptyWriteKey for a key that is empty or only whitespace, and accepts one character", arguments: [
        ("", true), (" ", true), ("\n", true), ("a", false), (" a ", false),
    ])
    func rudderStackEmptyWriteKey(writeKey: String, throwsError: Bool) throws {
        let plan = try TrackingPlan(schemas: [])
        let dataPlane = try #require(URL(string: "https://exampledataplane.rudderstack.com"))
        let expected: RudderStackSetupError? = throwsError ? .emptyWriteKey : nil

        let actual: RudderStackSetupError?
        do {
            _ = try HTTPDestination.rudderStack(writeKey: writeKey, dataPlane: dataPlane, plan: plan)
            actual = nil
        } catch {
            actual = error
        }

        #expect(actual == expected)
    }

    @Test("RudderStack's factory throws invalidDataPlane for a URL that isn't a plain https data plane, its /v1 or /batch in any case, and accepts one that is", arguments: [
        ("http://exampledataplane.rudderstack.com", true), ("http://localhost:8080", true), ("ftp://rudder.example.com", true),
        ("https://", true), ("https:///path", true), ("https://user@rudder.example.com", true), ("https://:secret@rudder.example.com", true),
        ("https://rudder.example.com?x=1", true), ("https://rudder.example.com#x", true), ("https://rudder.example.com/v1", true),
        ("https://rudder.example.com/v1/", true), ("https://rudder.example.com/v1/batch", true), ("https://rudder.example.com/batch", true),
        ("https://rudder.example.com/V1", true), ("https://rudder.example.com/v1/BATCH", true), ("https://rudder.example.com/Batch/", true),
        ("https://rudder.example.com/V1x", false), ("https://rudder.example.com/Batches", false),
        ("https://rudder.example.com", false), ("https://rudder.example.com/", false), ("https://rudder.example.com/v1x", false),
        ("https://rudder.example.com/v1/ingest", false), ("https://rudder.example.com/batches", false), ("https://localhost:8443", false),
    ])
    func rudderStackInvalidDataPlane(dataPlane: String, throwsError: Bool) throws {
        let plan = try TrackingPlan(schemas: [])
        let url = try #require(URL(string: dataPlane))
        let expected: RudderStackSetupError? = throwsError ? .invalidDataPlane : nil

        let actual: RudderStackSetupError?
        do {
            _ = try HTTPDestination.rudderStack(writeKey: "testwritekey", dataPlane: url, plan: plan)
            actual = nil
        } catch {
            actual = error
        }

        #expect(actual == expected)
    }

    @Test("Customer.io's factory throws emptyAPIKey for a key that is empty or only whitespace", arguments: ["", " ", " \n\t"])
    func customerIOEmptyAPIKey(apiKey: String) throws {
        let plan = try TrackingPlan(schemas: [])

        #expect(throws: CustomerIOSetupError.emptyAPIKey) {
            try HTTPDestination.customerIO(apiKey: apiKey, region: .us, plan: plan)
        }
    }

    // https://docs.customer.io/accounts/settings/managing-credentials/: public keys start pk_,
    // private ones sk_, then the region.
    @Test("Customer.io's factory throws privateKey for a key starting sk_, and regionMismatch for a public key of the other region", arguments: [
        ("sk_us_abc", CustomerIORegion.us, CustomerIOSetupError?.some(.privateKey)), ("sk_eu_abc", .eu, .privateKey), ("sk_", .us, .privateKey),
        ("sk_abc", .eu, .privateKey), ("pk_eu_abc", .us, .regionMismatch), ("pk_us_abc", .eu, .regionMismatch),
        ("pk_us_abc", .us, nil), ("pk_eu_abc", .eu, nil), ("pk_us_", .us, nil), ("pk_abc", .eu, nil), ("SK_us_abc", .us, nil),
        ("pk_US_abc", .eu, nil), ("a", .us, nil), (" pk_eu_abc\n", .eu, nil), (" sk_us_abc", .us, .privateKey),
    ])
    func customerIOKeys(apiKey: String, region: CustomerIORegion, expected: CustomerIOSetupError?) throws {
        let plan = try TrackingPlan(schemas: [])

        let actual: CustomerIOSetupError?
        do {
            _ = try HTTPDestination.customerIO(apiKey: apiKey, region: region, plan: plan)
            actual = nil
        } catch {
            actual = error
        }

        #expect(actual == expected)
    }
}
