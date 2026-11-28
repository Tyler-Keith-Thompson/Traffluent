public import Foundation
public import HTTPDestinations
import HTTPTypes
import Instrumentation
public import TrackingPlans

extension HTTPDestination where Encoding == AptabaseBatchEncoder {
    /// A destination that sends batches to the Aptabase app of `appKey`, at the region its key
    /// names or, for a self-hosted key, at `host`, marking every event as a debug event or not as
    /// `isDebug` says, through `transport`, retrying a send that fails for now with the waits of
    /// `backoff` on `clock`.
    ///
    /// The destination posts each batch to the events API, `/api/v0/events`, of
    /// `https://eu.aptabase.com` for an `A-EU-` key, `https://us.aptabase.com` for an `A-US-` key,
    /// or `host` for a self-hosted key (`A-SH-`, or `A-DEV-` for a server run in development),
    /// with the key in its `App-Key` header field, encoded by an ``AptabaseBatchEncoder`` within
    /// ``AptabaseBatchEncoder/batchLimit``. It sends no trace context. It retries no response, a
    /// 5xx, 408 or 429, such as Aptabase answers past its rate limit, and 418, which Aptabase
    /// answers when a request's body arrives slower than 60 bytes a second after a 10-second grace
    /// period, as over a poor connection (``AptabaseBatchEncoder/transientStatuses``). It drops and
    /// reports any other status, such as 400 for a request Aptabase can't take.
    ///
    /// The app key is public, as Aptabase's SDKs ship it in every app, and the events API takes no
    /// other credential, so the destination builds on every platform: an app sends to Aptabase
    /// directly.
    ///
    /// Aptabase takes no event tracked more than a day before it arrives, and answers 200 while
    /// storing nothing for one, so the encoder leaves out a record tracked more than 23 hours
    /// before it is encoded (``AptabaseEncodingError/timestampOutsideWindow``). A request is
    /// encoded once and retried as it is, so one still undelivered 23 hours after its oldest
    /// record was tracked, by the time `now` gives, isn't sent again: it is dropped and reported as
    /// `HTTPDropReport.deadlineExceeded(deadline:recordIDs:)`.
    ///
    /// - Parameters:
    ///   - appKey: The app's key, from the Instructions page of its Aptabase dashboard, such as
    ///     `A-EU-1234567890`. Whitespace and newlines around it are trimmed off.
    ///   - host: The URL a self-hosted server is reached at (`https://aptabase.example.com`), a
    ///     path included where it is served under one; required for an `A-SH-` or `A-DEV-` key and
    ///     refused for a cloud key, so `nil` by default. Not the endpoint: the destination appends
    ///     `/api/v0/events` itself.
    ///   - isDebug: Whether every event is a debug event, which Aptabase's dashboard shows only in
    ///     its Debug mode and keeps for less time: `true` for a development or internal build,
    ///     `false` for one users run. There is no default: `#if DEBUG` in a library tells its own
    ///     build configuration, not the app's, so the app decides, from its own build settings.
    ///   - plan: The tracking plan of every event the destination is given.
    ///   - transport: What sends each request.
    ///   - backoff: How long to wait before each new attempt at a request; 1 second, doubling up
    ///     to 60 seconds, with full jitter, by default.
    ///   - clock: The clock the waits are measured on.
    ///   - now: The wall-clock time a batch is encoded at, which the 23 hours are measured from,
    ///     and each request's deadline is checked against before it is sent; the system's clock by
    ///     default. When it reads NaN or infinite, every record is left out.
    /// - Returns: The destination.
    /// - Throws: ``AptabaseSetupError/emptyAppKey`` for a key that is empty or only whitespace,
    ///   ``AptabaseSetupError/malformedAppKey`` for one that isn't `A-<region>-<body>`,
    ///   ``AptabaseSetupError/unknownRegion`` for a region other than `EU`, `US`, `SH` and `DEV`,
    ///   ``AptabaseSetupError/selfHostedAppKeyWithoutHost`` for a self-hosted key without `host`,
    ///   ``AptabaseSetupError/cloudAppKeyWithHost`` for a cloud key with one, and
    ///   ``AptabaseSetupError/invalidHost`` for a host that isn't a plain `https` URL of the
    ///   server.
    public static func aptabase(
        appKey: String,
        host: URL? = nil,
        isDebug: Bool,
        plan: TrackingPlan,
        transport: Transport,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock(),
        now: @escaping @Sendable () -> Date = { Date.now }
    ) throws(AptabaseSetupError) -> HTTPDestination<Transport, AptabaseBatchEncoder> {
        // Trimmed, as a key pasted from a configuration file often ends in a newline.
        let appKey = appKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = try AptabaseRegion(appKey: appKey)
        // An optional host, checked against the key, rather than an enum of hosts or a factory per
        // kind of key: the key's kind is known only at run time, so either would still need the
        // same throws for a cloud key sent to a host and a self-hosted key sent nowhere, with more
        // API to spell it.
        let endpoint: URL
        switch (region, host) {
        case (.eu, nil): endpoint = AptabaseRegion.euEndpoint
        case (.us, nil): endpoint = AptabaseRegion.usEndpoint
        case (.eu, .some), (.us, .some): throw .cloudAppKeyWithHost
        case (.selfHosted, nil): throw .selfHostedAppKeyWithoutHost
        case (.selfHosted, let host?): endpoint = try host.aptabaseEndpoint
        }
        var headerFields: HTTPFields = [:]
        // The name always parses; the key is ASCII letters, digits and dashes, which a field's
        // value always takes.
        if let name = HTTPField.Name("App-Key") {
            headerFields[name] = appKey
        }
        let encoder = AptabaseBatchEncoder(isDebug: isDebug, plan: plan, now: now)
        // Aptabase doesn't read a trace context, so the app's traces aren't sent to it.
        let instrument: any Instrument = NoOpInstrument()
        return HTTPDestination(
            endpoint: endpoint,
            headerFields: headerFields,
            instrument: instrument,
            transport: transport,
            encoder: encoder,
            backoff: backoff,
            clock: clock,
            // One clock for both, so the 23 hours a record is checked against when its batch is
            // encoded are the ones its request's deadline ends.
            now: now)
    }
}

extension HTTPDestination where Transport == URLSessionTransport, Encoding == AptabaseBatchEncoder {
    /// A destination that sends batches to the Aptabase app of `appKey`, at the region its key
    /// names or, for a self-hosted key, at `host`, marking every event as a debug event or not as
    /// `isDebug` says, with `URLSession.shared`, retrying a send that fails for now with the waits
    /// of `backoff` on `clock`.
    ///
    /// ```swift
    /// let aptabase = try HTTPDestination.aptabase(
    ///     appKey: appKey,  // from the app's Instructions page: A-EU-…, A-US-… or A-SH-…
    ///     isDebug: false,  // true for builds whose events only Debug mode should show
    ///     plan: plan)
    /// ```
    ///
    /// It is ``HTTPDestinations/HTTPDestination/aptabase(appKey:host:isDebug:plan:transport:backoff:clock:now:)``
    /// with a `URLSessionTransport`.
    ///
    /// - Parameters:
    ///   - appKey: The app's key, from the Instructions page of its Aptabase dashboard. Whitespace
    ///     and newlines around it are trimmed off.
    ///   - host: The URL a self-hosted server is reached at; required for an `A-SH-` or `A-DEV-`
    ///     key and refused for a cloud key, so `nil` by default.
    ///   - isDebug: Whether every event is a debug event, which Aptabase's dashboard shows only in
    ///     its Debug mode.
    ///   - plan: The tracking plan of every event the destination is given.
    ///   - backoff: How long to wait before each new attempt at a request; 1 second, doubling up
    ///     to 60 seconds, with full jitter, by default.
    ///   - clock: The clock the waits are measured on.
    ///   - now: The wall-clock time a batch is encoded at, which the 23 hours are measured from,
    ///     and each request's deadline is checked against before it is sent; the system's clock by
    ///     default. When it reads NaN or infinite, every record is left out.
    /// - Returns: The destination.
    /// - Throws: ``AptabaseSetupError`` for a key that is empty, malformed or of an unknown region,
    ///   a host missing for a self-hosted key or given for a cloud key, or a host that isn't a
    ///   plain `https` URL, as the other spelling says.
    public static func aptabase(
        appKey: String,
        host: URL? = nil,
        isDebug: Bool,
        plan: TrackingPlan,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock(),
        now: @escaping @Sendable () -> Date = { Date.now }
    ) throws(AptabaseSetupError) -> HTTPDestination<URLSessionTransport, AptabaseBatchEncoder> {
        try aptabase(appKey: appKey, host: host, isDebug: isDebug, plan: plan, transport: URLSessionTransport(), backoff: backoff, clock: clock, now: now)
    }
}

extension AptabaseRegion {
    // Foundation has no non-failable initializer for a literal URL. These literals always parse,
    // so the fallback is never taken, and the endpoint test pins both. The URL macro would check
    // them at compile time, but it would add a macro package to every adopter's build for two
    // literals.
    /// The events API of Aptabase's cloud in the European Union.
    fileprivate static let euEndpoint = URL(string: "https://eu.aptabase.com/api/v0/events") ?? URL(fileURLWithPath: "/")

    /// The events API of Aptabase's cloud in the United States.
    fileprivate static let usEndpoint = URL(string: "https://us.aptabase.com/api/v0/events") ?? URL(fileURLWithPath: "/")
}

extension URL {
    /// The events API of the self-hosted server at this URL: its path, then `/api/v0/events`.
    ///
    /// - Throws: ``AptabaseSetupError/invalidHost`` for a URL that isn't `https`, has no host name,
    ///   has a user name or password, a query or fragment, or a path already ending in
    ///   `/api/v0/events` or `/api/v0/event`, in any case.
    fileprivate var aptabaseEndpoint: URL {
        get throws(AptabaseSetupError) {
            // `https` alone, on every platform and for every host, so events never travel in
            // cleartext. Rejected: allowing `http` for a server on the developer's network; one is
            // reached through a TLS proxy, or an HTTPDestination made by hand.
            guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true),
                  components.scheme?.lowercased() == "https",
                  components.percentEncodedHost?.isEmpty == false,
                  // A password comes with a user name, empty in `https://:secret@host`, so this
                  // refuses both.
                  components.percentEncodedUser == nil,
                  components.percentEncodedQuery == nil,
                  components.percentEncodedFragment == nil
            else {
                throw .invalidHost
            }
            // The percent-encoded path, so an escape in a server's path reaches the request as it
            // was written rather than decoded.
            var path = components.percentEncodedPath
            while path.hasSuffix("/") {
                path.removeLast()
            }
            // The server's URL, not an endpoint, which the destination appends: one spelling for
            // every server. Rejected: taking the endpoint, which would let the single-event
            // endpoint, a typo or the dashboard's URL through to a 404, or to a page answering 200.
            let lowercased = path.lowercased()
            guard !lowercased.hasSuffix("/api/v0/events"), !lowercased.hasSuffix("/api/v0/event") else {
                throw .invalidHost
            }
            components.percentEncodedPath = path + "/api/v0/events"
            guard let endpoint = components.url else { throw .invalidHost }
            return endpoint
        }
    }
}
