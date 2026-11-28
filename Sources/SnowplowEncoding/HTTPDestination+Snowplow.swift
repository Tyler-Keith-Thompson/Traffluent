public import Foundation
public import HTTPDestinations
import HTTPTypes
import Instrumentation
public import TrackingPlans

extension HTTPDestination where Encoding == SnowplowBatchEncoder {
    /// A destination that sends batches to the Snowplow collector at `collector`, as self-describing
    /// events whose schemas are `plan`'s under `vendor`, from the app `appID`, through `transport`,
    /// retrying a send that fails for now with the waits of `backoff` on `clock`.
    ///
    /// The destination posts to the collector's `/com.snowplowanalytics.snowplow/tp2`, the tracker
    /// protocol's endpoint, encoded by a ``SnowplowBatchEncoder`` within
    /// ``SnowplowBatchEncoder/batchLimit``, and sends no trace context in its header fields. It
    /// retries no response, a 5xx, 408 or 429, and drops and reports any other status, such as 413
    /// for a body over the collector's limit.
    ///
    /// Every request carries `SP-Anonymous: *`, so the collector sets no `sp` cookie, reads none,
    /// takes `network_userid` as all zeros, and records no IP address or forwarding header fields.
    /// Without it the collector would set a cookie that `URLSession` keeps and sends back, an
    /// identifier lasting across sessions (D4).
    ///
    /// A collector takes events from anyone who can reach it, so the destination needs no key or
    /// secret, and builds on every platform.
    ///
    /// - Parameters:
    ///   - collector: The collector's URL (`https://collector.example.com`), a path included
    ///     where it is served under one. Not the endpoint: the destination appends
    ///     `/com.snowplowanalytics.snowplow/tp2` itself.
    ///   - vendor: The Iglu vendor of the events' schemas, in reverse domain notation
    ///     (`com.acme`): the one the tracking plan's Iglu export is given.
    ///   - appID: The app's ID, each event's `aid`, which tells apart the apps and sites that send
    ///     to one pipeline.
    ///   - plan: The tracking plan of every event the destination is given.
    ///   - transport: What sends each request.
    ///   - backoff: How long to wait before each new attempt at a request; 1 second, doubling up
    ///     to 60 seconds, with full jitter, by default.
    ///   - clock: The clock the waits are measured on.
    /// - Returns: The destination.
    /// - Throws: ``SnowplowSetupError/invalidCollector`` for a collector URL that isn't `https`,
    ///   has no host name, has a user name or password, a query or fragment, or a path ending in
    ///   `tp2` or `com.snowplowanalytics.snowplow`, in any case;
    ///   ``SnowplowSetupError/invalidVendor`` for a vendor Iglu doesn't take; and
    ///   ``SnowplowSetupError/invalidAppID`` for an empty app ID or one longer than 255 UTF-16
    ///   code units.
    public static func snowplow(
        collector: URL,
        vendor: String,
        appID: String,
        plan: TrackingPlan,
        transport: Transport,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock()
    ) throws(SnowplowSetupError) -> HTTPDestination<Transport, SnowplowBatchEncoder> {
        let endpoint = try collector.snowplowEndpoint
        let encoder = try SnowplowBatchEncoder(vendor: vendor, appID: appID, plan: plan)
        // Snowplow doesn't read a trace context, so the app's traces aren't sent to it.
        let instrument: any Instrument = NoOpInstrument()
        var headerFields: HTTPFields = [:]
        // Always made: the name is a valid field name, letters and a hyphen. The header field
        // keeps the collector from setting its network_userid cookie, which URLSession would
        // keep and send with every later request, and from recording the request's address.
        if let anonymous = HTTPField.Name("SP-Anonymous") {
            headerFields[anonymous] = "*"
        }
        return HTTPDestination(
            endpoint: endpoint,
            headerFields: headerFields,
            instrument: instrument,
            transport: transport,
            encoder: encoder,
            backoff: backoff,
            clock: clock)
    }
}

extension HTTPDestination where Transport == URLSessionTransport, Encoding == SnowplowBatchEncoder {
    /// A destination that sends batches to the Snowplow collector at `collector`, as self-describing
    /// events whose schemas are `plan`'s under `vendor`, from the app `appID`, with
    /// `URLSession.shared`, retrying a send that fails for now with the waits of `backoff` on
    /// `clock`.
    ///
    /// ```swift
    /// let snowplow = try HTTPDestination.snowplow(
    ///     collector: collector,  // https://collector.example.com
    ///     vendor: "com.example",  // your schemas' Iglu vendor
    ///     appID: "shop-ios",
    ///     plan: plan)
    /// ```
    ///
    /// It is ``HTTPDestinations/HTTPDestination/snowplow(collector:vendor:appID:plan:transport:backoff:clock:)``
    /// with a `URLSessionTransport`.
    ///
    /// - Parameters:
    ///   - collector: The collector's URL (`https://collector.example.com`), a path included
    ///     where it is served under one.
    ///   - vendor: The Iglu vendor of the events' schemas, in reverse domain notation (`com.acme`).
    ///   - appID: The app's ID, each event's `aid`.
    ///   - plan: The tracking plan of every event the destination is given.
    ///   - backoff: How long to wait before each new attempt at a request; 1 second, doubling up
    ///     to 60 seconds, with full jitter, by default.
    ///   - clock: The clock the waits are measured on.
    /// - Returns: The destination.
    /// - Throws: ``SnowplowSetupError`` for a collector URL that isn't a plain `https` URL of the
    ///   collector, a vendor Iglu doesn't take, or an empty or overlong app ID, as the other
    ///   spelling says.
    public static func snowplow(
        collector: URL,
        vendor: String,
        appID: String,
        plan: TrackingPlan,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock()
    ) throws(SnowplowSetupError) -> HTTPDestination<URLSessionTransport, SnowplowBatchEncoder> {
        try snowplow(collector: collector, vendor: vendor, appID: appID, plan: plan, transport: URLSessionTransport(), backoff: backoff, clock: clock)
    }
}

extension URL {
    /// The tracker protocol's endpoint of the collector at this URL: its path, then
    /// `/com.snowplowanalytics.snowplow/tp2`.
    ///
    /// - Throws: ``SnowplowSetupError/invalidCollector`` for a URL that isn't `https`, has no host
    ///   name, has a user name or password, a query or fragment, or a path whose last component is
    ///   `tp2` or `com.snowplowanalytics.snowplow`, in any case.
    fileprivate var snowplowEndpoint: URL {
        get throws(SnowplowSetupError) {
            // `https` alone, on every platform and for every host, so events never travel in
            // cleartext. Rejected: allowing `http` for a collector on the developer's machine or
            // network, such as Snowplow Micro; one is reached through a TLS tunnel or proxy, or an
            // HTTPDestination made by hand.
            guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true),
                  components.scheme?.lowercased() == "https",
                  components.percentEncodedHost?.isEmpty == false,
                  // A password comes with a user name, empty in `https://:secret@host`, so this
                  // refuses both.
                  components.percentEncodedUser == nil,
                  components.percentEncodedQuery == nil,
                  components.percentEncodedFragment == nil
            else {
                throw .invalidCollector
            }
            // The percent-encoded path, so an escape in a collector's path reaches the request as
            // it was written rather than decoded.
            var path = components.percentEncodedPath
            while path.hasSuffix("/") {
                path.removeLast()
            }
            // The endpoint, or its first component, passed as the collector would post to
            // `/com.snowplowanalytics.snowplow/tp2/com.snowplowanalytics.snowplow/tp2`, a path no
            // collector serves. In any case, as `/TP2` is as likely a slip.
            let last = path.split(separator: "/").last?.lowercased()
            guard last != "tp2", last != "com.snowplowanalytics.snowplow" else {
                throw .invalidCollector
            }
            components.percentEncodedPath = path + "/com.snowplowanalytics.snowplow/tp2"
            guard let endpoint = components.url else { throw .invalidCollector }
            return endpoint
        }
    }
}
