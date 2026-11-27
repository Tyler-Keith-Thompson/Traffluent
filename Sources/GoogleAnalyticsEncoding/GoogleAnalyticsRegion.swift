// Compiled for macOS and Linux alone, as the factory is (HTTPDestination+GoogleAnalytics.swift), so
// nothing in this module can write a Measurement Protocol request in an app for iOS, iPadOS, tvOS,
// watchOS, visionOS or Mac Catalyst.
#if os(macOS) || os(Linux)
// Named after the Measurement Protocol reference's wording: its endpoint, and the one to "use
// instead" if "you want your data to be collected in the EU"
// (https://developers.google.com/analytics/devguides/collection/protocol/ga4/reference, "Transport").
/// Where Google Analytics collects a stream's events, which decides the Measurement Protocol
/// endpoint they are posted to.
///
/// Either endpoint reaches every property; the region only says where Google collects the data.
public enum GoogleAnalyticsRegion: Sendable, Hashable {
    /// Google's default collection endpoint: `https://www.google-analytics.com`.
    case global
    /// Collection in the EU: `https://region1.google-analytics.com`.
    case eu
}
#endif
