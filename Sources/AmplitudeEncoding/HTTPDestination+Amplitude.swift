import Foundation
public import HTTPDestinations
import Instrumentation
public import TrackingPlans

extension HTTPDestination where Encoding == AmplitudeBatchEncoder {
    /// A destination that sends batches to the Amplitude project of `apiKey`, whose data resides in
    /// `region`, through `transport`, retrying a send that fails for now with the waits of
    /// `backoff` on `clock`.
    ///
    /// The destination posts to the HTTP V2 endpoint of `region`, encoded by an
    /// ``AmplitudeBatchEncoder`` of `plan` within ``AmplitudeBatchEncoder/batchLimit``, and sends
    /// no trace context in its header fields. It retries what Amplitude says to retry, no
    /// response, a 5xx, 408 or 429, and drops and reports any other status, such as 400 for an
    /// invalid request or 413 for one too large.
    ///
    /// - Parameters:
    ///   - apiKey: The project's API key, from the project's settings; never its secret key.
    ///     Whitespace and newlines around it are trimmed off.
    ///   - region: Where the project's data resides: ``AmplitudeRegion/us``, Amplitude's
    ///     default data center, or ``AmplitudeRegion/eu`` for a project in its EU one.
    ///   - plan: The tracking plan of every event the destination is given.
    ///   - transport: What sends each request.
    ///   - backoff: How long to wait before each new attempt at a request; 1 second, doubling up
    ///     to 60 seconds, with full jitter, by default.
    ///   - clock: The clock the waits are measured on.
    /// - Returns: The destination.
    /// - Throws: ``AmplitudeSetupError/emptyAPIKey`` for a key that is empty or only whitespace,
    ///   and ``AmplitudeSetupError/deploymentKey`` for an Amplitude Experiment deployment key
    ///   (`client-...` or `server-...`).
    public static func amplitude(
        apiKey: String,
        region: AmplitudeRegion,
        plan: TrackingPlan,
        transport: Transport,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock()
    ) throws(AmplitudeSetupError) -> HTTPDestination<Transport, AmplitudeBatchEncoder> {
        // Trimmed once, so a key pasted with a newline is checked and sent without it.
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw .emptyAPIKey
        }
        // Amplitude documents no format for a project's API key, and its secret keys look the
        // same, so a rule on the key's form could only refuse a key Amplitude takes. Experiment's
        // deployment keys are the one kind it names by prefix (Keys and Tokens,
        // https://amplitude.com/docs/apis/keys-and-tokens). Case-sensitive, as Amplitude issues
        // them in lowercase.
        guard !apiKey.hasPrefix("client-"), !apiKey.hasPrefix("server-") else {
            throw .deploymentKey
        }
        // Amplitude doesn't read a trace context, so the app's traces aren't sent to it.
        let instrument: any Instrument = NoOpInstrument()
        return HTTPDestination(
            endpoint: region.endpoint,
            instrument: instrument,
            transport: transport,
            encoder: AmplitudeBatchEncoder(apiKey: apiKey, plan: plan),
            backoff: backoff,
            clock: clock)
    }
}

extension HTTPDestination where Transport == URLSessionTransport, Encoding == AmplitudeBatchEncoder {
    /// A destination that sends batches to the Amplitude project of `apiKey`, whose data resides in
    /// `region`, with `URLSession.shared`, retrying a send that fails for now with the waits of
    /// `backoff` on `clock`.
    ///
    /// ```swift
    /// let amplitude = try HTTPDestination.amplitude(
    ///     apiKey: apiKey,
    ///     region: .us,  // or .eu, where the project's data resides
    ///     plan: plan)
    /// ```
    ///
    /// It is ``HTTPDestinations/HTTPDestination/amplitude(apiKey:region:plan:transport:backoff:clock:)``
    /// with a `URLSessionTransport`.
    ///
    /// - Parameters:
    ///   - apiKey: The project's API key, from the project's settings; never its secret key.
    ///     Whitespace and newlines around it are trimmed off.
    ///   - region: Where the project's data resides: ``AmplitudeRegion/us``, Amplitude's
    ///     default data center, or ``AmplitudeRegion/eu`` for a project in its EU one.
    ///   - plan: The tracking plan of every event the destination is given.
    ///   - backoff: How long to wait before each new attempt at a request; 1 second, doubling up
    ///     to 60 seconds, with full jitter, by default.
    ///   - clock: The clock the waits are measured on.
    /// - Returns: The destination.
    /// - Throws: ``AmplitudeSetupError`` for an empty key or an Experiment deployment key, as the
    ///   other spelling says.
    public static func amplitude(
        apiKey: String,
        region: AmplitudeRegion,
        plan: TrackingPlan,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock()
    ) throws(AmplitudeSetupError) -> HTTPDestination<URLSessionTransport, AmplitudeBatchEncoder> {
        try amplitude(apiKey: apiKey, region: region, plan: plan, transport: URLSessionTransport(), backoff: backoff, clock: clock)
    }
}

extension AmplitudeRegion {
    /// The region's HTTP V2 endpoint (https://amplitude.com/docs/apis/analytics/http-v2,
    /// "Regions").
    fileprivate var endpoint: URL {
        // Foundation has no non-failable initializer for a literal URL. These literals always
        // parse, so the fallback is never taken, and the endpoint test pins both. The URL macro
        // would check them at compile time, but it would add a macro package to every adopter's
        // build for two literals.
        switch self {
        case .us: URL(string: "https://api2.amplitude.com/2/httpapi") ?? URL(fileURLWithPath: "/")
        case .eu: URL(string: "https://api.eu.amplitude.com/2/httpapi") ?? URL(fileURLWithPath: "/")
        }
    }
}
