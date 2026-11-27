import Foundation
public import HTTPDestinations
import HTTPTypes
import Instrumentation
public import TrackingPlans

extension HTTPDestination where Encoding == SegmentSpecBatchEncoder {
    /// A destination that sends batches to the Segment source of `writeKey`, in a workspace in
    /// `region`, through `transport`, retrying a send that fails for now with the waits of
    /// `backoff` on `clock`.
    ///
    /// The destination posts to the `/v1/batch` endpoint of `region`, encoded by a
    /// ``SegmentSpecBatchEncoder`` of `plan` within ``SegmentSpecBatchEncoder/batchLimit``, with
    /// the write key as HTTP Basic authentication's user name and an empty password, and sends no
    /// trace context in its header fields. It retries no response, a 5xx, 408 or 429, and drops
    /// and reports any other status, such as 400 for a request too large. Segment answers 200 for
    /// any other request, one whose events it doesn't store included, so a wrong region, or a write
    /// key of no source, may be answered 200 with nothing stored: check the source's debugger after
    /// setting it up.
    ///
    /// The write key is a public client key, as Segment's own app and web libraries ship it: it
    /// lets a client send data to the source and read nothing.
    ///
    /// - Parameters:
    ///   - writeKey: The source's write key, from the source's settings. Whitespace and newlines
    ///     around it are trimmed off.
    ///   - region: Where the workspace is: ``SegmentRegion/us``, Segment's default, or
    ///     ``SegmentRegion/eu``.
    ///   - plan: The tracking plan of every event the destination is given.
    ///   - transport: What sends each request.
    ///   - backoff: How long to wait before each new attempt at a request; 1 second, doubling up
    ///     to 60 seconds, by default.
    ///   - clock: The clock the waits are measured on.
    /// - Returns: The destination.
    /// - Throws: ``SegmentSetupError/emptyWriteKey`` for a write key that is empty or only
    ///   whitespace.
    public static func segment(
        writeKey: String,
        region: SegmentRegion,
        plan: TrackingPlan,
        transport: Transport,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock()
    ) throws(SegmentSetupError) -> HTTPDestination<Transport, SegmentSpecBatchEncoder> {
        // Trimmed once, so a key pasted with a newline is checked and sent without it.
        let writeKey = writeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        // Segment documents no format for a write key, so only an empty one is refused.
        guard !writeKey.isEmpty else {
            throw .emptyWriteKey
        }
        // Segment doesn't read a trace context, so the app's traces aren't sent to it.
        let instrument: any Instrument = NoOpInstrument()
        return HTTPDestination(
            endpoint: region.endpoint,
            headerFields: [.authorization: writeKey.basicAuthorization],
            instrument: instrument,
            transport: transport,
            encoder: SegmentSpecBatchEncoder(plan: plan),
            backoff: backoff,
            clock: clock)
    }
}

extension HTTPDestination where Transport == URLSessionTransport, Encoding == SegmentSpecBatchEncoder {
    /// A destination that sends batches to the Segment source of `writeKey`, in a workspace in
    /// `region`, with `URLSession.shared`, retrying a send that fails for now with the waits of
    /// `backoff` on `clock`.
    ///
    /// ```swift
    /// let segment = try HTTPDestination.segment(
    ///     writeKey: writeKey,
    ///     region: .us,  // or .eu, where the workspace is
    ///     plan: plan)
    /// ```
    ///
    /// It is ``HTTPDestinations/HTTPDestination/segment(writeKey:region:plan:transport:backoff:clock:)``
    /// with a `URLSessionTransport`.
    ///
    /// - Parameters:
    ///   - writeKey: The source's write key, from the source's settings: a public client key.
    ///     Whitespace and newlines around it are trimmed off.
    ///   - region: Where the workspace is: ``SegmentRegion/us``, Segment's default, or
    ///     ``SegmentRegion/eu``.
    ///   - plan: The tracking plan of every event the destination is given.
    ///   - backoff: How long to wait before each new attempt at a request; 1 second, doubling up
    ///     to 60 seconds, by default.
    ///   - clock: The clock the waits are measured on.
    /// - Returns: The destination.
    /// - Throws: ``SegmentSetupError`` for an empty write key, as the other spelling says.
    public static func segment(
        writeKey: String,
        region: SegmentRegion,
        plan: TrackingPlan,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock()
    ) throws(SegmentSetupError) -> HTTPDestination<URLSessionTransport, SegmentSpecBatchEncoder> {
        try segment(writeKey: writeKey, region: region, plan: plan, transport: URLSessionTransport(), backoff: backoff, clock: clock)
    }
}

extension SegmentRegion {
    /// The region's batch endpoint (Segment's HTTP Tracking API, "Regional configuration", and
    /// https://segment.com/docs/guides/regional-segment/).
    fileprivate var endpoint: URL {
        // Foundation has no non-failable initializer for a literal URL. These literals always
        // parse, so the fallback is never taken, and the endpoint test pins both. The URL macro
        // would check them at compile time, but it would add a macro package to every adopter's
        // build for two literals.
        switch self {
        case .us: URL(string: "https://api.segment.io/v1/batch") ?? URL(fileURLWithPath: "/")
        case .eu: URL(string: "https://events.eu1.segmentapis.com/v1/batch") ?? URL(fileURLWithPath: "/")
        }
    }
}
