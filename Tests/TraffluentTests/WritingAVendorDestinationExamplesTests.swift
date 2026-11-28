// The examples of the "Writing a Vendor Destination" article
// (Sources/Traffluent/Traffluent.docc/WritingAVendorDestination.md), verbatim, so the article
// cannot drift from the code. The encoder and the factory are at file scope, as a vendor module
// declares them.

import DestinationTesting
import EventMacros
import Foundation
import Instrumentation
import HTTPDestinations
import JSONValues
import PropertyJSON
import Testing
import TrackingPlans
import Traffluent

/// Why the Acme encoder left a record out.
enum AcmeEncodingError: Error, Hashable {
    case unreadable(PropertyReadingError)
    case contextKeyCollision(key: String)
    case unrepresentableTimestamp
    case oversized(byteCount: Int)
}

struct AcmeBatchEncoder: BatchEncoder {
    /// Acme's limits on one request.
    static let batchLimit = (try? BatchLimit(maximumRecordCount: 500, maximumByteCount: 1_000_000, maximumRecordByteCount: 32_000)) ?? .unlimited

    typealias Failure = AcmeEncodingError

    private let reader: PropertyReader
    private let envelope: JSONEnvelope

    init(apiKey: String, plan: TrackingPlan) {
        reader = PropertyReader(plan: plan)
        envelope = JSONEnvelope(["api_key": .string(apiKey)], arrayMember: "events")
    }

    func requests(for batch: [EventRecord]) -> BatchRequests<AcmeEncodingError> {
        Self.batchLimit.requests(for: batch, in: envelope) { record throws(AcmeEncodingError) in
            try json(of: record)
        } oversized: { byteCount in
            .oversized(byteCount: byteCount)
        }
    }

    private func json(of record: EventRecord) throws(AcmeEncodingError) -> JSON {
        let properties: [String: JSON]
        do {
            properties = try reader.properties(of: record, includingSensitiveValues: false)
        } catch {
            throw .unreadable(error)
        }
        let context: [String: JSON]
        do {
            context = try record.standardContext.flattened()
        } catch {
            throw .contextKeyCollision(key: error.key)
        }
        let time: Int64
        do {
            time = try record.timestamp.millisecondsSince1970()
        } catch {
            throw .unrepresentableTimestamp
        }
        return .object([
            "event": .string(record.name),
            "user_id": .string(record.pseudonymousIdentity.uuid.uuidString.lowercased()),
            "insert_id": .string(record.deduplicationID),
            "time": .integer(time),
            "properties": .object(properties),
            "context": .object(context),
        ])
    }
}

extension AcmeBatchEncoder {
    /// Acme answers 425 Too Early while a new region starts up, and takes the request later.
    static let transientStatuses: Set<TransientStatus> = (try? TransientStatus(425)).map { [$0] } ?? []
}

extension AcmeBatchEncoder {
    private struct Answer: Decodable {
        let accepted: Bool
        let error: String?
    }

    // Acme's ingestion reference answers 200 with {"accepted": false, "error": "..."} for an
    // unknown API key, and {"accepted": true} for a request it stored.
    static func outcome(of response: HTTPTransportResponse, for request: EncodedRequest) -> ResponseOutcome {
        guard let answer = try? JSONDecoder().decode(Answer.self, from: response.body), !answer.accepted else {
            return .delivered
        }
        return .rejected(reason: answer.error ?? "Acme accepted none of the request")
    }
}

/// Sends what Acme's encoder sends, leaving out the records `isSent` refuses.
struct FilteredAcmeEncoder: BatchEncoder {
    typealias Failure = AcmeEncodingError

    static var transientStatuses: Set<TransientStatus> { AcmeBatchEncoder.transientStatuses }

    let inner: AcmeBatchEncoder
    let isSent: @Sendable (EventRecord) -> Bool

    static func outcome(of response: HTTPTransportResponse, for request: EncodedRequest) -> ResponseOutcome {
        AcmeBatchEncoder.outcome(of: response, for: request)
    }

    func didReceive(_ response: HTTPTransportResponse, for request: EncodedRequest) {
        inner.didReceive(response, for: request)
    }

    func requests(for batch: [EventRecord]) -> BatchRequests<AcmeEncodingError> {
        let sent = batch.filter(isSent)
        guard !sent.isEmpty else { return BatchRequests(requests: [], skippedRecords: []) }
        return inner.requests(for: sent)
    }
}

/// Why the Acme factory couldn't make a destination.
enum AcmeSetupError: Error, Hashable {
    case emptyAPIKey
    case invalidHost
}

extension HTTPDestination where Encoding == AcmeBatchEncoder {
    static func acme(
        apiKey: String,
        host: URL,
        plan: TrackingPlan,
        transport: Transport,
        backoff: ExponentialBackoff = ExponentialBackoff()
    ) throws(AcmeSetupError) -> HTTPDestination<Transport, AcmeBatchEncoder> {
        guard !apiKey.isEmpty else { throw .emptyAPIKey }
        guard host.scheme == "https", host.host() != nil else { throw .invalidHost }
        return HTTPDestination(
            endpoint: host.appending(path: "v1/events"),
            // Acme doesn't read a trace context, so the app's traces aren't sent to it.
            instrument: NoOpInstrument(),
            transport: transport,
            encoder: AcmeBatchEncoder(apiKey: apiKey, plan: plan),
            backoff: backoff)
    }
}

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("Writing a vendor destination examples", .timeLimit(.minutes(1)))
private struct WritingAVendorDestinationExamplesTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
        var email: Sensitive<String>
    }

    @Test(arguments: ConformanceCheck.allCases)
    func acmeConformance(check: ConformanceCheck) async throws {
        let host = try #require(URL(string: "https://acme.example.com"))
        let conformance = DestinationConformance(limit: AcmeBatchEncoder.batchLimit) { setup in
            try HTTPDestination.acme(apiKey: "test-key", host: host, plan: setup.plan, transport: setup.transport, backoff: setup.backoff)
        }
        try await conformance.expect(check)
    }

    @Test("The Acme encoder's transient statuses are 425 alone, which the conformance checks retry")
    func acmeTransientStatuses() throws {
        // Read as HTTPDestination reads it, through the protocol.
        func transientStatuses<Encoder: BatchEncoder>(of encoder: Encoder.Type) -> Set<TransientStatus> {
            Encoder.transientStatuses
        }
        let expected: Set<TransientStatus> = [try TransientStatus(425)]

        let actual = transientStatuses(of: AcmeBatchEncoder.self)

        #expect(actual == expected)
    }

    @Test("Acme's 200 saying it accepted nothing is dropped and reported with its error; one saying it accepted the request is delivered")
    func acmeOutcome() async throws {
        let host = try #require(URL(string: "https://acme.example.com"))
        let plan = try TrackingPlan(schemas: [SignedUp.schema])
        let transport = ScriptedTransport([
            .response(.ok, body: Data(#"{"accepted":true}"#.utf8)),
            .response(.ok, body: Data(#"{"accepted":false,"error":"unknown API key"}"#.utf8)),
        ])
        let sut = try HTTPDestination.acme(apiKey: "test-key", host: host, plan: plan, transport: transport)
        let delivered = [EventRecord(event: SignedUp(plan: "pro", email: Sensitive("ada@example.com")), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)]
        let refused = [EventRecord(event: SignedUp(plan: "team", email: Sensitive("grace@example.com")), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil)]
        let expected = HTTPDropReport<AcmeBatchEncoder.Failure>.rejectedInBody(status: .ok, reason: "unknown API key", recordIDs: refused.map(\.id))

        await sut.receive(delivered)
        await sut.receive(refused)

        // A report of the delivered batch would come first.
        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
    }

    @Test("The Acme encoder writes a hand-worked record as Acme's JSON, without its Sensitive email, and the factory posts it to the host's /v1/events")
    func acmeRequest() async throws {
        let host = try #require(URL(string: "https://acme.example.com"))
        let plan = try TrackingPlan(schemas: [SignedUp.schema])
        let transport = ScriptedTransport([.status(.ok)])
        let sut = try HTTPDestination.acme(apiKey: "test-key", host: host, plan: plan, transport: transport)
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
        context[NetworkKey.self] = .wifi
        var record = EventRecord(
            id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!,
            event: SignedUp(plan: "pro", email: Sensitive("ada@example.com")),
            timestamp: Date(timeIntervalSince1970: 1_795_442_607.5),
            sourceLocation: nil,
            context: context
        )
        record.revealsSensitiveValues = true
        let expectedBody = #"{"api_key":"test-key","events":[{"context":{"network":"wifi"},"event":"signed_up","insert_id":"6f9619ff-8b86-d011-b42d-00c04fc964ff","properties":{"plan":"pro"},"time":1795442607500,"user_id":"00000000-0000-4000-8000-00000000000a"}]}"#
        let expectedURL = "https://acme.example.com/v1/events"

        await sut.receive([record])

        let actual = try #require(transport.requests.first)
        #expect(String(decoding: actual.body, as: UTF8.self) == expectedBody)
        #expect(actual.request.url?.absoluteString == expectedURL)
    }

    @Test("The wrapping encoder sends what Acme's sends for the records it keeps, and sends nothing for a batch it keeps none of")
    func filteredAcmeEncoder() async throws {
        let endpoint = try #require(URL(string: "https://acme.example.com/v1/events"))
        let plan = try TrackingPlan(schemas: [SignedUp.schema])
        let transport = ScriptedTransport([.status(.ok)])
        let inner = AcmeBatchEncoder(apiKey: "test-key", plan: plan)
        let encoder = FilteredAcmeEncoder(inner: inner) { ($0.event as? SignedUp)?.plan != "internal" }
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: encoder)
        let kept = EventRecord(event: SignedUp(plan: "pro", email: Sensitive("ada@example.com")), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let left = EventRecord(event: SignedUp(plan: "internal", email: Sensitive("grace@example.com")), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil)
        let expectedBodies = inner.requests(for: [kept]).requests.map(\.body.body)

        await sut.receive([kept, left])
        await sut.receive([left])

        let actual = transport.requests.map(\.body)
        #expect(actual == expectedBodies)
    }

    @Test("The Acme factory throws emptyAPIKey for an empty key and invalidHost for an http host")
    func acmeSetupErrors() throws {
        let host = try #require(URL(string: "https://acme.example.com"))
        let insecure = try #require(URL(string: "http://acme.example.com"))
        let plan = try TrackingPlan(schemas: [])
        let transport = ScriptedTransport([])

        #expect(throws: AcmeSetupError.emptyAPIKey) {
            try HTTPDestination.acme(apiKey: "", host: host, plan: plan, transport: transport)
        }
        #expect(throws: AcmeSetupError.invalidHost) {
            try HTTPDestination.acme(apiKey: "k", host: insecure, plan: plan, transport: transport)
        }
    }
}
