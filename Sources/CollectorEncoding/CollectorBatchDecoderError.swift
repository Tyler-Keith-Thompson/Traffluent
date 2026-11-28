/// The error ``CollectorBatchDecoder/init(plan:events:instrument:)`` throws: event types it can't
/// read records of.
public enum CollectorBatchDecoderError: Error, Sendable, Hashable {
    /// Two of the event types share an `Event/name` and an `Event/schemaVersion`, which are all a
    /// record names its event by: the name, the version, and the fully qualified names
    /// (`String(reflecting:)`) of the type listed first and the one listed second. Rename one of
    /// them, raise one's version, or leave one out of `events`.
    case duplicateEvent(String, version: Int, firstType: String, secondType: String)
}
