public import Foundation
public import HTTPDestinations
import Instrumentation
public import TrackingPlans

extension HTTPDestination where Encoding == MatomoBatchEncoder {
    /// A destination that sends batches to the site `siteID` of the Matomo installation at `url`,
    /// each event in `category` and each property `dimensions` maps as its custom dimension,
    /// through `transport`, retrying a send that fails for now with the waits of `backoff` on
    /// `clock`.
    ///
    /// The destination posts bulk tracking requests to the installation's `matomo.php`, encoded by
    /// a ``MatomoBatchEncoder`` within ``MatomoBatchEncoder/batchLimit``, and sends no trace context
    /// in its header fields. It retries no response, a 5xx, 408 or 429, and drops and reports any
    /// other status, such as 400 for a body Matomo can't read.
    ///
    /// The destination sends no `token_auth`, and takes none: a token is a secret, and any secret
    /// an app holds is public. Matomo takes events from anyone who can reach it, so the destination
    /// builds on every platform. Without a token, Matomo takes no event tracked more than a day
    /// before it arrives, so the encoder leaves out a record tracked more than 23 hours before it
    /// is encoded (``MatomoEncodingError/timestampOutsideWindow``). A request is encoded once and
    /// retried as it is, so one still being retried when its oldest record is a day old is
    /// answered 200 by Matomo and lost without a report.
    ///
    /// - Parameters:
    ///   - url: The URL Matomo is installed at (`https://analytics.example.com`), a path included
    ///     where it is served under one (`https://example.com/matomo/`). Not the endpoint: the
    ///     destination appends `matomo.php` itself.
    ///   - siteID: The site's ID in Matomo, from its Websites settings.
    ///   - dimensions: The custom dimension each property is sent as, by the property's name, as
    ///     made in Matomo's Custom Dimensions settings; a property it doesn't name is never sent.
    ///   - category: Every event's category, `e_c`, such as the app's name. Each event's action,
    ///     `e_a`, is its name.
    ///   - plan: The tracking plan of every event the destination is given.
    ///   - transport: What sends each request.
    ///   - backoff: How long to wait before each new attempt at a request; 1 second, doubling up
    ///     to 60 seconds, by default.
    ///   - clock: The clock the waits are measured on.
    ///   - now: The wall-clock time a batch is encoded at, which the 23 hours are measured from;
    ///     the system's clock by default. When it reads NaN or infinite, every record is left out.
    /// - Returns: The destination.
    /// - Throws: ``MatomoSetupError/invalidURL`` for a URL that isn't `https`, has no host name,
    ///   has a user name or password, a query or fragment, or a path ending in a `.php` file, in
    ///   any case; ``MatomoSetupError/invalidSiteID`` for a site ID below 1;
    ///   ``MatomoSetupError/invalidCategory`` for a category Matomo would empty or cut short; and
    ///   ``MatomoSetupError/invalidDimension(property:dimension:)``,
    ///   ``MatomoSetupError/duplicateProperty(_:)``, ``MatomoSetupError/unknownProperty(_:)``,
    ///   ``MatomoSetupError/sensitiveProperty(event:version:property:)`` or
    ///   ``MatomoSetupError/sharedDimension(event:version:dimension:)`` for a mapping that breaks a
    ///   rule against `plan`.
    public static func matomo(
        url: URL,
        siteID: Int,
        dimensions: MatomoDimensions,
        category: String,
        plan: TrackingPlan,
        transport: Transport,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock(),
        now: @escaping @Sendable () -> Date = { Date.now }
    ) throws(MatomoSetupError) -> HTTPDestination<Transport, MatomoBatchEncoder> {
        let endpoint = try url.matomoEndpoint
        let encoder = try MatomoBatchEncoder(siteID: siteID, dimensions: dimensions, category: category, plan: plan, now: now)
        // Matomo doesn't read a trace context, so the app's traces aren't sent to it.
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

extension HTTPDestination where Transport == URLSessionTransport, Encoding == MatomoBatchEncoder {
    /// A destination that sends batches to the site `siteID` of the Matomo installation at `url`,
    /// each event in `category` and each property `dimensions` maps as its custom dimension, with
    /// `URLSession.shared`, retrying a send that fails for now with the waits of `backoff` on
    /// `clock`.
    ///
    /// ```swift
    /// let matomo = try HTTPDestination.matomo(
    ///     url: url,  // where Matomo is installed: https://analytics.example.com
    ///     siteID: 3,  // the app's site in Matomo
    ///     dimensions: ["plan": 1, "seats": 2],  // custom dimensions made in Matomo
    ///     category: "Shop",  // each event's category
    ///     plan: plan)
    /// ```
    ///
    /// It is ``HTTPDestinations/HTTPDestination/matomo(url:siteID:dimensions:category:plan:transport:backoff:clock:now:)``
    /// with a `URLSessionTransport`.
    ///
    /// - Parameters:
    ///   - url: The URL Matomo is installed at (`https://analytics.example.com`), a path included
    ///     where it is served under one.
    ///   - siteID: The site's ID in Matomo.
    ///   - dimensions: The custom dimension each property is sent as, by the property's name.
    ///   - category: Every event's category, `e_c`, such as the app's name.
    ///   - plan: The tracking plan of every event the destination is given.
    ///   - backoff: How long to wait before each new attempt at a request; 1 second, doubling up
    ///     to 60 seconds, by default.
    ///   - clock: The clock the waits are measured on.
    ///   - now: The wall-clock time a batch is encoded at, which the 23 hours are measured from;
    ///     the system's clock by default. When it reads NaN or infinite, every record is left out.
    /// - Returns: The destination.
    /// - Throws: ``MatomoSetupError`` for a URL that isn't a plain `https` URL of the installation,
    ///   a site ID below 1, a category Matomo would empty or cut short, or a mapping that breaks a
    ///   rule against `plan`, as the other spelling says.
    public static func matomo(
        url: URL,
        siteID: Int,
        dimensions: MatomoDimensions,
        category: String,
        plan: TrackingPlan,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock(),
        now: @escaping @Sendable () -> Date = { Date.now }
    ) throws(MatomoSetupError) -> HTTPDestination<URLSessionTransport, MatomoBatchEncoder> {
        try matomo(url: url, siteID: siteID, dimensions: dimensions, category: category, plan: plan, transport: URLSessionTransport(), backoff: backoff, clock: clock, now: now)
    }
}

extension URL {
    /// The bulk tracking endpoint of the Matomo installation at this URL: its path, then
    /// `/matomo.php`.
    ///
    /// - Throws: ``MatomoSetupError/invalidURL`` for a URL that isn't `https`, has no host name,
    ///   has a user name or password, a query or fragment, or a path whose last component ends in
    ///   `.php`, in any case.
    fileprivate var matomoEndpoint: URL {
        get throws(MatomoSetupError) {
            // `https` alone, on every platform and for every host, so events never travel in
            // cleartext. Rejected: allowing `http` for an installation on the developer's network;
            // one is reached through a TLS proxy, or an HTTPDestination made by hand.
            guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true),
                  components.scheme?.lowercased() == "https",
                  components.percentEncodedHost?.isEmpty == false,
                  // A password comes with a user name, empty in `https://:secret@host`, so this
                  // refuses both.
                  components.percentEncodedUser == nil,
                  components.percentEncodedQuery == nil,
                  components.percentEncodedFragment == nil
            else {
                throw .invalidURL
            }
            // The percent-encoded path, so an escape in an installation's path reaches the request
            // as it was written rather than decoded.
            var path = components.percentEncodedPath
            while path.hasSuffix("/") {
                path.removeLast()
            }
            // The installation's URL, not an endpoint: a `.php` file is the tracker itself
            // (matomo.php, or piwik.php, its old name), which the destination appends. Taking the
            // installation's URL alone means one spelling for every installation. Rejected:
            // taking the endpoint, which would let a typo in its name, an index.php or the
            // reporting API's URL through to a 404 or a page answering 200 for every request.
            guard path.split(separator: "/").last?.lowercased().hasSuffix(".php") != true else {
                throw .invalidURL
            }
            components.percentEncodedPath = path + "/matomo.php"
            guard let endpoint = components.url else { throw .invalidURL }
            return endpoint
        }
    }
}
