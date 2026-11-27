import Afluent
import AsyncQueues
import Destinations
public import Events
public import Foundation
public import HTTPDestinations
import HTTPTypes
import InMemoryTracing
import Instrumentation
public import PropertyJSON
public import Testing
import Tracing
import Trackers
public import TrackingPlans

/// The checks every vendor destination passes, run from the vendor module's tests: its requests
/// match recorded fixtures byte for byte, and it keeps the library's rules for `Sensitive` values,
/// consent, oversized records, retries and trace context.
///
/// Make one with the vendor's factory, called with the kit's ``ScriptedTransport`` and short
/// backoff, then run each ``ConformanceCheck`` and each fixture from a test:
///
/// ```swift
/// @Test(arguments: ConformanceCheck.allCases)
/// func postHogConformance(check: ConformanceCheck) async throws {
///     let host = try #require(URL(string: "https://posthog.example.com"))
///     let conformance = DestinationConformance(limit: PostHogBatchEncoder.batchLimit) { setup in
///         try HTTPDestination.postHog(projectToken: "phc_test", host: host, plan: setup.plan, transport: setup.transport, backoff: setup.backoff)
///     }
///     try await conformance.expect(check)
/// }
/// ```
///
/// Each check records a Swift Testing issue, at the caller's source location, for every rule the
/// destination breaks, and throws what the factory throws. Unlike a project's own tests, which
/// write their assertions out in full, this is a published assertion, shared on purpose, as
/// TrackingPlanTesting's `expectTrackingPlan(_:matches:sourceLocation:)` is: every vendor module
/// runs the same checks. The checks send through the transport only, never the network, and run
/// in well under a second; give the calling suite a `.timeLimit`, as a factory that keeps a copy
/// of the destination it returns makes a check wait for ever.
public struct DestinationConformance<Encoding: BatchEncoder>: Sendable {
    /// What makes a destination for one check.
    public typealias Factory = @Sendable (DestinationSetup) throws -> HTTPDestination<ScriptedTransport, Encoding>

    private let limit: BatchLimit
    private let timestamp: Date
    private let bodyText: @Sendable (Data) -> String
    private let makeDestination: Factory
    private let makeRevealingDestination: Factory?

    /// Checks of the destinations `makeDestination` makes, which split batches to `limit`.
    ///
    /// - Parameters:
    ///   - limit: The vendor's limit, the one its encoder splits batches to.
    ///   - timestamp: When every record a check sends was tracked, and the setup's
    ///     ``DestinationSetup/timestamp``; 2026-11-24 14:03:27 UTC by default.
    ///   - bodyText: A body as text the checks can search for an event's name and values; the
    ///     body's UTF-8 by default. A vendor whose bodies encode events again (in base64, say)
    ///     passes one that decodes them.
    ///   - makeRevealingDestination: The destination as an adopter makes it after opting in to
    ///     sending `Sensitive` values, or `nil`, the default, for a vendor that never sends them.
    ///   - makeDestination: The destination as an adopter makes it by default, from the setup's
    ///     plan, transport and backoff.
    public init(
        limit: BatchLimit,
        timestamp: Date = .conformanceTimestamp,
        bodyText: @escaping @Sendable (Data) -> String = { String(decoding: $0, as: UTF8.self) },
        makeRevealingDestination: Factory? = nil,
        makeDestination: @escaping Factory
    ) {
        self.limit = limit
        self.timestamp = timestamp
        self.bodyText = bodyText
        self.makeDestination = makeDestination
        self.makeRevealingDestination = makeRevealingDestination
    }

    /// Records an issue unless the requests `records` make match the fixture `name` in `bundle`,
    /// byte for byte.
    ///
    /// The fixture holds each request's body in order, each followed by a newline (`\n`), as the
    /// destination posts them when the endpoint answers 200. When there is no such fixture, the
    /// issue's comment holds the bodies, to save as the fixture once they are checked by hand.
    ///
    /// - Parameters:
    ///   - records: The records to send, oldest first, as one batch.
    ///   - plan: The tracking plan of their events.
    ///   - name: The fixture's name, without its extension.
    ///   - pathExtension: The fixture's extension; `json` by default.
    ///   - subdirectory: The directory of the bundle's resources the fixture is in, such as the
    ///     `Fixtures` directory a test target copies; `nil`, the top level, by default.
    ///   - bundle: The bundle holding the fixture: the test target's `Bundle.module`.
    ///   - sourceLocation: Where an issue is recorded; the call's location by default.
    /// - Throws: What the factory throws.
    public func expectRequests(
        of records: [EventRecord],
        plan: TrackingPlan,
        matchFixture name: String,
        withExtension pathExtension: String = "json",
        subdirectory: String? = nil,
        in bundle: Bundle,
        sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) async throws {
        let sent = try await send(records, plan: plan, script: [.status(.ok)], through: makeDestination)
        var actual = Data()
        for request in sent.requests {
            actual.append(request.body)
            actual.append(UInt8(ascii: "\n"))
        }
        for request in sent.requests where request.request.method != .post {
            Issue.record("A request was sent with \(request.request.method), not POST", sourceLocation: sourceLocation)
        }
        if !sent.reports.isEmpty {
            Issue.record("Sending the fixture's records dropped some: \(sent.reports)", sourceLocation: sourceLocation)
        }
        guard let url = bundle.url(forResource: name, withExtension: pathExtension, subdirectory: subdirectory) else {
            Issue.record("No fixture \(name).\(pathExtension) in \(bundle.bundlePath). The requests sent were:\n\(bodyText(actual))", sourceLocation: sourceLocation)
            return
        }
        let expected = try Data(contentsOf: url)
        if actual != expected {
            Issue.record("The requests don't match \(name).\(pathExtension).\nExpected:\n\(bodyText(expected))\nActual:\n\(bodyText(actual))", sourceLocation: sourceLocation)
        }
    }

    /// Records an issue for each way the destination breaks `check`'s rule.
    ///
    /// - Parameters:
    ///   - check: The rule to check.
    ///   - sourceLocation: Where an issue is recorded; the call's location by default.
    /// - Throws: What the factory throws.
    public func expect(_ check: ConformanceCheck, sourceLocation: Testing.SourceLocation = #_sourceLocation) async throws {
        switch check {
        case .sensitiveValuesRedacted: try await expectSensitiveValuesRedacted(sourceLocation: sourceLocation)
        case .consentHolds: try await expectConsentHolds(sourceLocation: sourceLocation)
        case .oversizedRecordSkipped: try await expectOversizedRecordSkipped(sourceLocation: sourceLocation)
        case .transientFailuresRetried: try await expectTransientFailuresRetried(sourceLocation: sourceLocation)
        case .rejectionsDropped: try await expectRejectionsDropped(sourceLocation: sourceLocation)
        case .traceContextWithheld: try await expectTraceContextWithheld(sourceLocation: sourceLocation)
        }
    }

    private func expectSensitiveValuesRedacted(sourceLocation: Testing.SourceLocation) async throws {
        let secret = "traffluent-conformance-secret"
        let plan = try TrackingPlan(schemas: [ConformanceSensitiveEvent.schema])
        let event = ConformanceSensitiveEvent(label: "traffluent-conformance-sensitive", secret: Sensitive(secret))
        var revealing = EventRecord(event: event, timestamp: timestamp, sourceLocation: nil)
        revealing.revealsSensitiveValues = true
        let redacted = EventRecord(event: event, timestamp: timestamp, sourceLocation: nil)

        let byDefault = try await send([revealing, redacted], plan: plan, script: [.status(.ok)], through: makeDestination)
        let defaultText = byDefault.requests.map { bodyText($0.body) }.joined(separator: "\n")
        if byDefault.requests.isEmpty {
            Issue.record("The destination sent nothing for records of an event with a Sensitive property", sourceLocation: sourceLocation)
        }
        if defaultText.contains(secret) {
            Issue.record("The destination sent a Sensitive value though the adopter didn't opt in:\n\(defaultText)", sourceLocation: sourceLocation)
        }
        guard let makeRevealingDestination else { return }
        let optedIn = try await send([revealing], plan: plan, script: [.status(.ok)], through: makeRevealingDestination)
        let optedInText = optedIn.requests.map { bodyText($0.body) }.joined(separator: "\n")
        if !optedInText.contains(secret) {
            Issue.record("The opted-in destination didn't send a Sensitive value the record reveals:\n\(optedInText)", sourceLocation: sourceLocation)
        }
        let optedInRedacted = try await send([redacted], plan: plan, script: [.status(.ok)], through: makeRevealingDestination)
        let optedInRedactedText = optedInRedacted.requests.map { bodyText($0.body) }.joined(separator: "\n")
        if optedInRedactedText.contains(secret) {
            Issue.record("The opted-in destination sent a Sensitive value of a redacted record:\n\(optedInRedactedText)", sourceLocation: sourceLocation)
        }
    }

    private func expectConsentHolds(sourceLocation: Testing.SourceLocation) async throws {
        let plan = try TrackingPlan(schemas: [ConformanceAnalyticsEvent.schema, ConformanceFunctionalEvent.schema, ConformanceAdvertisingEvent.schema])
        let transport = ScriptedTransport([.status(.ok)])
        let destination = try makeDestination(DestinationSetup(plan: plan, transport: transport, backoff: try .conformance, timestamp: timestamp))
        let consent = Consent([.analytics: .granted, .functional: .granted, .advertising: .denied])
        // Stamped as the other checks' records are, so a destination that leaves out records by
        // their age measures them from the setup's timestamp too.
        let tracker = Tracker(consent: consent, now: { [timestamp] in timestamp })
        let delivery = tracker.records.batch().deliver(to: destination.accepting(.analytics, .advertising))

        tracker.track(ConformanceAnalyticsEvent(label: "traffluent-conformance-granted"))
        tracker.track(ConformanceFunctionalEvent(label: "traffluent-conformance-not-accepted"))
        tracker.track(ConformanceAdvertisingEvent(label: "traffluent-conformance-denied"))
        await tracker.finish()
        try await delivery.execute()

        let text = transport.requests.map { bodyText($0.body) }.joined(separator: "\n")
        if !text.contains(ConformanceAnalyticsEvent.name) {
            Issue.record("The destination didn't send an event whose category is granted and accepted:\n\(text)", sourceLocation: sourceLocation)
        }
        if text.contains(ConformanceFunctionalEvent.name) {
            Issue.record("The destination sent an event of a category it doesn't accept:\n\(text)", sourceLocation: sourceLocation)
        }
        if text.contains(ConformanceAdvertisingEvent.name) {
            Issue.record("The destination sent an event of a denied category:\n\(text)", sourceLocation: sourceLocation)
        }
    }

    private func expectOversizedRecordSkipped(sourceLocation: Testing.SourceLocation) async throws {
        // The label alone fills the limit, so the record's JSON, with its name and quotes, is over
        // it. Bounded, as the kit allocates the label.
        let labelByteCount = min(limit.maximumRecordByteCount, limit.maximumByteCount)
        // No cap the kit can exceed: nothing to check, which ConformanceCheck documents.
        guard labelByteCount <= 64 << 20 else { return }
        let plan = try TrackingPlan(schemas: [ConformanceAnalyticsEvent.schema])
        let oversized = EventRecord(event: ConformanceAnalyticsEvent(label: String(repeating: "x", count: labelByteCount)), timestamp: timestamp, sourceLocation: nil)
        let small = EventRecord(event: ConformanceAnalyticsEvent(label: "traffluent-conformance-small"), timestamp: timestamp, sourceLocation: nil)

        let sent = try await send([oversized, small], plan: plan, script: [.status(.ok)], through: makeDestination)

        let skippedIDs = sent.reports.compactMap { report in
            if case .skipped(let skipped) = report { skipped.recordID } else { nil }
        }
        if skippedIDs != [oversized.id] {
            Issue.record("The destination didn't report the oversized record alone as skipped: \(sent.reports)", sourceLocation: sourceLocation)
        }
        if sent.requests.contains(where: { $0.body.count > labelByteCount }) {
            Issue.record("The destination sent a request holding the oversized record", sourceLocation: sourceLocation)
        }
        if !sent.requests.contains(where: { bodyText($0.body).contains("traffluent-conformance-small") }) {
            Issue.record("The destination didn't send the batch's other record", sourceLocation: sourceLocation)
        }
    }

    private func expectTransientFailuresRetried(sourceLocation: Testing.SourceLocation) async throws {
        let plan = try TrackingPlan(schemas: [ConformanceAnalyticsEvent.schema])
        let failures: [ScriptedTransport.Answer] = [.noResponse, .status(.requestTimeout), .status(.tooManyRequests), .status(.internalServerError), .status(.serviceUnavailable)]
        for failure in failures {
            let record = EventRecord(event: ConformanceAnalyticsEvent(label: "traffluent-conformance-retried"), timestamp: timestamp, sourceLocation: nil)

            let sent = try await send([record], plan: plan, script: [failure, .status(.ok)], through: makeDestination)

            if sent.requests.count != 2 {
                Issue.record("After \(failure), the destination sent \(sent.requests.count) requests, not the request and one retry", sourceLocation: sourceLocation)
            } else if sent.requests[0].body != sent.requests[1].body {
                Issue.record("After \(failure), the destination's retry had a different body", sourceLocation: sourceLocation)
            }
            if !sent.reports.isEmpty {
                Issue.record("After \(failure) and then 200, the destination reported a drop: \(sent.reports)", sourceLocation: sourceLocation)
            }
        }
    }

    private func expectRejectionsDropped(sourceLocation: Testing.SourceLocation) async throws {
        let plan = try TrackingPlan(schemas: [ConformanceAnalyticsEvent.schema])
        let rejections: [HTTPResponse.Status] = [.badRequest, .unauthorized, .forbidden, .notFound, .contentTooLarge, .unprocessableContent]
        for status in rejections {
            let record = EventRecord(event: ConformanceAnalyticsEvent(label: "traffluent-conformance-rejected"), timestamp: timestamp, sourceLocation: nil)

            let sent = try await send([record], plan: plan, script: [.status(status)], through: makeDestination)

            if sent.requests.count != 1 {
                Issue.record("After \(status), the destination sent \(sent.requests.count) requests, not one", sourceLocation: sourceLocation)
            }
            let rejected = sent.reports.contains { report in
                if case .rejected(status, [record.id]) = report { true } else { false }
            }
            if !rejected || sent.reports.count != 1 {
                Issue.record("After \(status), the destination didn't report the record as rejected: \(sent.reports)", sourceLocation: sourceLocation)
            }
        }
    }

    private func expectTraceContextWithheld(sourceLocation: Testing.SourceLocation) async throws {
        let plan = try TrackingPlan(schemas: [ConformanceAnalyticsEvent.schema])
        // Active for the factory and the send, so a destination that takes the default
        // instrument, `InstrumentationSystem.instrument`, gets this tracer.
        let tracer = InMemoryTracer()
        let span = tracer.startSpan("traffluent-conformance")
        let record = EventRecord(event: ConformanceAnalyticsEvent(label: "traffluent-conformance-traced"), timestamp: timestamp, sourceLocation: nil, context: span.context)

        let sent = try await withTracer(tracer) { () async throws -> Sent in
            try await send([record], plan: plan, script: [.status(.ok)], through: makeDestination)
        }
        span.end()

        let traceFields: Set<String> = ["traceparent", "tracestate", InMemoryTracer.traceIDKey, InMemoryTracer.spanIDKey]
        if sent.requests.isEmpty {
            Issue.record("The destination sent nothing for a record tracked in a span", sourceLocation: sourceLocation)
        }
        for request in sent.requests where request.request.headerFields.contains(where: { traceFields.contains($0.name.canonicalName) }) {
            Issue.record("The destination sent a trace context in its header fields: \(request.request.headerFields)", sourceLocation: sourceLocation)
        }
        if !tracer.performedContextInjections.isEmpty {
            Issue.record("The destination asked the active tracer to inject a trace context, into its header fields or its body", sourceLocation: sourceLocation)
        }
    }

    /// Hands `records` to a destination `factory` makes, as one batch, through a transport of
    /// `script`, and returns what it sent and every drop it reported.
    private func send(_ records: [EventRecord], plan: TrackingPlan, script: [ScriptedTransport.Answer], through factory: Factory) async throws -> Sent {
        let transport = ScriptedTransport(script)
        let reports = try await receive(records, setup: DestinationSetup(plan: plan, transport: transport, backoff: .conformance, timestamp: timestamp), through: factory)
        // The destination is gone, so its reports end once read.
        var collected: [HTTPDropReport<Encoding.Failure>] = []
        for await report in reports {
            collected.append(report)
        }
        return Sent(requests: transport.requests, reports: collected)
    }

    /// The destination's drop reports, once it has received `records`; the destination itself
    /// goes as this returns.
    private func receive(_ records: [EventRecord], setup: DestinationSetup, through factory: Factory) async throws -> AsyncQueue<HTTPDropReport<Encoding.Failure>> {
        let destination = try factory(setup)
        await destination.receive(records)
        return destination.dropReports
    }

    /// What one destination sent and reported.
    private struct Sent {
        var requests: [ScriptedTransport.SentRequest]
        var reports: [HTTPDropReport<Encoding.Failure>]
    }
}

extension ExponentialBackoff {
    /// A backoff of a nanosecond, so a retried request is sent again at once.
    fileprivate static var conformance: ExponentialBackoff {
        get throws(InvalidBackoff) {
            try ExponentialBackoff(initialDelay: .nanoseconds(1), maximumDelay: .nanoseconds(1))
        }
    }
}

extension Date {
    /// The time every check's records are stamped with, and `DestinationSetup`'s timestamp, by
    /// default.
    @usableFromInline
    static let conformanceTimestamp = Date(timeIntervalSince1970: 1_795_442_607)
}
