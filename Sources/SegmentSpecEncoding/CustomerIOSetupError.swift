/// Why ``HTTPDestinations/HTTPDestination/customerIO(apiKey:region:plan:transport:backoff:clock:)``
/// couldn't make a destination.
public enum CustomerIOSetupError: Error, Sendable, Hashable {
    /// The key is empty, or only whitespace. Customer.io ingests nothing without one.
    case emptyAPIKey
    /// The key is a private key (`sk_...`), not a public one (`pk_...`). A private key reaches
    /// every Customer.io API, deleting and suppressing people included, and must not ship in an
    /// app.
    case privateKey
    /// The key's region (`pk_us_...` or `pk_eu_...`) isn't the region given. A key belongs to its
    /// region's data center, so the other region's endpoint refuses it.
    case regionMismatch
}
