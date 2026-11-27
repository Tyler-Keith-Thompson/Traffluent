/// Why ``HTTPDestinations/HTTPDestination/telemetryDeck(appID:namespace:testMode:plan:transport:backoff:clock:)``
/// or ``TelemetryDeckBatchEncoder/init(appID:testMode:plan:limit:)`` couldn't be made.
public enum TelemetryDeckSetupError: Error, Sendable, Hashable {
    /// The app ID is empty, or only whitespace. TelemetryDeck files an event without one under no
    /// app, where no app's dashboard shows it.
    case emptyAppID
    /// The namespace isn't one TelemetryDeck takes: it is empty, holds a character other than an
    /// ASCII letter, digit, `.`, `_` or `-`, is `.` or `..`, which a URL's path reads as no
    /// segment, or is `w`, the path of TelemetryDeck's web endpoint. TelemetryDeck refuses every
    /// event sent to a namespace it doesn't take.
    case invalidNamespace
}
