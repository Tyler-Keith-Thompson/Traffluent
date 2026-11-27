/// Why ``HTTPDestinations/HTTPDestination/snowplow(collector:vendor:appID:plan:transport:backoff:clock:)``
/// or ``SnowplowBatchEncoder/init(vendor:appID:plan:limit:)`` couldn't be made.
public enum SnowplowSetupError: Error, Sendable, Hashable {
    /// The collector's URL isn't an `https` URL with a host name and no user name, password, query
    /// or fragment, or its path already ends in the tracker protocol's endpoint
    /// (`/com.snowplowanalytics.snowplow/tp2`, or its last component), in any case. The destination
    /// appends the endpoint itself, and sends events in cleartext to no host.
    case invalidCollector
    /// The vendor isn't one Iglu takes in reverse domain notation: labels of ASCII letters,
    /// digits, `-` and `_`, joined by `.`, none of them empty (`com.acme`). Every event's schema
    /// URI names it, so a collector would fail every event.
    case invalidVendor
    /// The app ID is empty, or longer than the 255 UTF-16 code units Snowplow's `app_id` holds,
    /// which fails every event in enrichment.
    case invalidAppID
}
