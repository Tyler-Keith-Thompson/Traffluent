/// Why ``HTTPDestinations/HTTPDestination/matomo(url:siteID:dimensions:category:plan:transport:backoff:clock:now:)``
/// or ``MatomoBatchEncoder/init(siteID:dimensions:category:plan:limit:now:)`` couldn't be made.
public enum MatomoSetupError: Error, Sendable, Hashable {
    /// The installation's URL isn't an `https` URL with a host name and no user name, password,
    /// query or fragment, or its path ends in a file ending in `.php`, in any case, such as
    /// `matomo.php`. The destination takes the URL Matomo is installed at and appends `matomo.php`
    /// itself, and sends no record in cleartext.
    case invalidURL
    /// The site ID is below 1. Matomo numbers its sites from 1, and files a request for any other
    /// ID under no site.
    case invalidSiteID
    /// The category is empty once Matomo removes its line breaks and trims it, or longer than the
    /// 4,096 characters Matomo stores of an event's category. Matomo refuses an event whose
    /// category is empty.
    case invalidCategory
    /// The dimensions map `property` to `dimension`, which is below 1. Matomo numbers custom
    /// dimensions from 1.
    case invalidDimension(property: String, dimension: Int)
    /// The dimensions map `property` more than once.
    case duplicateProperty(String)
    /// The dimensions map `property`, which no event of the tracking plan has, so no value of it
    /// would ever be sent.
    case unknownProperty(String)
    /// The dimensions map `property`, which is `Sensitive` in the event `event`, at `version`.
    /// Matomo is never sent a `Sensitive` value, so its dimension would never hold one.
    case sensitiveProperty(event: String, version: Int, property: String)
    /// Two properties of the event `event`, at `version`, are mapped to `dimension`, which holds
    /// one value of a request.
    case sharedDimension(event: String, version: Int, dimension: Int)
}
