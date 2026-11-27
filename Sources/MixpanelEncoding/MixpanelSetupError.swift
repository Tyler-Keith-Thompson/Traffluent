/// Why ``HTTPDestinations/HTTPDestination/mixpanel(projectToken:region:plan:transport:backoff:clock:)``
/// couldn't make a destination.
public enum MixpanelSetupError: Error, Sendable, Hashable {
    /// The project token is empty, or only whitespace. Mixpanel ingests nothing without one.
    case emptyProjectToken
    /// The token holds a character other than an ASCII letter or digit. Every Mixpanel project
    /// token is alphanumeric, and a service account's username (`name.1a2b3c.mp-service-account`)
    /// is not, nor a credential for Mixpanel's import API, which must not ship in an app. Mixpanel
    /// answers a request with a token it doesn't know with 200 and stores nothing, so the factory
    /// refuses a malformed one when the destination is made.
    case malformedProjectToken
}
