/// Why ``HTTPDestinations/HTTPDestination/amplitude(apiKey:region:plan:transport:backoff:clock:)``
/// couldn't make a destination.
public enum AmplitudeSetupError: Error, Sendable, Hashable {
    /// The API key is empty, or only whitespace. Amplitude answers a request without one with 400
    /// and stores nothing.
    case emptyAPIKey
    /// The key is a deployment key of Amplitude Experiment (`client-...` or `server-...`), not the
    /// project's API key. The HTTP V2 API refuses it as an invalid API key, and a server deployment
    /// key is a secret that must not ship in an app.
    case deploymentKey
}
