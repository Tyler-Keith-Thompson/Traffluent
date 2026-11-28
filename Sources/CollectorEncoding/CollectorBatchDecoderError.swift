/// The error ``CollectorBatchDecoder/init(plan:events:instrument:)`` throws: event types it can't
/// read records of.
public enum CollectorBatchDecoderError: Error, Sendable, Hashable {
    /// Two of the event types share an `Event/name`, which is all a record names its event by:
    /// the name, and the fully qualified names (`String(reflecting:)`) of the type listed first
    /// and the one listed second. Rename one of them, or leave one out of `events`.
    case duplicateEventName(String, firstType: String, secondType: String)
}
