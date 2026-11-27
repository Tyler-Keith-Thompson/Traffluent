/// Why ``HTTPDestinations/HTTPDestination/rudderStack(writeKey:dataPlane:plan:transport:backoff:clock:)``
/// couldn't make a destination.
public enum RudderStackSetupError: Error, Sendable, Hashable {
    /// The write key is empty, or only whitespace. RudderStack answers a request without one with
    /// 401 and stores nothing.
    case emptyWriteKey
    /// The data plane URL isn't an `https` URL with a host name and no user name, password, query
    /// or fragment, or its path ends in `v1` or `batch`, in any case, as the endpoint's does. The
    /// write key travels in a header field and is never sent in cleartext, on any platform or host,
    /// and the destination appends `/v1/batch` to the data plane itself.
    case invalidDataPlane
}
