// Stand-ins for GoogleAnalyticsEncoding's public types, on the platforms that module leaves them
// out of, for GoogleAnalyticsAvailabilityTests: a file that imports both modules and names one of
// these compiles only while GoogleAnalyticsEncoding declares no type of that name, as two imported
// types of one name make the name ambiguous. Placeholders, not fixtures, so they hold nothing.
#if !(os(macOS) || os(Linux))
/// Stands in for GoogleAnalyticsEncoding's region, which iOS builds leave out.
public enum GoogleAnalyticsRegion: Sendable {
    case global
}

/// Stands in for GoogleAnalyticsEncoding's encoder, which iOS builds leave out.
public enum GoogleAnalyticsBatchEncoder {}

/// Stands in for GoogleAnalyticsEncoding's setup error, which iOS builds leave out.
public enum GoogleAnalyticsSetupError {}

/// Stands in for GoogleAnalyticsEncoding's encoding error, which iOS builds leave out.
public enum GoogleAnalyticsEncodingError {}
#endif
