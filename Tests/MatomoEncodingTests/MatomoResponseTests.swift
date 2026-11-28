import DestinationTesting
import EventMacros
import Foundation
import HTTPDestinations
import HTTPTypes
import MatomoEncoding
import PropertyBased
import Testing
import TrackingPlans

@Suite("Matomo's 200 answers", .timeLimit(.minutes(1)))
struct MatomoResponseTests {
    @Event(name: "checkout_started")
    struct CheckoutStarted {
        var cartSize: Int
    }

    // The fixture is the answer matomo-org/matomo 6.0.0's plugins/BulkTracking/Tracker/Response.php
    // writes, {"status":"success","tracked":n,"invalid":m}, for a bulk request of one tracking
    // request that threw UnexpectedWebsiteFoundException (a site ID of no site), counted as
    // invalid by Handler.php.

    @Test("A 200 saying Matomo refused the request's one tracking request is sent once, then dropped and reported as rejected in its body")
    func allInvalidReported() async throws {
        let fixture = try #require(Bundle.module.url(forResource: "bulk-none-tracked", withExtension: "json", subdirectory: "Fixtures"))
        let body = try Data(contentsOf: fixture)
        let url = try #require(URL(string: "https://analytics.example.com/stats/"))
        let transport = ScriptedTransport([.response(.ok, body: body), .status(.badRequest)])
        let sut = try HTTPDestination.matomo(url: url, siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let batch = [EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)]
        let rejected = [EventRecord(event: CheckoutStarted(cartSize: 2), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)]
        let expected = HTTPDropReport<MatomoEncodingError>.rejectedInBody(status: .ok, reason: "Matomo refused all 1 of the request's tracking requests as invalid, as it does for a site ID of no site", recordIDs: batch.map(\.id))
        let expectedRequestCount = 2

        await sut.receive(batch)
        // Answered with 400, so its report comes next, and a missing report of the first batch
        // fails rather than waits.
        await sut.receive(rejected)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.requests.count == expectedRequestCount)
    }

    @Test("Each bulk answer to a request of 3 tracking requests means what Matomo's source says, at the boundaries of the counts, and any other body is delivered", arguments: [
        (#"{"status":"success","tracked":0,"invalid":3}"#, ResponseOutcome.rejected(reason: "Matomo refused all 3 of the request's tracking requests as invalid, as it does for a site ID of no site")),
        (#"{"status":"success","tracked":0,"invalid":4}"#, .rejected(reason: "Matomo refused all 4 of the request's tracking requests as invalid, as it does for a site ID of no site")),
        (#"{"status":"success","tracked":0,"invalid":2}"#, .transient(reason: "Matomo counted 0 tracked and 2 invalid of the request's 3 tracking requests, and skipped the rest")),
        (#"{"status":"success","tracked":0,"invalid":0}"#, .transient(reason: "Matomo counted 0 tracked and 0 invalid of the request's 3 tracking requests, and skipped the rest")),
        (#"{"status":"success","tracked":1,"invalid":1}"#, .transient(reason: "Matomo counted 1 tracked and 1 invalid of the request's 3 tracking requests, and skipped the rest")),
        (#"{"status":"success","tracked":2,"invalid":0}"#, .transient(reason: "Matomo counted 2 tracked and 0 invalid of the request's 3 tracking requests, and skipped the rest")),
        (#"{"status":"success","tracked":3,"invalid":0}"#, .delivered),
        (#"{"status":"success","tracked":1,"invalid":2}"#, .delivered),
        (#"{"status":"success","tracked":2,"invalid":1}"#, .delivered),
        (#"{"status":"success","tracked":4,"invalid":0}"#, .delivered),
        (#"{"status":"success","tracked":-1,"invalid":5}"#, .delivered),
        (#"{"status":"success","tracked":0,"invalid":-1}"#, .delivered),
        (#"{"status":"success","tracked":9223372036854775807,"invalid":9223372036854775807}"#, .delivered),
        (#"{"status":"success","tracked":0}"#, .delivered),
        (#"{"status":"success"}"#, .delivered),
        ("", .delivered),
        ("<html><body>OK</body></html>", .delivered),
    ])
    func bodies(body: String, expected: ResponseOutcome) {
        let request = EncodedRequest(body: EncodedBatch(body: Data("{}".utf8), contentType: "application/json"), recordIDs: [UUID(), UUID(), UUID()])
        let response = HTTPTransportResponse(head: HTTPResponse(status: .ok), body: Data(body.utf8))

        let actual = MatomoBatchEncoder.outcome(of: response, for: request)

        #expect(actual == expected)
    }

    @Test("A request with no tracking requests answered with both counts 0 is transient, as Matomo tracked nothing")
    func emptyRequestBothZero() {
        let request = EncodedRequest(body: EncodedBatch(body: Data("{}".utf8), contentType: "application/json"), recordIDs: [])
        let response = HTTPTransportResponse(head: HTTPResponse(status: .ok), body: Data(#"{"status":"success","tracked":0,"invalid":0}"#.utf8))
        let expected = ResponseOutcome.transient(reason: "Matomo counted 0 tracked and 0 invalid of the request's 0 tracking requests, and skipped the rest")

        let actual = MatomoBatchEncoder.outcome(of: response, for: request)

        #expect(actual == expected)
    }

    @Test("Against a model, a bulk answer is transient when its counts fall short of the request or are both 0, rejected when it tracked none, and delivered otherwise")
    func matchesModel() async {
        await propertyCheck(count: 300, input: Gen.int(in: 0 ... 25), Gen.int(in: 0 ... 25), Gen.int(in: 1 ... 20)) { tracked, invalid, sent in
            let request = EncodedRequest(body: EncodedBatch(body: Data("{}".utf8), contentType: "application/json"), recordIDs: (0 ..< sent).map { _ in UUID() })
            let body = #"{"status":"success","tracked":\#(tracked),"invalid":\#(invalid)}"#
            let response = HTTPTransportResponse(head: HTTPResponse(status: .ok), body: Data(body.utf8))
            let expected: ResponseOutcome =
                if tracked + invalid < sent || (tracked == 0 && invalid == 0) {
                    .transient(reason: "Matomo counted \(tracked) tracked and \(invalid) invalid of the request's \(sent) tracking requests, and skipped the rest")
                } else if tracked == 0 {
                    .rejected(reason: "Matomo refused all \(invalid) of the request's tracking requests as invalid, as it does for a site ID of no site")
                } else {
                    .delivered
                }

            let actual = MatomoBatchEncoder.outcome(of: response, for: request)

            #expect(actual == expected, "\(body), \(sent) sent")
        }
    }
}
