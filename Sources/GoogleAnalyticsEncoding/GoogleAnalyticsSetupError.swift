// Compiled for macOS and Linux alone, as the factory is (HTTPDestination+GoogleAnalytics.swift), so
// nothing in this module can write a Measurement Protocol request in an app for iOS, iPadOS, tvOS,
// watchOS, visionOS or Mac Catalyst.
#if os(macOS) || os(Linux)
/// Why ``HTTPDestinations/HTTPDestination/googleAnalytics(measurementID:apiSecret:region:plan:transport:backoff:clock:now:)``
/// couldn't make a destination.
public enum GoogleAnalyticsSetupError: Error, Sendable, Hashable {
    /// The measurement ID is empty, or only whitespace.
    case emptyMeasurementID
    /// The measurement ID isn't `G-` followed by uppercase ASCII letters and digits, the form of
    /// every web stream's ID (`G-1A2B3C4D5E`). The Measurement Protocol answers a request for a
    /// stream it doesn't know with 2xx and stores nothing, so the factory refuses a malformed ID
    /// when the destination is made. A stream ID, an app stream's Firebase app ID, a Universal
    /// Analytics ID (`UA-…`) or a Google tag ID (`GT-…`) is refused as well.
    case malformedMeasurementID
    /// The API secret is empty, or only whitespace. The Measurement Protocol stores nothing for a
    /// request without one.
    case emptyAPISecret
    /// The process is an app or an app extension: its main bundle is an `.app` or `.appex`
    /// directory. The factory is compiled for macOS so a server written for it can run there, and a
    /// Mac app compiles it too, but an app ships the API secret to everyone who installs it, and
    /// anyone holding the secret can send events to the property. Send the app's events to a relay
    /// of yours instead, which forwards them to Google Analytics.
    case appBundle
}
#endif
