import DestinationTesting
import EventMacros
import Foundation
import HTTPDestinations
import HTTPTypes
import MixpanelEncoding
import PropertyBased
import Testing
import TrackingPlans

@Suite("Mixpanel's 200 answers", .timeLimit(.minutes(1)))
struct MixpanelResponseTests {
    @Event(name: "checkout_started")
    struct CheckoutStarted {
        var cartSize: Int
    }

    // The fixtures are built from the reference schema; no live response recorded. The schema is
    // the verbose answer's in Mixpanel's track reference,
    // https://developer.mixpanel.com/reference/track-event (`verbose`: "two keys: `status`, with
    // the value 1 on success and 0 on failure, and `error`, with a string-valued error message if
    // the request wasn't successful"). The reference gives no example message, so the failure's
    // `error` is the reference's own placeholder for a string, `<string>`.

    @Test("A /track 200 whose verbose body is status 0 is sent once, then dropped and reported as rejected in its body, with Mixpanel's error")
    func statusZeroReported() async throws {
        let url = try #require(Bundle.module.url(forResource: "track-verbose-failure", withExtension: "json", subdirectory: "Fixtures"))
        let body = try Data(contentsOf: url)
        let transport = ScriptedTransport([.response(.ok, body: body), .status(.badRequest)])
        let sut = try HTTPDestination.mixpanel(projectToken: "testprojecttoken", region: .us, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let batch = [
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil),
            EventRecord(event: CheckoutStarted(cartSize: 2), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil),
        ]
        let rejected = [EventRecord(event: CheckoutStarted(cartSize: 3), timestamp: Date(timeIntervalSince1970: 1_795_442_609), sourceLocation: nil)]
        let expected = HTTPDropReport<MixpanelEncodingError>.rejectedInBody(status: .ok, reason: "<string>", recordIDs: batch.map(\.id))
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

    @Test("A /track 200 whose verbose body is status 1 is delivered")
    func statusOneDelivered() throws {
        let url = try #require(Bundle.module.url(forResource: "track-verbose-success", withExtension: "json", subdirectory: "Fixtures"))
        let request = EncodedRequest(body: EncodedBatch(body: Data("[]".utf8), contentType: "application/json"), recordIDs: [UUID()])
        let response = HTTPTransportResponse(head: HTTPResponse(status: .ok), body: try Data(contentsOf: url))
        let expected = ResponseOutcome.delivered

        let actual = MixpanelBatchEncoder.outcome(of: response, for: request)

        #expect(actual == expected)
    }

    @Test("Each body Mixpanel's track API answers 200 with means what its reference says, and any other is delivered", arguments: [
        (#"{"status":0,"error":"an error"}"#, ResponseOutcome.rejected(reason: "an error")),
        (#"{"status":0}"#, .rejected(reason: "No data objects in the body are valid")),
        (#"{"status":0,"error":null}"#, .rejected(reason: "No data objects in the body are valid")),
        (#"{"status":0,"error":""}"#, .rejected(reason: "No data objects in the body are valid")),
        (#"{"status":1,"error":null}"#, .delivered),
        (#"{"status":1}"#, .delivered),
        ("0", .rejected(reason: "No data objects in the body are valid")),
        ("1", .delivered),
        ("2", .delivered),
        ("-1", .delivered),
        (#"{"status":2,"error":"x"}"#, .delivered),
        (#"{"status":-1,"error":"x"}"#, .delivered),
        (#"{"status":"0","error":"x"}"#, .delivered),
        (#"{"error":"x"}"#, .delivered),
        ("", .delivered),
        ("<html><body>OK</body></html>", .delivered),
    ])
    func bodies(body: String, expected: ResponseOutcome) {
        let request = EncodedRequest(body: EncodedBatch(body: Data("[]".utf8), contentType: "application/json"), recordIDs: [UUID()])
        let response = HTTPTransportResponse(head: HTTPResponse(status: .ok), body: Data(body.utf8))

        let actual = MixpanelBatchEncoder.outcome(of: response, for: request)

        #expect(actual == expected)
    }

    @Test("Against a model of the verbose answer, status 0 is rejected with its error, or what 0 means when it has none, and every other status is delivered")
    func matchesModel() async {
        await propertyCheck(count: 300, input: Gen.int(in: -2 ... 3), Gen.uint8().optional) { status, error in
            // nil leaves the member out, 0 writes null, and any other byte an error of its digits,
            // with 1 to 9 as the empty string.
            let errorMember: String? = switch error {
            case nil: nil
            case 0?: "null"
            case let byte? where byte < 10: #""""#
            case let byte?: #""error \#(byte)""#
            }
            let body = "{\"status\":\(status)" + (errorMember.map { ",\"error\":\($0)" } ?? "") + "}"
            let request = EncodedRequest(body: EncodedBatch(body: Data("[]".utf8), contentType: "application/json"), recordIDs: [UUID()])
            let response = HTTPTransportResponse(head: HTTPResponse(status: .ok), body: Data(body.utf8))
            let expected: ResponseOutcome = switch (status, error) {
            case (0, let byte?) where byte >= 10: .rejected(reason: "error \(byte)")
            case (0, _): .rejected(reason: "No data objects in the body are valid")
            default: .delivered
            }

            let actual = MixpanelBatchEncoder.outcome(of: response, for: request)

            #expect(actual == expected, "\(body)")
        }
    }
}
