/// Why ``HTTPDestinations/HTTPDestination/aptabase(appKey:host:isDebug:plan:transport:backoff:clock:now:)``
/// couldn't be made.
public enum AptabaseSetupError: Error, Sendable, Hashable {
    /// The app key is empty, or only whitespace. Aptabase's events API files every event under the
    /// app of its key.
    case emptyAppKey
    /// The app key isn't `A-`, a region, `-` and a body of ASCII letters and digits, such as
    /// `A-EU-1234567890`: it has more or fewer than three parts, a first part other than `A`, or a
    /// body that is empty or holds another character.
    case malformedAppKey
    /// The app key's region, its second part, is none Aptabase makes keys for: `EU` and `US`, its
    /// cloud's regions, `SH`, a self-hosted server's, and `DEV`, a server run in development. A
    /// region is written in capitals, as Aptabase writes it.
    case unknownRegion
    /// The app key is a self-hosted server's (`A-SH-`) or a development server's (`A-DEV-`), and
    /// no host was given: only the app knows where its server is.
    case selfHostedAppKeyWithoutHost
    /// A host was given with a key of Aptabase's cloud (`A-EU-` or `A-US-`), whose events go to
    /// the region the key names. A host is for a self-hosted key alone, so a cloud key is never
    /// sent to another server.
    case cloudAppKeyWithHost
    /// The host isn't an `https` URL with a host name and no user name, password, query or
    /// fragment, or its path already ends in `/api/v0/events` or `/api/v0/event`, in any case. The
    /// destination takes the URL the server is reached at and appends the endpoint itself, and
    /// sends no record in cleartext.
    case invalidHost
}
