/// Why ``HTTPDestinations/HTTPDestination/heap(appID:region:plan:transport:backoff:clock:)`` or
/// ``HeapBatchEncoder/init(appID:plan:limit:)`` couldn't be made.
public enum HeapSetupError: Error, Sendable, Hashable {
    /// The app ID is empty, or only whitespace. Heap's track API requires one, the ID of the
    /// environment its events go to.
    case emptyAppID
    /// The app ID holds a character other than an ASCII digit. A Heap environment's ID is a number,
    /// such as `12343283`; an API key, which only Heap's user deletion API takes and which must not
    /// ship in an app, is not.
    case malformedAppID
}
