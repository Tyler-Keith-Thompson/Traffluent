import DestinationTesting
import Events
import Foundation
import HTTPDestinations
import HTTPTypes
import Instrumentation
import JSONValues
import PropertyJSON
import Synchronization
import Testing
import TrackingPlans

// A vendor of the kit's own: each record as {"event","id","properties"} in a bare array, split to
// a small limit. Variants break one rule each, and the kit must record an issue for it.
@Suite("DestinationConformance", .timeLimit(.minutes(1)))
struct DestinationConformanceTests {
    struct Failure: Error, Hashable {
        var reason: String
    }

    /// What each variant gets wrong.
    enum Flaw: Sendable {
        case none
        case sendsSensitiveValues
        case ignoresRevealedSensitiveValues
        case revealsRedactedValuesWhenOptedIn
        case neverSplits
        case sendsOversizedRecords
        case dropsOversizedRecordsUnreported
        case forwardsTraceContext
        case sendsTraceHeader
        case writesTraceIntoBody
    }

    /// Writes what an instrument injects into a dictionary.
    struct DictionaryInjector: Injector {
        func inject(_ value: String, forKey key: String, into dictionary: inout [String: String]) {
            dictionary[key] = value
        }
    }

    /// A hand-written event, with no macro, for a fixture of the kit's own.
    struct Opened: Event, Codable {
        static let name = "opened"
        static let schema = EventSchema(name: name, version: schemaVersion, consentCategory: consentCategory, properties: [])
    }

    struct ToyEncoder: BatchEncoder {
        static let transientStatuses: Set<TransientStatus> = []

        typealias Failure = DestinationConformanceTests.Failure

        let reader: PropertyReader
        let limit: BatchLimit
        let flaw: Flaw
        let revealing: Bool
        /// When set, the time the encoder encodes at: like a vendor's that takes only recent
        /// events, it leaves out a record tracked at any other time.
        var encodedAt: Date? = nil

        func requests(for batch: [EventRecord]) -> BatchRequests<Failure> {
            if flaw == .neverSplits {
                return BatchRequests(requests: [EncodedRequest(body: body(of: batch), recordIDs: batch.map(\.id))], skippedRecords: [])
            }
            let split = limit.requests(for: batch, in: .array) { record throws(Failure) in
                try json(of: record)
            } oversized: { byteCount in
                Failure(reason: "oversized \(byteCount)")
            }
            switch flaw {
            case .sendsOversizedRecords:
                // Reports each record left out, and sends it anyway.
                let skipped = batch.filter { record in split.skippedRecords.contains { $0.recordID == record.id } }
                return BatchRequests(requests: split.requests + [EncodedRequest(body: body(of: skipped), recordIDs: skipped.map(\.id))], skippedRecords: split.skippedRecords)
            case .dropsOversizedRecordsUnreported:
                return BatchRequests(requests: split.requests, skippedRecords: [])
            default:
                return split
            }
        }

        /// One body of every record it can encode, whatever the limit.
        private func body(of batch: [EventRecord]) -> EncodedBatch {
            JSONEnvelope.array.body(of: batch.compactMap { try? json(of: $0).minified })
        }

        private func json(of record: EventRecord) throws(Failure) -> JSON {
            if let encodedAt, record.timestamp != encodedAt {
                throw Failure(reason: "tracked at \(record.timestamp), not \(encodedAt)")
            }
            var revealed = record
            if flaw == .sendsSensitiveValues || (revealing && flaw == .revealsRedactedValuesWhenOptedIn) {
                revealed.revealsSensitiveValues = true
            }
            let including = (revealing && flaw != .ignoresRevealedSensitiveValues) || flaw == .sendsSensitiveValues
            let properties: [String: JSON]
            do {
                properties = try reader.properties(of: revealed, includingSensitiveValues: including)
            } catch {
                throw Failure(reason: "\(error)")
            }
            var members: [String: JSON] = ["event": .string(record.name), "id": .string(record.deduplicationID), "properties": .object(properties)]
            if flaw == .writesTraceIntoBody {
                // The active instrument's fields for the record, in the body as the collector's are.
                var fields: [String: String] = [:]
                InstrumentationSystem.instrument.inject(record.context, into: &fields, using: DictionaryInjector())
                members["trace"] = .object(fields.mapValues(JSON.string))
            }
            return .object(members)
        }
    }

    static let limit = (try? BatchLimit(maximumRecordCount: 10, maximumByteCount: 4_096, maximumRecordByteCount: 1_024)) ?? .unlimited

    static func conformance(_ flaw: Flaw, optingIn: Bool = true, encodingAtSetupTimestamp: Bool = false, timestamp: Date? = nil) -> DestinationConformance<ToyEncoder> {
        @Sendable func destination(_ setup: DestinationSetup, revealing: Bool) throws -> HTTPDestination<ScriptedTransport, ToyEncoder> {
            let endpoint = try #require(URL(string: "https://vendor.example.com/ingest"))
            let encoder = ToyEncoder(reader: PropertyReader(plan: setup.plan), limit: limit, flaw: flaw, revealing: revealing, encodedAt: encodingAtSetupTimestamp ? (setup.timestamp == (timestamp ?? setup.timestamp) ? setup.timestamp : .distantPast) : nil)
            if flaw == .forwardsTraceContext {
                // The default instrument, the bootstrapped or active one.
                return HTTPDestination(endpoint: endpoint, transport: setup.transport, encoder: encoder, backoff: setup.backoff)
            }
            if flaw == .sendsTraceHeader {
                let traceparent = try #require(HTTPField.Name("traceparent"))
                return HTTPDestination(endpoint: endpoint, headerFields: [traceparent: "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"], instrument: NoOpInstrument(), transport: setup.transport, encoder: encoder, backoff: setup.backoff)
            }
            return HTTPDestination(endpoint: endpoint, instrument: NoOpInstrument(), transport: setup.transport, encoder: encoder, backoff: setup.backoff)
        }
        let revealing: DestinationConformance<ToyEncoder>.Factory = { try destination($0, revealing: true) }
        if let timestamp {
            return DestinationConformance(limit: limit, timestamp: timestamp, makeRevealingDestination: optingIn ? revealing : nil) { setup in
                try destination(setup, revealing: false)
            }
        }
        return DestinationConformance(limit: limit, makeRevealingDestination: optingIn ? revealing : nil) { setup in
            try destination(setup, revealing: false)
        }
    }

    @Test("A destination that keeps every rule passes every check", arguments: ConformanceCheck.allCases)
    func conforming(check: ConformanceCheck) async throws {
        let sut = Self.conformance(.none)

        try await sut.expect(check)
    }

    /// ``ToyEncoder`` for a vendor that answers 422 for a request worth sending again, one of the
    /// statuses rejectionsDropped sends.
    struct UnprocessableRetryingEncoder: BatchEncoder {
        static let transientStatuses: Set<TransientStatus> = (try? TransientStatus(.unprocessableContent)).map { [$0] } ?? []

        typealias Failure = DestinationConformanceTests.Failure

        let wrapped: ToyEncoder

        func requests(for batch: [EventRecord]) -> BatchRequests<Failure> {
            wrapped.requests(for: batch)
        }
    }

    @Test("A destination whose encoder names a transient status the kit would send as a rejection passes transientFailuresRetried and rejectionsDropped, as it retries that status", arguments: [ConformanceCheck.transientFailuresRetried, .rejectionsDropped])
    func encoderTransientStatus(check: ConformanceCheck) async throws {
        let endpoint = try #require(URL(string: "https://vendor.example.com/ingest"))
        let sut = DestinationConformance(limit: Self.limit) { setup in
            HTTPDestination(endpoint: endpoint, instrument: NoOpInstrument(), transport: setup.transport, encoder: UnprocessableRetryingEncoder(wrapped: ToyEncoder(reader: PropertyReader(plan: setup.plan), limit: Self.limit, flaw: .none, revealing: false)), backoff: setup.backoff)
        }

        try await sut.expect(check)
    }

    /// ``ToyEncoder`` for a vendor that answers every status rejectionsDropped sends, 400, 401,
    /// 403, 404, 413 and 422, for a request worth sending again.
    struct EveryRejectionRetryingEncoder: BatchEncoder {
        typealias Failure = DestinationConformanceTests.Failure

        static let transientStatuses = Set([400, 401, 403, 404, 413, 422].compactMap { try? TransientStatus(HTTPResponse.Status(code: $0)) })

        let wrapped: ToyEncoder

        func requests(for batch: [EventRecord]) -> BatchRequests<Failure> {
            wrapped.requests(for: batch)
        }
    }

    /// ``ToyEncoder`` for a vendor that answers every client error for a request worth sending again.
    struct EveryClientErrorRetryingEncoder: BatchEncoder {
        typealias Failure = DestinationConformanceTests.Failure

        static let transientStatuses = Set((400 ... 499).compactMap { try? TransientStatus(HTTPResponse.Status(code: $0)) })

        let wrapped: ToyEncoder

        func requests(for batch: [EventRecord]) -> BatchRequests<Failure> {
            wrapped.requests(for: batch)
        }
    }

    /// Counts the destinations a factory makes, one per send.
    final class FactoryCalls: Sendable {
        let count = Mutex(0)
    }

    @Test("rejectionsDropped against an encoder that lists every status it sends still checks a rejection, the first client error the encoder doesn't list, and passes")
    func everyRejectionListed() async throws {
        let endpoint = try #require(URL(string: "https://vendor.example.com/ingest"))
        let calls = FactoryCalls()
        let sut = DestinationConformance(limit: Self.limit) { setup in
            calls.count.withLock { $0 += 1 }
            return HTTPDestination(endpoint: endpoint, instrument: NoOpInstrument(), transport: setup.transport, encoder: EveryRejectionRetryingEncoder(wrapped: ToyEncoder(reader: PropertyReader(plan: setup.plan), limit: Self.limit, flaw: .none, revealing: false)), backoff: setup.backoff)
        }
        let expectedSends = 1

        try await sut.expect(.rejectionsDropped)

        #expect(calls.count.withLock { $0 } == expectedSends)
    }

    @Test("rejectionsDropped against an encoder that lists every client error as transient records an issue, as no rejection is left to check")
    func everyClientErrorListed() async throws {
        let endpoint = try #require(URL(string: "https://vendor.example.com/ingest"))
        let sut = DestinationConformance(limit: Self.limit) { setup in
            HTTPDestination(endpoint: endpoint, instrument: NoOpInstrument(), transport: setup.transport, encoder: EveryClientErrorRetryingEncoder(wrapped: ToyEncoder(reader: PropertyReader(plan: setup.plan), limit: Self.limit, flaw: .none, revealing: false)), backoff: setup.backoff)
        }
        let expected: [String] = ["lists every client error (4xx) as transient"]

        await withKnownIssue(isIntermittent: false) {
            do {
                try await sut.expect(.rejectionsDropped)
            } catch {
                Issue.record(error)
            }
        } matching: { issue in
            issue.comments.contains { comment in expected.contains { comment.rawValue.contains($0) } }
        }
    }

    @Test("Every check stamps its records with the setup's timestamp, so a destination that leaves out records tracked at any other time passes every check", arguments: ConformanceCheck.allCases)
    func recordsStampedAtSetupTimestamp(check: ConformanceCheck) async throws {
        let sut = Self.conformance(.none, encodingAtSetupTimestamp: true)

        try await sut.expect(check)
    }

    @Test("A timestamp given to the kit is the setup's and every check's records', so a destination that leaves out records tracked at any other time passes every check", arguments: ConformanceCheck.allCases)
    func givenTimestamp(check: ConformanceCheck) async throws {
        // A day before the default, which the encoder would refuse.
        let sut = Self.conformance(.none, encodingAtSetupTimestamp: true, timestamp: Date(timeIntervalSince1970: 1_795_356_207))

        try await sut.expect(check)
    }

    @Test("A destination that sends Sensitive values without the opt-in fails sensitiveValuesRedacted, though it offers no opt-in")
    func sendsSensitiveValues() async throws {
        let sut = Self.conformance(.sendsSensitiveValues, optingIn: false)
        let expected: [String] = ["sent a Sensitive value though the adopter didn't opt in"]

        await withKnownIssue(isIntermittent: false) {
            do {
                try await sut.expect(.sensitiveValuesRedacted)
            } catch {
                Issue.record(error)
            }
        } matching: { issue in
            issue.comments.contains { comment in expected.contains { comment.rawValue.contains($0) } }
        }
    }

    @Test("An opted-in destination that still leaves out revealed Sensitive values fails sensitiveValuesRedacted")
    func ignoresRevealedSensitiveValues() async throws {
        let sut = Self.conformance(.ignoresRevealedSensitiveValues)
        let expected: [String] = ["didn't send a Sensitive value the record reveals"]

        await withKnownIssue(isIntermittent: false) {
            do {
                try await sut.expect(.sensitiveValuesRedacted)
            } catch {
                Issue.record(error)
            }
        } matching: { issue in
            issue.comments.contains { comment in expected.contains { comment.rawValue.contains($0) } }
        }
    }

    @Test("An opted-in destination that sends a redacted record's Sensitive values fails sensitiveValuesRedacted")
    func revealsRedactedValuesWhenOptedIn() async throws {
        let sut = Self.conformance(.revealsRedactedValuesWhenOptedIn)
        let expected: [String] = ["sent a Sensitive value of a redacted record"]

        await withKnownIssue(isIntermittent: false) {
            do {
                try await sut.expect(.sensitiveValuesRedacted)
            } catch {
                Issue.record(error)
            }
        } matching: { issue in
            issue.comments.contains { comment in expected.contains { comment.rawValue.contains($0) } }
        }
    }

    @Test("A destination that never splits a batch fails oversizedRecordSkipped")
    func neverSplits() async throws {
        let sut = Self.conformance(.neverSplits)
        let expected: [String] = ["didn't report the oversized record alone as skipped", "sent a request holding the oversized record"]

        await withKnownIssue(isIntermittent: false) {
            do {
                try await sut.expect(.oversizedRecordSkipped)
            } catch {
                Issue.record(error)
            }
        } matching: { issue in
            issue.comments.contains { comment in expected.contains { comment.rawValue.contains($0) } }
        }
    }

    @Test("A destination that reports an oversized record as skipped but sends it anyway fails oversizedRecordSkipped")
    func sendsOversizedRecords() async throws {
        let sut = Self.conformance(.sendsOversizedRecords)
        let expected: [String] = ["sent a request holding the oversized record"]

        await withKnownIssue(isIntermittent: false) {
            do {
                try await sut.expect(.oversizedRecordSkipped)
            } catch {
                Issue.record(error)
            }
        } matching: { issue in
            issue.comments.contains { comment in expected.contains { comment.rawValue.contains($0) } }
        }
    }

    @Test("A destination that leaves an oversized record out without reporting it fails oversizedRecordSkipped")
    func dropsOversizedRecordsUnreported() async throws {
        let sut = Self.conformance(.dropsOversizedRecordsUnreported)
        let expected: [String] = ["didn't report the oversized record alone as skipped"]

        await withKnownIssue(isIntermittent: false) {
            do {
                try await sut.expect(.oversizedRecordSkipped)
            } catch {
                Issue.record(error)
            }
        } matching: { issue in
            issue.comments.contains { comment in expected.contains { comment.rawValue.contains($0) } }
        }
    }

    @Test("A destination whose transport isn't the setup's fails consentHolds, as nothing it sends is seen")
    func consentWithoutTransport() async throws {
        let endpoint = try #require(URL(string: "https://vendor.example.com/ingest"))
        let elsewhere = ScriptedTransport([])
        let sut = DestinationConformance(limit: Self.limit) { setup in
            HTTPDestination(endpoint: endpoint, transport: elsewhere, encoder: ToyEncoder(reader: PropertyReader(plan: setup.plan), limit: Self.limit, flaw: .none, revealing: false), backoff: setup.backoff)
        }

        let expected: [String] = ["didn't send an event whose category is granted and accepted"]

        await withKnownIssue(isIntermittent: false) {
            do {
                try await sut.expect(.consentHolds)
            } catch {
                Issue.record(error)
            }
        } matching: { issue in
            issue.comments.contains { comment in expected.contains { comment.rawValue.contains($0) } }
        }
    }

    @Test("A destination that injects the active tracer's trace context fails traceContextWithheld")
    func forwardsTraceContext() async throws {
        let sut = Self.conformance(.forwardsTraceContext)
        let expected: [String] = ["sent a trace context in its header fields", "asked the active tracer to inject"]

        await withKnownIssue(isIntermittent: false) {
            do {
                try await sut.expect(.traceContextWithheld)
            } catch {
                Issue.record(error)
            }
        } matching: { issue in
            issue.comments.contains { comment in expected.contains { comment.rawValue.contains($0) } }
        }
    }

    @Test("A destination whose header fields always carry a traceparent fails traceContextWithheld, though it injects nothing")
    func sendsTraceHeader() async throws {
        let sut = Self.conformance(.sendsTraceHeader)
        let expected: [String] = ["sent a trace context in its header fields"]

        await withKnownIssue(isIntermittent: false) {
            do {
                try await sut.expect(.traceContextWithheld)
            } catch {
                Issue.record(error)
            }
        } matching: { issue in
            issue.comments.contains { comment in expected.contains { comment.rawValue.contains($0) } }
        }
    }

    @Test("A destination whose encoder writes the active tracer's trace context into the body fails traceContextWithheld")
    func writesTraceIntoBody() async throws {
        let sut = Self.conformance(.writesTraceIntoBody)
        let expected: [String] = ["asked the active tracer to inject"]

        await withKnownIssue(isIntermittent: false) {
            do {
                try await sut.expect(.traceContextWithheld)
            } catch {
                Issue.record(error)
            }
        } matching: { issue in
            issue.comments.contains { comment in expected.contains { comment.rawValue.contains($0) } }
        }
    }

    @Test("A destination whose transport isn't the setup's fails traceContextWithheld, as nothing it sends is seen")
    func traceWithoutTransport() async throws {
        let endpoint = try #require(URL(string: "https://vendor.example.com/ingest"))
        let elsewhere = ScriptedTransport([])
        let sut = DestinationConformance(limit: Self.limit) { setup in
            HTTPDestination(endpoint: endpoint, instrument: NoOpInstrument(), transport: elsewhere, encoder: ToyEncoder(reader: PropertyReader(plan: setup.plan), limit: Self.limit, flaw: .none, revealing: false), backoff: setup.backoff)
        }
        let expected: [String] = ["sent nothing for a record tracked in a span"]

        await withKnownIssue(isIntermittent: false) {
            do {
                try await sut.expect(.traceContextWithheld)
            } catch {
                Issue.record(error)
            }
        } matching: { issue in
            issue.comments.contains { comment in expected.contains { comment.rawValue.contains($0) } }
        }
    }

    @Test("oversizedRecordSkipped makes no destination and records nothing for a limit with no byte cap under 64 MiB")
    func oversizedWithoutCap() async throws {
        // A factory that throws, so a check that made a destination would throw.
        let sut = DestinationConformance<ToyEncoder>(limit: .unlimited) { _ in
            throw Failure(reason: "no destination")
        }

        try await sut.expect(.oversizedRecordSkipped)
    }

    @Test("What the factory throws, each check throws")
    func factoryThrows() async {
        let sut = DestinationConformance<ToyEncoder>(limit: Self.limit) { _ in
            throw Failure(reason: "no destination")
        }
        let expected = Failure(reason: "no destination")

        await #expect(throws: expected) {
            try await sut.expect(.transientFailuresRetried)
        }
    }

    @Test("A fixture that matches passes, in the bundle or a directory of it, one that doesn't records an issue, and a missing one records an issue")
    func fixtures() async throws {
        let sut = Self.conformance(.none)
        let plan = try TrackingPlan(schemas: [])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtures = directory.appendingPathComponent("Fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        // No records make no request, so the fixture of them is empty; one record makes one
        // request, its body followed by a newline.
        try Data().write(to: directory.appendingPathComponent("empty.json"))
        try Data("[]\n".utf8).write(to: directory.appendingPathComponent("wrong.json"))
        try Data(#"[{"event":"opened","id":"6f9619ff-8b86-d011-b42d-00c04fc964ff","properties":{}}]"#.utf8 + [UInt8(ascii: "\n")]).write(to: fixtures.appendingPathComponent("opened.json"))
        let bundle = try #require(Bundle(path: directory.path))
        let record = EventRecord(id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!, event: Opened(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)

        try await sut.expectRequests(of: [], plan: plan, matchFixture: "empty", in: bundle)
        try await sut.expectRequests(of: [record], plan: try TrackingPlan(schemas: [Opened.schema]), matchFixture: "opened", subdirectory: "Fixtures", in: bundle)
        await withKnownIssue(isIntermittent: false) {
            do {
                try await sut.expectRequests(of: [], plan: plan, matchFixture: "wrong", in: bundle)
            } catch {
                Issue.record(error)
            }
        } matching: { issue in
            issue.comments.contains { $0.rawValue.contains("The requests don't match wrong.json") }
        }
        await withKnownIssue(isIntermittent: false) {
            do {
                try await sut.expectRequests(of: [], plan: plan, matchFixture: "missing", in: bundle)
            } catch {
                Issue.record(error)
            }
        } matching: { issue in
            issue.comments.contains { $0.rawValue.contains("No fixture missing.json") }
        }
    }
}
