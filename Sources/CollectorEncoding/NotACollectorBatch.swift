/// The error ``CollectorBatchDecoder/batch(from:)`` throws for a body that isn't a collector batch
/// at all, so it has no records to read.
///
/// A body that is a batch but holds records the decoder can't read doesn't throw: each such record
/// is an ``UndecodedRecord``.
public enum NotACollectorBatch: Error, Sendable, Hashable {
    /// The body isn't JSON, or holds JSON this library can't parse, such as a number past a
    /// `Double`'s range (`1e400`).
    case notJSON
    /// The body is JSON, but not an object.
    case notAnObject
    /// The body's object has no `records` member.
    case missingRecords
    /// The body's `records` member isn't an array.
    case recordsNotAnArray
}
