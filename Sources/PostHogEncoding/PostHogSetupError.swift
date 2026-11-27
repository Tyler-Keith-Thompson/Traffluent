/// Why ``HTTPDestinations/HTTPDestination/postHog(projectToken:host:plan:transport:backoff:clock:)``
/// couldn't make a destination.
public enum PostHogSetupError: Error, Sendable, Hashable {
    /// The project token is empty, or only whitespace. PostHog answers a request without one with
    /// 401 and stores nothing.
    case emptyProjectToken
    /// The token is a personal API key (`phx_...`), not a project token. PostHog refuses one with
    /// 401, and a personal key shipped in an app reads and changes the whole organization's data.
    case personalAPIKey
    /// The host isn't an `https` URL with a host name and no user name, password, query or
    /// fragment, or its path ends in `batch`, as the endpoint's does. The project token travels in
    /// the body, App Transport Security refuses `http` on Apple platforms, and the destination
    /// appends `/batch/` to the host itself.
    case invalidHost
}
