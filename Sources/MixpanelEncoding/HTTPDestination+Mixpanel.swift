import Foundation
public import HTTPDestinations
import Instrumentation
public import TrackingPlans

extension HTTPDestination where Encoding == MixpanelBatchEncoder {
    /// A destination that sends batches to the Mixpanel project of `projectToken`, whose data
    /// resides in `region`, through `transport`, retrying a send that fails for now with the waits
    /// of `backoff` on `clock`.
    ///
    /// The destination posts to the `/track` endpoint of `region`, encoded by a
    /// ``MixpanelBatchEncoder`` of `plan` within ``MixpanelBatchEncoder/batchLimit``, with `ip=0`,
    /// so Mixpanel adds no location from the request's address, and sends no trace context in its
    /// header fields. It retries what Mixpanel says to retry, no response, a 5xx, 408 or 429, and
    /// drops and reports any other status, such as 400 for an invalid request. Mixpanel answers
    /// 200 for a request whose events it doesn't store, so a wrong region, or a token of no
    /// project, may be answered 200 with nothing stored: check the project's Live View after
    /// setting it up.
    ///
    /// The encoder logs a notice for each property of `plan` named as one Mixpanel reserves, as
    /// every record of its event will be skipped
    /// (``MixpanelEncodingError/reservedPropertyName(event:property:)``).
    ///
    /// The track API takes the project token, which is public, so the destination takes nothing
    /// else: never the project's secret or a service account's credentials, which Mixpanel's
    /// import API takes and which must not ship in an app.
    ///
    /// - Parameters:
    ///   - projectToken: The project's token, from the project's settings. Whitespace and newlines
    ///     around it are trimmed off.
    ///   - region: Where the project's data resides: ``MixpanelRegion/us``, Mixpanel's default,
    ///     ``MixpanelRegion/eu`` or ``MixpanelRegion/india``.
    ///   - plan: The tracking plan of every event the destination is given.
    ///   - transport: What sends each request.
    ///   - backoff: How long to wait before each new attempt at a request; 1 second, doubling up
    ///     to 60 seconds, by default.
    ///   - clock: The clock the waits are measured on.
    /// - Returns: The destination.
    /// - Throws: ``MixpanelSetupError/emptyProjectToken`` for a token that is empty or only
    ///   whitespace, and ``MixpanelSetupError/malformedProjectToken`` for one holding a character
    ///   other than an ASCII letter or digit.
    public static func mixpanel(
        projectToken: String,
        region: MixpanelRegion,
        plan: TrackingPlan,
        transport: Transport,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock()
    ) throws(MixpanelSetupError) -> HTTPDestination<Transport, MixpanelBatchEncoder> {
        // Trimmed once, so a token pasted with a newline is checked and sent without it.
        let projectToken = projectToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectToken.isEmpty else {
            throw .emptyProjectToken
        }
        // Mixpanel's project tokens are alphanumeric (Project Token,
        // https://docs.mixpanel.com/reference/project-token), and it answers a token it doesn't
        // know with 200 while storing nothing. A length or hex rule isn't documented, and a
        // project's secret looks like its token, so only the characters are checked.
        guard projectToken.utf8.allSatisfy(\.isASCIIAlphanumeric) else {
            throw .malformedProjectToken
        }
        // Mixpanel doesn't read a trace context, so the app's traces aren't sent to it.
        let instrument: any Instrument = NoOpInstrument()
        return HTTPDestination(
            endpoint: region.endpoint,
            instrument: instrument,
            transport: transport,
            encoder: MixpanelBatchEncoder(projectToken: projectToken, plan: plan),
            backoff: backoff,
            clock: clock)
    }
}

extension HTTPDestination where Transport == URLSessionTransport, Encoding == MixpanelBatchEncoder {
    /// A destination that sends batches to the Mixpanel project of `projectToken`, whose data
    /// resides in `region`, with `URLSession.shared`, retrying a send that fails for now with the
    /// waits of `backoff` on `clock`.
    ///
    /// ```swift
    /// let mixpanel = try HTTPDestination.mixpanel(
    ///     projectToken: projectToken,
    ///     region: .us,  // or .eu or .india, where the project's data resides
    ///     plan: plan)
    /// ```
    ///
    /// It is ``HTTPDestinations/HTTPDestination/mixpanel(projectToken:region:plan:transport:backoff:clock:)``
    /// with a `URLSessionTransport`.
    ///
    /// - Parameters:
    ///   - projectToken: The project's token, from the project's settings; never its secret or a
    ///     service account's credentials. Whitespace and newlines around it are trimmed off.
    ///   - region: Where the project's data resides: ``MixpanelRegion/us``, Mixpanel's default,
    ///     ``MixpanelRegion/eu`` or ``MixpanelRegion/india``.
    ///   - plan: The tracking plan of every event the destination is given.
    ///   - backoff: How long to wait before each new attempt at a request; 1 second, doubling up
    ///     to 60 seconds, by default.
    ///   - clock: The clock the waits are measured on.
    /// - Returns: The destination.
    /// - Throws: ``MixpanelSetupError`` for an empty or malformed token, as the other spelling
    ///   says.
    public static func mixpanel(
        projectToken: String,
        region: MixpanelRegion,
        plan: TrackingPlan,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock()
    ) throws(MixpanelSetupError) -> HTTPDestination<URLSessionTransport, MixpanelBatchEncoder> {
        try mixpanel(projectToken: projectToken, region: region, plan: plan, transport: URLSessionTransport(), backoff: backoff, clock: clock)
    }
}

extension MixpanelRegion {
    /// The region's `/track` endpoint, with `ip=0` (https://developer.mixpanel.com/reference/track-event).
    fileprivate var endpoint: URL {
        // Foundation has no non-failable initializer for a literal URL. These literals always
        // parse, so the fallback is never taken, and the endpoint test pins all three. The URL
        // macro would check them at compile time, but it would add a macro package to every
        // adopter's build for three literals.
        switch self {
        case .us: URL(string: "https://api.mixpanel.com/track?ip=0") ?? URL(fileURLWithPath: "/")
        case .eu: URL(string: "https://api-eu.mixpanel.com/track?ip=0") ?? URL(fileURLWithPath: "/")
        case .india: URL(string: "https://api-in.mixpanel.com/track?ip=0") ?? URL(fileURLWithPath: "/")
        }
    }
}

extension UInt8 {
    /// Whether the byte is an ASCII letter or digit, the only characters of a Mixpanel project
    /// token.
    fileprivate var isASCIIAlphanumeric: Bool {
        (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(self)
            || (UInt8(ascii: "a") ... UInt8(ascii: "z")).contains(self)
            || (UInt8(ascii: "A") ... UInt8(ascii: "Z")).contains(self)
    }
}
