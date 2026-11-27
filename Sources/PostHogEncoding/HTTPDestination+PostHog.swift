public import Foundation
public import HTTPDestinations
import Instrumentation
public import TrackingPlans

extension HTTPDestination where Encoding == PostHogBatchEncoder {
    /// A destination that sends batches to the PostHog project of `projectToken` at `host`
    /// through `transport`, retrying a send that fails for now with the waits of `backoff` on
    /// `clock`.
    ///
    /// The destination posts to `host`'s `/batch/`, encoded by a ``PostHogBatchEncoder`` of
    /// `plan` within ``PostHogBatchEncoder/batchLimit``, and sends no trace context in its header
    /// fields. It retries what PostHog says to retry, no response, a 5xx, 408 or 429, and drops and
    /// reports any other status.
    ///
    /// - Parameters:
    ///   - projectToken: The project's token (`phc_...`), from the project's settings. Whitespace
    ///     and newlines around it are trimmed off.
    ///   - host: The instance's URL: `https://us.i.posthog.com` for US Cloud,
    ///     `https://eu.i.posthog.com` for EU Cloud, or your self-hosted instance's, a path
    ///     included where it is served under one. Not the endpoint: the destination appends
    ///     `/batch/` itself.
    ///   - plan: The tracking plan of every event the destination is given.
    ///   - transport: What sends each request.
    ///   - backoff: How long to wait before each new attempt at a request; 1 second, doubling up
    ///     to 60 seconds, by default.
    ///   - clock: The clock the waits are measured on.
    /// - Returns: The destination.
    /// - Throws: ``PostHogSetupError/emptyProjectToken`` for a token that is empty or only
    ///   whitespace, ``PostHogSetupError/personalAPIKey`` for a personal API key (`phx_...`), and
    ///   ``PostHogSetupError/invalidHost`` for a host that isn't `https`, has no host name, has a
    ///   user name or password, a query or fragment, or a path whose last component is `batch`.
    public static func postHog(
        projectToken: String,
        host: URL,
        plan: TrackingPlan,
        transport: Transport,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock()
    ) throws(PostHogSetupError) -> HTTPDestination<Transport, PostHogBatchEncoder> {
        // Trimmed once, so a token pasted with a newline is checked and sent without it.
        let projectToken = projectToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectToken.isEmpty else {
            throw .emptyProjectToken
        }
        // Case-sensitive: PostHog issues personal API keys with a lowercase `phx_`, and a token
        // spelled otherwise is none of its keys, so refusing it would refuse what isn't a secret.
        guard !projectToken.hasPrefix("phx_") else {
            throw .personalAPIKey
        }
        // PostHog doesn't read a trace context, so the app's traces aren't sent to it.
        let instrument: any Instrument = NoOpInstrument()
        return HTTPDestination(
            endpoint: try host.postHogBatchEndpoint,
            instrument: instrument,
            transport: transport,
            encoder: PostHogBatchEncoder(projectToken: projectToken, plan: plan),
            backoff: backoff,
            clock: clock)
    }
}

extension HTTPDestination where Transport == URLSessionTransport, Encoding == PostHogBatchEncoder {
    /// A destination that sends batches to the PostHog project of `projectToken` at `host` with
    /// `URLSession.shared`, retrying a send that fails for now with the waits of `backoff` on
    /// `clock`.
    ///
    /// ```swift
    /// let postHog = try HTTPDestination.postHog(
    ///     projectToken: "phc_…",
    ///     host: postHogHost,  // https://eu.i.posthog.com
    ///     plan: plan)
    /// ```
    ///
    /// It is ``HTTPDestinations/HTTPDestination/postHog(projectToken:host:plan:transport:backoff:clock:)``
    /// with a `URLSessionTransport`.
    ///
    /// - Parameters:
    ///   - projectToken: The project's token (`phc_...`), from the project's settings. Whitespace
    ///     and newlines around it are trimmed off.
    ///   - host: The instance's URL: `https://us.i.posthog.com` for US Cloud,
    ///     `https://eu.i.posthog.com` for EU Cloud, or your self-hosted instance's.
    ///   - plan: The tracking plan of every event the destination is given.
    ///   - backoff: How long to wait before each new attempt at a request; 1 second, doubling up
    ///     to 60 seconds, by default.
    ///   - clock: The clock the waits are measured on.
    /// - Returns: The destination.
    /// - Throws: ``PostHogSetupError`` for an empty token, a personal API key, or a host that
    ///   isn't a plain `https` URL of the instance, as the other spelling says.
    public static func postHog(
        projectToken: String,
        host: URL,
        plan: TrackingPlan,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock()
    ) throws(PostHogSetupError) -> HTTPDestination<URLSessionTransport, PostHogBatchEncoder> {
        try postHog(projectToken: projectToken, host: host, plan: plan, transport: URLSessionTransport(), backoff: backoff, clock: clock)
    }
}

extension URL {
    /// The batch capture endpoint of the PostHog instance at this URL: its path, then `/batch/`.
    ///
    /// - Throws: ``PostHogSetupError/invalidHost`` for a URL that isn't `https`, has no host
    ///   name, has a user name or password, a query or fragment, or a path whose last component
    ///   is `batch`.
    fileprivate var postHogBatchEndpoint: URL {
        get throws(PostHogSetupError) {
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
            // The percent-encoded path, so an escape in a self-hosted instance's path (`%2F`)
            // reaches the request as it was written rather than decoded.
            var path = components.percentEncodedPath
            while path.hasSuffix("/") {
                path.removeLast()
            }
            // The endpoint passed as the host would post to `/batch/batch/`, which PostHog
            // answers with 404, dropping every batch.
            guard path.split(separator: "/").last != "batch" else {
                throw .invalidHost
            }
            components.percentEncodedPath = path + "/batch/"
            guard let endpoint = components.url else { throw .invalidHost }
            return endpoint
        }
    }
}
