import Afluent
import Clocks
import DestinationTesting
import Destinations
import EventMacros
import Foundation
import HTTPDestinations
import HTTPTypes
import Instrumentation
import MixpanelEncoding
import Sessions
import Testing
import Trackers
import TrackingPlans

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("HTTPDestination.mixpanel through a tracker", .timeLimit(.minutes(1)))
private struct MixpanelDeliveryTests {
    @Event(name: "checkout_started")
    struct CheckoutStarted {
        var cartSize: Int
    }

    @Test("A tracker's batch reaches the endpoint as one request, each event's distinct_id and $device_id the session")
    func trackerToEndpoint() async throws {
        let start = Date(timeIntervalSince1970: 1_795_442_607.5)
        let transport = ScriptedTransport([.status(.ok)])
        let mixpanel = try HTTPDestination.mixpanel(projectToken: "testprojecttoken", region: .us, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let memory = InMemoryDestination()
        let tracker = Tracker(enrichers: [.sessions(kinds: [])], now: { start })
        let delivery = tracker.records.batch().deliver(to: mixpanel, memory)
        let expectedRequestCount = 1
        let expectedTime: Int64 = 1_795_442_607_500

        tracker.track(CheckoutStarted(cartSize: 1))
        tracker.track(CheckoutStarted(cartSize: 2))
        await tracker.finish()
        try await delivery.execute()

        let session = try #require(memory.records.first?.context[SessionKey.self])
        let expectedIDs: [String?] = [session.uuidString.lowercased(), session.uuidString.lowercased()]
        let expectedInsertIDs: [String?] = memory.records.map { $0.id.uuidString.lowercased() }
        let request = try #require(transport.requests.first)
        let events = try #require(try JSONSerialization.jsonObject(with: request.body) as? [[String: Any]])
        let properties = events.map { $0["properties"] as? [String: Any] }
        let actualDistinctIDs = properties.map { $0?["distinct_id"] as? String }
        let actualDeviceIDs = properties.map { $0?["$device_id"] as? String }
        let actualInsertIDs = properties.map { $0?["$insert_id"] as? String }
        let actualTimes = properties.map { ($0?["time"] as? NSNumber)?.int64Value }
        #expect(transport.requests.count == expectedRequestCount)
        #expect(actualDistinctIDs == expectedIDs)
        #expect(actualDeviceIDs == expectedIDs)
        #expect(actualInsertIDs == expectedInsertIDs)
        #expect(actualTimes == [expectedTime, expectedTime])
    }

    @Test("A request Mixpanel answers with 400, 401, 403 or 413 is sent once, then dropped and reported as rejected", arguments: [
        HTTPResponse.Status.badRequest, .unauthorized, .forbidden, .contentTooLarge,
    ])
    func rejectionDropped(status: HTTPResponse.Status) async throws {
        let transport = ScriptedTransport([.status(status), .status(.ok)])
        let sut = try HTTPDestination.mixpanel(projectToken: "testprojecttoken", region: .eu, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let batch = [EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)]
        let expected = HTTPDropReport<MixpanelEncodingError>.rejected(status: status, recordIDs: [batch[0].id])
        let expectedRequestCount = 1

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.requests.count == expectedRequestCount)
    }

    @Test("A request Mixpanel answers with 429, 502 or 503 is sent again after the backoff's wait, with the same body, until it is taken", arguments: [
        HTTPResponse.Status.tooManyRequests, .badGateway, .serviceUnavailable,
    ])
    func transientRetried(status: HTTPResponse.Status) async throws {
        let transport = ScriptedTransport([.status(status), .status(.ok)])
        let clock = TestClock()
        let sut = try HTTPDestination.mixpanel(projectToken: "testprojecttoken", region: .india, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport, backoff: try ExponentialBackoff(initialDelay: .seconds(2), maximumDelay: .seconds(60), jitter: .none), clock: clock, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let batch = [EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)]
        let expectedRequestCount = 2
        let receiving = Task { await sut.receive(batch) }

        // Mixpanel's schedule without jitter waits exactly 2 s before the first retry.
        while (try? await clock.checkSuspension()) != nil {}
        await clock.advance(by: .seconds(2))
        await receiving.value

        let bodies = transport.requests.map(\.body)
        #expect(bodies.count == expectedRequestCount)
        #expect(Set(bodies).count == 1)
    }

    @Test("Mixpanel's backoff is the one its docs recommend: a nominal 2 s doubling to 60 s, with full jitter")
    func mixpanelBackoff() throws {
        let expected = try ExponentialBackoff(initialDelay: .seconds(2), maximumDelay: .seconds(60), jitter: .full)

        let actual = ExponentialBackoff.mixpanel

        #expect(actual == expected)
    }

    @Test("A batch of events Mixpanel reserves isn't sent, and each record is reported as skipped with reservedEventName")
    func reservedBatchReported() async throws {
        struct Identify: Event, Codable {
            static let name = "$identify"
        }
        let identify = EventSchema(name: "$identify", version: 1, consentCategory: .analytics, properties: [])
        let transport = ScriptedTransport([.status(.ok)])
        let sut = try HTTPDestination.mixpanel(projectToken: "testprojecttoken", region: .us, plan: try TrackingPlan(schemas: [identify]), transport: transport, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let batch = [EventRecord(event: Identify(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)]
        let expected = HTTPDropReport<MixpanelEncodingError>.skipped(SkippedRecord(recordID: batch[0].id, eventName: "$identify", schemaVersion: 1, reason: .reservedEventName(name: "$identify")))

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.requests.isEmpty)
    }
}
