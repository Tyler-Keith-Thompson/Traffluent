import AptabaseEncoding
import DestinationTesting
import EventMacros
import Foundation
import HTTPDestinations
import HTTPTypes
import PropertyBased
import Testing
import TrackingPlans

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("Aptabase's 200 answers", .timeLimit(.minutes(1)))
private struct AptabaseResponseTests {
    @Event(name: "checkout_started")
    struct CheckoutStarted {
        var cartSize: Int
    }

    // The fixture is what Aptabase's server, src/Features/Ingestion/ResolveAppKeyAttribute.cs at
    // 89d36185, answers an App-Key of no app: 200 and `new { error = $"{reason} Events are not
    // being recorded." }`, the reason "Application not found with given app key: {appKey}.". A
    // request it takes is answered `{}` (EventsController.cs).

    @Test("A 200 whose body is Aptabase's error for a key of no app is sent once, then dropped and reported as rejected in its body, with Aptabase's error")
    func unknownKeyReported() async throws {
        let url = try #require(Bundle.module.url(forResource: "events-unknown-key", withExtension: "json", subdirectory: "Fixtures"))
        let body = try Data(contentsOf: url)
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let transport = ScriptedTransport([.response(.ok, body: body), .status(.badRequest)])
        let sut = try HTTPDestination.aptabase(appKey: "A-EU-1234567890", isDebug: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport, now: { tracked })
        let batch = [EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: tracked, sourceLocation: nil)]
        let rejected = [EventRecord(event: CheckoutStarted(cartSize: 2), timestamp: tracked, sourceLocation: nil)]
        let expected = HTTPDropReport<AptabaseEncodingError>.rejectedInBody(status: .ok, reason: "Application not found with given app key: A-EU-1234567890. Events are not being recorded.", recordIDs: batch.map(\.id))
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

    @Test("Each body Aptabase answers 200 with means what its server says, and any other is delivered", arguments: [
        (#"{"error":"Owner account is locked. Events are not being recorded."}"#, ResponseOutcome.rejected(reason: "Owner account is locked. Events are not being recorded.")),
        (#"{"error":""}"#, .rejected(reason: "")),
        ("{}", .delivered),
        (#"{"error":null}"#, .delivered),
        (#"{"error":1}"#, .delivered),
        (#"["error"]"#, .delivered),
        ("", .delivered),
        ("<html><body>OK</body></html>", .delivered),
    ])
    func bodies(body: String, expected: ResponseOutcome) {
        let request = EncodedRequest(body: EncodedBatch(body: Data("[]".utf8), contentType: "application/json"), recordIDs: [UUID()])
        let response = HTTPTransportResponse(head: HTTPResponse(status: .ok), body: Data(body.utf8))

        let actual = AptabaseBatchEncoder.outcome(of: response, for: request)

        #expect(actual == expected)
    }

    @Test("Against a model, a body that is an object with a string error is rejected with it, and one without is delivered")
    func matchesModel() async {
        await propertyCheck(count: 300, input: Gen.uint8().optional) { error in
            let body = error.map { #"{"error":"refused \#($0)"}"# } ?? "{}"
            let request = EncodedRequest(body: EncodedBatch(body: Data("[]".utf8), contentType: "application/json"), recordIDs: [UUID()])
            let response = HTTPTransportResponse(head: HTTPResponse(status: .ok), body: Data(body.utf8))
            let expected: ResponseOutcome = error.map { .rejected(reason: "refused \($0)") } ?? .delivered

            let actual = AptabaseBatchEncoder.outcome(of: response, for: request)

            #expect(actual == expected, "\(body)")
        }
    }
}
