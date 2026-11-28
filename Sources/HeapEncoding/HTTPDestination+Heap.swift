import Foundation
public import HTTPDestinations
import Instrumentation
public import TrackingPlans

extension HTTPDestination where Encoding == HeapBatchEncoder {
    /// A destination that sends batches to the Heap environment `appID`, whose data resides in
    /// `region`, through `transport`, retrying a send that fails for now with the waits of
    /// `backoff` on `clock`.
    ///
    /// The destination posts bulk track requests to the `/api/track` endpoint of `region`, encoded
    /// by a ``HeapBatchEncoder`` of `plan` within ``HeapBatchEncoder/batchLimit``, and sends no
    /// trace context in its header fields. It retries no response, a 5xx, 408 or 429, and drops and
    /// reports any other status, such as 400 for a request Heap can't take.
    ///
    /// Heap's track API takes the environment's ID alone, which is public, as Heap's client SDKs
    /// ship it in every app, so the destination builds on every platform and takes nothing else:
    /// never an API key, which only Heap's user deletion API takes and which must not ship in an
    /// app.
    ///
    /// - Parameters:
    ///   - appID: The environment's ID, from Heap's project settings, such as `12343283`.
    ///     Whitespace and newlines around it are trimmed off.
    ///   - region: Where the project's data resides: ``HeapRegion/us``, Heap's default, or
    ///     ``HeapRegion/eu``.
    ///   - plan: The tracking plan of every event the destination is given.
    ///   - transport: What sends each request.
    ///   - backoff: How long to wait before each new attempt at a request; 1 second, doubling up
    ///     to 60 seconds, with full jitter, by default.
    ///   - clock: The clock the waits are measured on.
    /// - Returns: The destination.
    /// - Throws: ``HeapSetupError/emptyAppID`` for an app ID that is empty or only whitespace, and
    ///   ``HeapSetupError/malformedAppID`` for one holding a character other than an ASCII digit.
    public static func heap(
        appID: String,
        region: HeapRegion,
        plan: TrackingPlan,
        transport: Transport,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock()
    ) throws(HeapSetupError) -> HTTPDestination<Transport, HeapBatchEncoder> {
        let encoder = try HeapBatchEncoder(appID: appID, plan: plan)
        // Heap doesn't read a trace context, so the app's traces aren't sent to it.
        let instrument: any Instrument = NoOpInstrument()
        return HTTPDestination(
            endpoint: region.endpoint,
            instrument: instrument,
            transport: transport,
            encoder: encoder,
            backoff: backoff,
            clock: clock)
    }
}

extension HTTPDestination where Transport == URLSessionTransport, Encoding == HeapBatchEncoder {
    /// A destination that sends batches to the Heap environment `appID`, whose data resides in
    /// `region`, with `URLSession.shared`, retrying a send that fails for now with the waits of
    /// `backoff` on `clock`.
    ///
    /// ```swift
    /// let heap = try HTTPDestination.heap(
    ///     appID: appID,  // the environment's ID, from Heap's project settings
    ///     region: .us,  // or .eu, where the project's data resides
    ///     plan: plan)
    /// ```
    ///
    /// It is ``HTTPDestinations/HTTPDestination/heap(appID:region:plan:transport:backoff:clock:)``
    /// with a `URLSessionTransport`.
    ///
    /// - Parameters:
    ///   - appID: The environment's ID, from Heap's project settings; never an API key.
    ///     Whitespace and newlines around it are trimmed off.
    ///   - region: Where the project's data resides: ``HeapRegion/us``, Heap's default, or
    ///     ``HeapRegion/eu``.
    ///   - plan: The tracking plan of every event the destination is given.
    ///   - backoff: How long to wait before each new attempt at a request; 1 second, doubling up
    ///     to 60 seconds, with full jitter, by default.
    ///   - clock: The clock the waits are measured on.
    /// - Returns: The destination.
    /// - Throws: ``HeapSetupError`` for an empty or malformed app ID, as the other spelling says.
    public static func heap(
        appID: String,
        region: HeapRegion,
        plan: TrackingPlan,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock()
    ) throws(HeapSetupError) -> HTTPDestination<URLSessionTransport, HeapBatchEncoder> {
        try heap(appID: appID, region: region, plan: plan, transport: URLSessionTransport(), backoff: backoff, clock: clock)
    }
}

extension HeapRegion {
    /// The region's track endpoint (https://developers.heap.io/reference/track-1).
    fileprivate var endpoint: URL {
        // Foundation has no non-failable initializer for a literal URL. These literals always
        // parse, so the fallback is never taken, and the endpoint test pins both. The URL macro
        // would check them at compile time, but it would add a macro package to every adopter's
        // build for two literals.
        switch self {
        case .us: URL(string: "https://heapanalytics.com/api/track") ?? URL(fileURLWithPath: "/")
        case .eu: URL(string: "https://c.eu.heap-api.com/api/track") ?? URL(fileURLWithPath: "/")
        }
    }
}
