import Afluent
import Clocks
import DestinationTesting
import Destinations
import EventMacros
import Foundation
import HTTPDestinations
import HTTPTypes
import MatomoEncoding
import Sessions
import Testing
import Trackers
import TrackingPlans

@Suite("HTTPDestination.matomo through a tracker", .timeLimit(.minutes(1)))
struct MatomoDeliveryTests {
    @Event(name: "checkout_started")
    struct CheckoutStarted {
        var cartSize: Int
    }

    @Test("A tracker's batch reaches matomo.php as one bulk request, every event's visitor the session's last 64 bits and its cdt the record's second")
    func trackerToEndpoint() async throws {
        let start = Date(timeIntervalSince1970: 1_795_442_607.5)
        let url = try #require(URL(string: "https://analytics.example.com/stats/"))
        let transport = ScriptedTransport([.status(.ok)])
        let matomo = try HTTPDestination.matomo(
            url: url,
            siteID: 7,
            dimensions: ["cartSize": 2],
            category: "Shop",
            plan: try TrackingPlan(schemas: [CheckoutStarted.schema]),
            transport: transport,
            now: { start }
        )
        let memory = InMemoryDestination()
        let tracker = Tracker(enrichers: [.sessions(kinds: [])], now: { start })
        let delivery = tracker.records.batch().deliver(to: matomo, memory)
        let expectedURL = "https://analytics.example.com/stats/matomo.php"
        let expectedRequestCount = 1

        tracker.track(CheckoutStarted(cartSize: 1))
        tracker.track(CheckoutStarted(cartSize: 2))
        await tracker.finish()
        try await delivery.execute()

        let session = try #require(memory.records.first?.context[SessionKey.self])
        let visitor = String(session.uuidString.lowercased().filter { $0 != "-" }.suffix(16))
        let expectedBody = #"{"requests":["?idsite=7&rec=1&apiv=1&_id="# + visitor + #"&cdt=1795442607&ca=1&e_c=Shop&e_a=checkout_started&dimension2=1","?idsite=7&rec=1&apiv=1&_id="# + visitor + #"&cdt=1795442607&ca=1&e_c=Shop&e_a=checkout_started&dimension2=2"]}"#
        let request = try #require(transport.requests.first)
        let actualURL = request.request.url?.absoluteString
        let actualBody = String(decoding: request.body, as: UTF8.self)
        let actualRequestCount = transport.requests.count
        #expect(actualRequestCount == expectedRequestCount)
        #expect(actualURL == expectedURL)
        #expect(actualBody == expectedBody)
    }

    @Test("A request answered with 400, 401, 403 or 413 is sent once, then dropped and reported as rejected", arguments: [
        HTTPResponse.Status.badRequest, .unauthorized, .forbidden, .contentTooLarge,
    ])
    func rejectionDropped(status: HTTPResponse.Status) async throws {
        let url = try #require(URL(string: "https://analytics.example.com"))
        let transport = ScriptedTransport([.status(status), .status(.ok)])
        let sut = try HTTPDestination.matomo(url: url, siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let batch = [EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)]
        let expected = HTTPDropReport<MatomoEncodingError>.rejected(status: status, recordIDs: [batch[0].id])
        let expectedRequestCount = 1

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        let actualRequestCount = transport.requests.count
        #expect(actual == expected)
        #expect(actualRequestCount == expectedRequestCount)
    }

    @Test("A request answered with 408, 429, 500 or 503 is sent again after the backoff's wait, with the same body, until it is taken", arguments: [
        HTTPResponse.Status.requestTimeout, .tooManyRequests, .internalServerError, .serviceUnavailable,
    ])
    func transientRetried(status: HTTPResponse.Status) async throws {
        let url = try #require(URL(string: "https://analytics.example.com"))
        let transport = ScriptedTransport([.status(status), .status(.ok)])
        let clock = TestClock()
        let sut = try HTTPDestination.matomo(url: url, siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport, clock: clock, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let batch = [EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)]
        let expectedRequestCount = 2
        let expectedDistinctBodies = 1
        let receiving = Task { await sut.receive(batch) }

        while (try? await clock.checkSuspension()) != nil {}
        await clock.advance(by: .seconds(1))
        await receiving.value

        let bodies = transport.requests.map(\.body)
        let actualDistinctBodies = Set(bodies).count
        #expect(bodies.count == expectedRequestCount)
        #expect(actualDistinctBodies == expectedDistinctBodies)
    }

    @Test("A record more than 23 hours older than the destination's clock isn't sent, and is reported as skipped with timestampOutsideWindow")
    func staleRecordReported() async throws {
        let url = try #require(URL(string: "https://analytics.example.com"))
        let transport = ScriptedTransport([.status(.ok)])
        let sut = try HTTPDestination.matomo(url: url, siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport, now: { Date(timeIntervalSince1970: 1_795_442_607 + 82_801) })
        let batch = [EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)]
        let expected = HTTPDropReport<MatomoEncodingError>.skipped(SkippedRecord(recordID: batch[0].id, eventName: "checkout_started", schemaVersion: 1, reason: .timestampOutsideWindow))

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.requests.isEmpty)
    }
}
