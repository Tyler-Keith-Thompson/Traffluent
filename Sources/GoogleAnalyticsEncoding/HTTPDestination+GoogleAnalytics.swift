// The factory takes the stream's Measurement Protocol API secret, which lets anyone holding it send
// events to the property, so it is compiled only where a server runs. iOS, iPadOS, tvOS, watchOS
// and visionOS get none, and nor does Mac Catalyst, which is os(iOS): an app that passes a secret
// fails to compile. A Mac app compiles it, and refuseApplicationBundle refuses it at run time.
// Rejected: a SwiftPM trait or a -D define to opt in, which adopters miss and Bazel would need
// matched.
#if os(macOS) || os(Linux)
import Foundation
public import HTTPDestinations
import Instrumentation
public import TrackingPlans

extension HTTPDestination where Encoding == GoogleAnalyticsBatchEncoder {
    /// A destination on a server that sends batches to the Google Analytics web or data stream of
    /// `measurementID`, authenticated by its `apiSecret`, through `transport`, retrying a send that
    /// fails for now with the waits of `backoff` on `clock`.
    ///
    /// The destination posts to the Measurement Protocol's `/mp/collect` endpoint of `region`, with
    /// the measurement ID and API secret in its query, encoded by a ``GoogleAnalyticsBatchEncoder``
    /// of `plan` within ``GoogleAnalyticsBatchEncoder/batchLimit`` that leaves out each record
    /// tracked more than 72 hours before, or more than 15 minutes after, the time `now` gives as a
    /// batch is encoded. It sends no trace context in its header fields. It retries no response, a
    /// 5xx, 408 or 429, and drops and reports any other status. The Measurement Protocol answers
    /// 2xx to every request it receives, so a wrong measurement ID or API secret, or a request it
    /// can't read, is answered 2xx with nothing stored: check the property's Realtime report after
    /// setting it up.
    ///
    /// The API secret lets anyone holding it send events to the property, so this factory is
    /// for a server, and must never be given a secret in an app. It is compiled for macOS and
    /// Linux alone, so an app for iOS, iPadOS, tvOS, watchOS, visionOS or Mac Catalyst that calls
    /// it fails to compile. A Mac app (AppKit or SwiftUI) compiles it, but the factory refuses it
    /// at run time: it throws ``GoogleAnalyticsSetupError/appBundle`` when the main bundle is an
    /// `.app` or an `.appex`. To get an app's events here, send them to a server of yours that
    /// makes this destination; see the module's article for what that server does.
    ///
    /// The secret is in the query of every request's URL, so don't log the destination, its
    /// requests or a transport's URLs.
    ///
    /// The encoder logs a notice for each event and property of `plan` named as Google Analytics
    /// refuses, or keeps for itself, as every record of that event will be skipped
    /// (``GoogleAnalyticsEncodingError``).
    ///
    /// - Parameters:
    ///   - measurementID: The web or data stream's measurement ID, `G-` followed by letters and
    ///     digits, from the stream's details in Google Analytics' Admin. Whitespace and newlines
    ///     around it are trimmed off.
    ///   - apiSecret: An API secret of the stream, from its Measurement Protocol API secrets in
    ///     Google Analytics' Admin. Whitespace and newlines around it are trimmed off.
    ///   - region: Where Google collects the data: ``GoogleAnalyticsRegion/global``, its default
    ///     endpoint, or ``GoogleAnalyticsRegion/eu``.
    ///   - plan: The tracking plan of every event the destination is given.
    ///   - transport: What sends each request.
    ///   - backoff: How long to wait before each new attempt at a request; 1 second, doubling up
    ///     to 60 seconds, by default.
    ///   - clock: The clock the waits are measured on.
    ///   - now: The wall-clock time a batch is encoded at; the system's clock by default.
    /// - Returns: The destination.
    /// - Throws: ``GoogleAnalyticsSetupError/appBundle`` in an app or an app extension,
    ///   ``GoogleAnalyticsSetupError/emptyMeasurementID`` for a measurement ID that is empty or only
    ///   whitespace, ``GoogleAnalyticsSetupError/malformedMeasurementID`` for one that isn't `G-`
    ///   followed by uppercase ASCII letters and digits, and
    ///   ``GoogleAnalyticsSetupError/emptyAPISecret`` for a secret that is empty or only
    ///   whitespace.
    public static func googleAnalytics(
        measurementID: String,
        apiSecret: String,
        region: GoogleAnalyticsRegion,
        plan: TrackingPlan,
        transport: Transport,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock(),
        now: @escaping @Sendable () -> Date = { Date.now }
    ) throws(GoogleAnalyticsSetupError) -> HTTPDestination<Transport, GoogleAnalyticsBatchEncoder> {
        // The #if keeps the factory out of every app platform but macOS, where an AppKit or SwiftUI
        // app compiles it as a server does; the bundle tells them apart at run time.
        try refuseApplicationBundle(Bundle.main.bundleURL)
        // Trimmed once, so a value pasted with a newline is checked and sent without it.
        let measurementID = measurementID.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiSecret = apiSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !measurementID.isEmpty else {
            throw .emptyMeasurementID
        }
        // Every web stream's measurement ID is G- and uppercase letters and digits ("It usually
        // starts with G-", https://developers.google.com/analytics/devguides/collection/protocol/ga4/sending-events,
        // read on 2026-11-27). The validation server doesn't check the ID, and /mp/collect
        // answers an unknown one with 2xx and stores nothing, so the form is checked here.
        guard measurementID.isMeasurementID else {
            throw .malformedMeasurementID
        }
        guard !apiSecret.isEmpty else {
            throw .emptyAPISecret
        }
        // Google Analytics doesn't read a trace context, so the app's traces aren't sent to it.
        let instrument: any Instrument = NoOpInstrument()
        return HTTPDestination(
            endpoint: region.endpoint(measurementID: measurementID, apiSecret: apiSecret),
            instrument: instrument,
            transport: transport,
            encoder: GoogleAnalyticsBatchEncoder(plan: plan, now: now),
            backoff: backoff,
            clock: clock)
    }
}

extension HTTPDestination where Transport == URLSessionTransport, Encoding == GoogleAnalyticsBatchEncoder {
    /// A destination on a server that sends batches to the Google Analytics web or data stream of
    /// `measurementID`, authenticated by its `apiSecret`, with `URLSession.shared`, retrying a
    /// send that fails for now with the waits of `backoff` on `clock`.
    ///
    /// ```swift
    /// let googleAnalytics = try HTTPDestination.googleAnalytics(
    ///     measurementID: measurementID,  // the web or data stream's, G-…
    ///     apiSecret: apiSecret,  // from the server's configuration, never an app's
    ///     region: .global,  // or .eu, to have Google collect the data in the EU
    ///     plan: plan)
    /// ```
    ///
    /// It is ``HTTPDestinations/HTTPDestination/googleAnalytics(measurementID:apiSecret:region:plan:transport:backoff:clock:now:)``
    /// with a `URLSessionTransport`, compiled for macOS and Linux alone, and refused at run time in
    /// a Mac app: the API secret lets anyone holding it send events to the property, so it must
    /// never ship in an app. The secret is in every request's URL, so don't log the destination,
    /// its requests or a transport's URLs.
    ///
    /// - Parameters:
    ///   - measurementID: The web or data stream's measurement ID, `G-` followed by letters and
    ///     digits. Whitespace and newlines around it are trimmed off.
    ///   - apiSecret: An API secret of the stream. Whitespace and newlines around it are trimmed
    ///     off.
    ///   - region: Where Google collects the data: ``GoogleAnalyticsRegion/global``, its default
    ///     endpoint, or ``GoogleAnalyticsRegion/eu``.
    ///   - plan: The tracking plan of every event the destination is given.
    ///   - backoff: How long to wait before each new attempt at a request; 1 second, doubling up
    ///     to 60 seconds, by default.
    ///   - clock: The clock the waits are measured on.
    ///   - now: The wall-clock time a batch is encoded at; the system's clock by default.
    /// - Returns: The destination.
    /// - Throws: ``GoogleAnalyticsSetupError`` in an app, and for an empty or malformed measurement
    ///   ID or an empty API secret, as the other spelling says.
    public static func googleAnalytics(
        measurementID: String,
        apiSecret: String,
        region: GoogleAnalyticsRegion,
        plan: TrackingPlan,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock(),
        now: @escaping @Sendable () -> Date = { Date.now }
    ) throws(GoogleAnalyticsSetupError) -> HTTPDestination<URLSessionTransport, GoogleAnalyticsBatchEncoder> {
        try googleAnalytics(measurementID: measurementID, apiSecret: apiSecret, region: region, plan: plan, transport: URLSessionTransport(), backoff: backoff, clock: clock, now: now)
    }
}

/// Throws ``GoogleAnalyticsSetupError/appBundle`` when `bundleURL`, the process's main bundle, is
/// an app's or an app extension's: a directory named `.app` or `.appex`. A server, a command-line
/// tool and a test runner have no such bundle, and on Linux `Bundle.main` is the executable's
/// directory.
///
/// - Parameter bundleURL: The main bundle's URL, `Bundle.main.bundleURL` in the factory.
/// - Throws: ``GoogleAnalyticsSetupError/appBundle`` for an app's or an app extension's bundle.
package func refuseApplicationBundle(_ bundleURL: URL) throws(GoogleAnalyticsSetupError) {
    switch bundleURL.pathExtension.lowercased() {
    case "app", "appex": throw .appBundle
    default: return
    }
}

extension GoogleAnalyticsRegion {
    /// The region's `/mp/collect` endpoint for the stream of `measurementID`
    /// (https://developers.google.com/analytics/devguides/collection/protocol/ga4/reference,
    /// "Transport").
    fileprivate func endpoint(measurementID: String, apiSecret: String) -> URL {
        let host = switch self {
        case .global: "www.google-analytics.com"
        case .eu: "region1.google-analytics.com"
        }
        // The measurement ID is letters, digits and `-` once checked. The secret is escaped but for
        // RFC 3986's unreserved characters, as URLComponents leaves `+` unescaped in a query item,
        // which a server may read as a space.
        let query = "measurement_id=\(measurementID)&api_secret=\(apiSecret.percentEncodedForQuery)"
        // Foundation has no non-failable initializer for a URL. Every byte of the query is an
        // unreserved character or a percent escape, so it always parses, the fallback is never
        // taken, and the endpoint tests pin both hosts.
        return URL(string: "https://\(host)/mp/collect?\(query)") ?? URL(fileURLWithPath: "/")
    }
}

extension String {
    /// Whether the string has a measurement ID's form: `G-` and one or more uppercase ASCII letters
    /// or digits.
    fileprivate var isMeasurementID: Bool {
        guard hasPrefix("G-") else { return false }
        let rest = utf8.dropFirst(2)
        return !rest.isEmpty && rest.allSatisfy { (UInt8(ascii: "A") ... UInt8(ascii: "Z")).contains($0) || (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains($0) }
    }

    /// The string with every character but an unreserved one (RFC 3986: ASCII letters, digits,
    /// `-`, `.`, `_`, `~`) as percent escapes of its UTF-8.
    fileprivate var percentEncodedForQuery: String {
        // nil only for a string that isn't valid Unicode, which a Swift String never is.
        addingPercentEncoding(withAllowedCharacters: .urlUnreserved) ?? self
    }
}

extension CharacterSet {
    /// RFC 3986's unreserved characters, the only ones a query's value holds unescaped whatever
    /// reads it.
    fileprivate static let urlUnreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
#endif
