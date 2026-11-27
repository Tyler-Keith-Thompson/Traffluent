/// Why ``HTTPDestinations/HTTPDestination/segment(writeKey:region:plan:transport:backoff:clock:)``
/// couldn't make a destination.
public enum SegmentSetupError: Error, Sendable, Hashable {
    /// The write key is empty, or only whitespace. Segment ingests nothing without one, and may
    /// answer the request with 200 all the same, so the factory refuses it when the destination is
    /// made.
    case emptyWriteKey
}
