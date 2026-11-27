import Foundation
public import HTTPDestinations
import Instrumentation
public import TrackingPlans

extension HTTPDestination where Encoding == TelemetryDeckBatchEncoder {
    /// A destination that sends batches to the TelemetryDeck app `appID`, in the organization's
    /// `namespace`, marking every event as a test event or not as `testMode` says, through
    /// `transport`, retrying a send that fails for now with the waits of `backoff` on `clock`.
    ///
    /// The destination posts to `https://nom.telemetrydeck.com/v3/<namespace>/`, TelemetryDeck's
    /// Ingest API v3, encoded by a ``TelemetryDeckBatchEncoder`` within
    /// ``TelemetryDeckBatchEncoder/batchLimit``, and sends no trace context in its header fields.
    /// It retries no response, a 5xx, 408 or 429, and drops and reports any other status, such as
    /// 422 for a request holding an event TelemetryDeck refuses.
    ///
    /// The app ID is public, as every TelemetryDeck client sends it, so the destination builds on
    /// every platform: an app sends to TelemetryDeck directly.
    ///
    /// - Parameters:
    ///   - appID: The app's ID, from its settings in the TelemetryDeck dashboard.
    ///   - namespace: The organization's namespace, from the dashboard, such as `com.example`.
    ///   - testMode: Whether every event is a test event, which TelemetryDeck's dashboard shows only
    ///     in Test Mode: `true` for a development or internal build, `false` for one users run.
    ///     There is no default: `#if DEBUG` in a library tells its own build configuration, not the
    ///     app's, so the app decides, from its own build settings.
    ///   - plan: The tracking plan of every event the destination is given.
    ///   - transport: What sends each request.
    ///   - backoff: How long to wait before each new attempt at a request; 1 second, doubling up
    ///     to 60 seconds, by default.
    ///   - clock: The clock the waits are measured on.
    /// - Returns: The destination.
    /// - Throws: ``TelemetryDeckSetupError/emptyAppID`` for an app ID that is empty or only
    ///   whitespace, and ``TelemetryDeckSetupError/invalidNamespace`` for a namespace TelemetryDeck
    ///   doesn't take: empty, holding a character other than an ASCII letter, digit, `.`, `_` or
    ///   `-`, `.`, `..`, or `w`.
    public static func telemetryDeck(
        appID: String,
        namespace: String,
        testMode: Bool,
        plan: TrackingPlan,
        transport: Transport,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock()
    ) throws(TelemetryDeckSetupError) -> HTTPDestination<Transport, TelemetryDeckBatchEncoder> {
        guard namespace.isTelemetryDeckNamespace,
              let endpoint = URL(string: "https://nom.telemetrydeck.com/v3/\(namespace)/")
        else {
            throw .invalidNamespace
        }
        let encoder = try TelemetryDeckBatchEncoder(appID: appID, testMode: testMode, plan: plan)
        // TelemetryDeck doesn't read a trace context, so the app's traces aren't sent to it.
        let instrument: any Instrument = NoOpInstrument()
        return HTTPDestination(
            endpoint: endpoint,
            instrument: instrument,
            transport: transport,
            encoder: encoder,
            backoff: backoff,
            clock: clock)
    }
}

extension HTTPDestination where Transport == URLSessionTransport, Encoding == TelemetryDeckBatchEncoder {
    /// A destination that sends batches to the TelemetryDeck app `appID`, in the organization's
    /// `namespace`, marking every event as a test event or not as `testMode` says, with
    /// `URLSession.shared`, retrying a send that fails for now with the waits of `backoff` on
    /// `clock`.
    ///
    /// ```swift
    /// let telemetryDeck = try HTTPDestination.telemetryDeck(
    ///     appID: appID,  // from the app's settings in the TelemetryDeck dashboard
    ///     namespace: "com.example",  // your organization's namespace
    ///     testMode: false,  // true for builds whose signals only Test Mode should show
    ///     plan: plan)
    /// ```
    ///
    /// It is ``HTTPDestinations/HTTPDestination/telemetryDeck(appID:namespace:testMode:plan:transport:backoff:clock:)``
    /// with a `URLSessionTransport`.
    ///
    /// - Parameters:
    ///   - appID: The app's ID, from its settings in the TelemetryDeck dashboard.
    ///   - namespace: The organization's namespace, from the dashboard, such as `com.example`.
    ///   - testMode: Whether every event is a test event, which TelemetryDeck's dashboard shows only
    ///     in Test Mode.
    ///   - plan: The tracking plan of every event the destination is given.
    ///   - backoff: How long to wait before each new attempt at a request; 1 second, doubling up
    ///     to 60 seconds, by default.
    ///   - clock: The clock the waits are measured on.
    /// - Returns: The destination.
    /// - Throws: ``TelemetryDeckSetupError`` for an empty app ID or a namespace TelemetryDeck
    ///   doesn't take, as the other spelling says.
    public static func telemetryDeck(
        appID: String,
        namespace: String,
        testMode: Bool,
        plan: TrackingPlan,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock()
    ) throws(TelemetryDeckSetupError) -> HTTPDestination<URLSessionTransport, TelemetryDeckBatchEncoder> {
        try telemetryDeck(appID: appID, namespace: namespace, testMode: testMode, plan: plan, transport: URLSessionTransport(), backoff: backoff, clock: clock)
    }
}
