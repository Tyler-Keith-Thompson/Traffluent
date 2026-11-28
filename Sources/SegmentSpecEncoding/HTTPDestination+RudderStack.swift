public import Foundation
public import HTTPDestinations
import HTTPTypes
import Instrumentation
public import TrackingPlans

extension HTTPDestination where Encoding == SegmentSpecBatchEncoder {
    /// A destination that sends batches to the RudderStack source of `writeKey`, through the data
    /// plane at `dataPlane`, through `transport`, retrying a send that fails for now with the waits
    /// of `backoff` on `clock`.
    ///
    /// The destination posts to the data plane's `/v1/batch`, encoded by a
    /// ``SegmentSpecBatchEncoder`` of `plan` within ``SegmentSpecBatchEncoder/batchLimit``, with
    /// the write key as HTTP Basic authentication's user name and an empty password, and sends no
    /// trace context in its header fields. It retries no response, a 5xx, 408 or 429, and drops
    /// and reports any other status, such as 400 for an invalid request, 401 for a write key of no
    /// source, or 404 for a disabled source.
    ///
    /// The write key is a public client key, as RudderStack's own app and web SDKs ship it: it lets
    /// a client send data to the source and read nothing.
    ///
    /// Each call carries `context.ip` and a top-level `request_ip` of `"0.0.0.0"`, as RudderStack
    /// otherwise fills in `request_ip` from the request's address and passes it on.
    ///
    /// - Parameters:
    ///   - writeKey: The source's write key, from the source's settings. Whitespace and newlines
    ///     around it are trimmed off.
    ///   - dataPlane: The data plane's URL, from the top of the workspace's Connections page
    ///     (`https://<workspace>dataplane.rudderstack.com`), or a self-hosted data plane's, a path
    ///     included where it is served under one. Not the endpoint: the destination appends
    ///     `/v1/batch` itself.
    ///   - plan: The tracking plan of every event the destination is given.
    ///   - transport: What sends each request.
    ///   - backoff: How long to wait before each new attempt at a request; 1 second, doubling up
    ///     to 60 seconds, with full jitter, by default.
    ///   - clock: The clock the waits are measured on.
    /// - Returns: The destination.
    /// - Throws: ``RudderStackSetupError/emptyWriteKey`` for a write key that is empty or only
    ///   whitespace, and ``RudderStackSetupError/invalidDataPlane`` for a data plane URL that isn't
    ///   `https`, has no host name, has a user name or password, a query or fragment, or a path
    ///   whose last component is `v1` or `batch`, in any case.
    public static func rudderStack(
        writeKey: String,
        dataPlane: URL,
        plan: TrackingPlan,
        transport: Transport,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock()
    ) throws(RudderStackSetupError) -> HTTPDestination<Transport, SegmentSpecBatchEncoder> {
        // Trimmed once, so a key pasted with a newline is checked and sent without it.
        let writeKey = writeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        // RudderStack documents no format for a write key, so only an empty one is refused.
        guard !writeKey.isEmpty else {
            throw .emptyWriteKey
        }
        // RudderStack doesn't read a trace context, so the app's traces aren't sent to it.
        let instrument: any Instrument = NoOpInstrument()
        return HTTPDestination(
            endpoint: try dataPlane.rudderStackBatchEndpoint,
            // The write key as the user name, as RudderStack's curl examples send it (`-u <key>:`)
            // and its SDKs do; its Postman note, which puts the key in the password, is the odd
            // one out.
            headerFields: [.authorization: writeKey.basicAuthorization],
            instrument: instrument,
            transport: transport,
            // With `request_ip`, which RudderStack would otherwise fill in from the request's
            // address, even beside `context.ip`, and pass on to its destinations.
            encoder: SegmentSpecBatchEncoder(plan: plan, sendsRequestIP: true),
            backoff: backoff,
            clock: clock)
    }
}

extension HTTPDestination where Transport == URLSessionTransport, Encoding == SegmentSpecBatchEncoder {
    /// A destination that sends batches to the RudderStack source of `writeKey`, through the data
    /// plane at `dataPlane`, with `URLSession.shared`, retrying a send that fails for now with the
    /// waits of `backoff` on `clock`.
    ///
    /// ```swift
    /// let rudderStack = try HTTPDestination.rudderStack(
    ///     writeKey: writeKey,
    ///     dataPlane: dataPlane,  // https://<workspace>dataplane.rudderstack.com
    ///     plan: plan)
    /// ```
    ///
    /// It is ``HTTPDestinations/HTTPDestination/rudderStack(writeKey:dataPlane:plan:transport:backoff:clock:)``
    /// with a `URLSessionTransport`.
    ///
    /// - Parameters:
    ///   - writeKey: The source's write key, from the source's settings: a public client key.
    ///     Whitespace and newlines around it are trimmed off.
    ///   - dataPlane: The data plane's URL, from the top of the workspace's Connections page, or a
    ///     self-hosted data plane's.
    ///   - plan: The tracking plan of every event the destination is given.
    ///   - backoff: How long to wait before each new attempt at a request; 1 second, doubling up
    ///     to 60 seconds, with full jitter, by default.
    ///   - clock: The clock the waits are measured on.
    /// - Returns: The destination.
    /// - Throws: ``RudderStackSetupError`` for an empty write key, or a data plane URL that isn't a
    ///   plain `https` URL of the data plane, as the other spelling says.
    public static func rudderStack(
        writeKey: String,
        dataPlane: URL,
        plan: TrackingPlan,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock()
    ) throws(RudderStackSetupError) -> HTTPDestination<URLSessionTransport, SegmentSpecBatchEncoder> {
        try rudderStack(writeKey: writeKey, dataPlane: dataPlane, plan: plan, transport: URLSessionTransport(), backoff: backoff, clock: clock)
    }
}

extension URL {
    /// The batch endpoint of the RudderStack data plane at this URL: its path, then `/v1/batch`.
    ///
    /// - Throws: ``RudderStackSetupError/invalidDataPlane`` for a URL that isn't `https`, has no
    ///   host name, has a user name or password, a query or fragment, or a path whose last
    ///   component is `v1` or `batch`, in any case.
    fileprivate var rudderStackBatchEndpoint: URL {
        get throws(RudderStackSetupError) {
            // `https` alone, on every platform and for every host, so the write key, which travels
            // in a header field, is never sent in cleartext. Rejected: allowing `http` for
            // loopback or private hosts, for a data plane on the developer's machine or network;
            // one is reached through a TLS tunnel or proxy instead.
            guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true),
                  components.scheme?.lowercased() == "https",
                  components.percentEncodedHost?.isEmpty == false,
                  // A password comes with a user name, empty in `https://:secret@host`, so this
                  // refuses both.
                  components.percentEncodedUser == nil,
                  components.percentEncodedQuery == nil,
                  components.percentEncodedFragment == nil
            else {
                throw .invalidDataPlane
            }
            // The percent-encoded path, so an escape in a self-hosted data plane's path reaches
            // the request as it was written rather than decoded.
            var path = components.percentEncodedPath
            while path.hasSuffix("/") {
                path.removeLast()
            }
            // The endpoint, or its `/v1`, passed as the data plane would post to
            // `/v1/batch/v1/batch` or `/v1/v1/batch`, which RudderStack answers with 404,
            // dropping every batch. In any case, as `/V1` or `/Batch` is as likely a slip.
            let last = path.split(separator: "/").last?.lowercased()
            guard last != "v1", last != "batch" else {
                throw .invalidDataPlane
            }
            components.percentEncodedPath = path + "/v1/batch"
            guard let endpoint = components.url else { throw .invalidDataPlane }
            return endpoint
        }
    }
}
