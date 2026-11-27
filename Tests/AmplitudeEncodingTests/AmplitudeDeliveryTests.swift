import Afluent
import AmplitudeEncoding
import DestinationTesting
import Destinations
import EventMacros
import Foundation
import HTTPDestinations
import HTTPTypes
import Instrumentation
import Sessions
import Testing
import Trackers
import TrackingPlans

@Suite("HTTPDestination.amplitude through a tracker", .timeLimit(.minutes(1)))
struct AmplitudeDeliveryTests {
    @Event(name: "checkout_started")
    struct CheckoutStarted {
        var cartSize: Int
    }

    @Test("A tracker's batch reaches the endpoint as one request, each event's device_id the session and session_id the session's start")
    func trackerToEndpoint() async throws {
        let start = Date(timeIntervalSince1970: 1_795_442_607.5)
        let transport = ScriptedTransport([.status(.ok)])
        let amplitude = try HTTPDestination.amplitude(apiKey: "test-api-key", region: .us, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport)
        let memory = InMemoryDestination()
        let tracker = Tracker(enrichers: [.sessions(kinds: [])], now: { start })
        let delivery = tracker.records.batch().deliver(to: amplitude, memory)
        let expectedRequestCount = 1
        let expectedSessionID: Int64 = 1_795_442_607_500

        tracker.track(CheckoutStarted(cartSize: 1))
        tracker.track(CheckoutStarted(cartSize: 2))
        await tracker.finish()
        try await delivery.execute()

        let session = try #require(memory.records.first?.context[SessionKey.self])
        let expectedDeviceIDs: [String?] = [session.uuidString.lowercased(), session.uuidString.lowercased()]
        let expectedInsertIDs: [String?] = memory.records.map { $0.id.uuidString.lowercased() }
        let request = try #require(transport.requests.first)
        let object = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        let events = try #require(object["events"] as? [[String: Any]])
        let actualDeviceIDs = events.map { $0["device_id"] as? String }
        let actualInsertIDs = events.map { $0["insert_id"] as? String }
        let actualSessionIDs = events.map { ($0["session_id"] as? NSNumber)?.int64Value }
        #expect(transport.requests.count == expectedRequestCount)
        #expect(actualDeviceIDs == expectedDeviceIDs)
        #expect(actualInsertIDs == expectedInsertIDs)
        #expect(actualSessionIDs == [expectedSessionID, expectedSessionID])
    }

    @Test("A request Amplitude answers with 413 or 400 is sent once, then dropped and reported as rejected", arguments: [HTTPResponse.Status.contentTooLarge, .badRequest])
    func rejectionDropped(status: HTTPResponse.Status) async throws {
        let transport = ScriptedTransport([.status(status), .status(.ok)])
        let sut = try HTTPDestination.amplitude(apiKey: "test-api-key", region: .eu, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport)
        let batch = [EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let expected = HTTPDropReport<AmplitudeEncodingError>.rejected(status: status, recordIDs: [batch[0].id])
        let expectedRequestCount = 1

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.requests.count == expectedRequestCount)
    }

    @Test("A batch of events Amplitude reserves isn't sent, and each record is reported as skipped with reservedEventName")
    func reservedBatchReported() async throws {
        struct Identify: Event, Codable {
            static let name = "$identify"
        }
        let identify = EventSchema(name: "$identify", version: 1, consentCategory: .analytics, properties: [])
        let transport = ScriptedTransport([.status(.ok)])
        let sut = try HTTPDestination.amplitude(apiKey: "test-api-key", region: .us, plan: try TrackingPlan(schemas: [identify]), transport: transport)
        let batch = [EventRecord(event: Identify(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)]
        let expected = HTTPDropReport<AmplitudeEncodingError>.skipped(SkippedRecord(recordID: batch[0].id, eventName: "$identify", schemaVersion: 1, reason: .reservedEventName(name: "$identify")))

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.requests.isEmpty)
    }
}
