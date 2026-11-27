/// The most an ingestion endpoint takes in one request: how many records, how many bytes of body,
/// and how many bytes of one record's JSON.
///
/// A vendor's encoder holds its endpoint's limits and splits each batch to them with
/// ``requests(for:in:encoding:oversized:)``:
///
/// ```swift
/// // 500 KB per request and 32 KB per event, as one vendor documents them.
/// let limit = try BatchLimit(maximumRecordCount: 100, maximumByteCount: 500_000, maximumRecordByteCount: 32_000)
/// ```
///
/// Byte counts are of the UTF-8 the encoder writes, before any compression.
///
/// Some endpoints take one large record in a request of its own, beyond what a request of several
/// holds, as Snowplow's collectors do. Such a limit sets ``sendsLargeRecordsAlone``:
///
/// ```swift
/// // 25 events and 40 KB a request, and an event of up to 150 KB alone.
/// let limit = try BatchLimit(maximumRecordCount: 25, maximumByteCount: 40_000, maximumRecordByteCount: 150_000, sendsLargeRecordsAlone: true)
/// ```
public struct BatchLimit: Sendable, Hashable {
    /// The most records one request holds.
    public let maximumRecordCount: Int
    /// The most bytes one request's body holds, the envelope included.
    public let maximumByteCount: Int
    /// The most bytes one record's JSON holds; a record over it is left out of every request.
    public let maximumRecordByteCount: Int
    /// Whether a record too large for a request of ``maximumByteCount`` is sent in a request of
    /// its own, up to ``maximumRecordByteCount`` bytes of it, rather than left out.
    public let sendsLargeRecordsAlone: Bool

    /// No limit: every record in one request, however large.
    public static let unlimited = BatchLimit(unchecked: .max, .max, .max, sendsLargeRecordsAlone: false)

    /// A limit of `maximumRecordCount` records and `maximumByteCount` bytes per request, and
    /// `maximumRecordByteCount` bytes per record.
    ///
    /// - Parameters:
    ///   - maximumRecordCount: The most records one request holds.
    ///   - maximumByteCount: The most bytes one request's body holds, the envelope included.
    ///   - maximumRecordByteCount: The most bytes one record's JSON holds.
    ///   - sendsLargeRecordsAlone: Whether a record too large for a request of `maximumByteCount`
    ///     bytes is sent in a request of its own, up to `maximumRecordByteCount` bytes of it; left
    ///     out by default.
    /// - Throws: ``InvalidBatchLimit`` when any of the three counts is below 1.
    public init(maximumRecordCount: Int, maximumByteCount: Int, maximumRecordByteCount: Int, sendsLargeRecordsAlone: Bool = false) throws(InvalidBatchLimit) {
        guard maximumRecordCount >= 1, maximumByteCount >= 1, maximumRecordByteCount >= 1 else {
            throw InvalidBatchLimit()
        }
        self.init(unchecked: maximumRecordCount, maximumByteCount, maximumRecordByteCount, sendsLargeRecordsAlone: sendsLargeRecordsAlone)
    }

    private init(unchecked maximumRecordCount: Int, _ maximumByteCount: Int, _ maximumRecordByteCount: Int, sendsLargeRecordsAlone: Bool) {
        self.maximumRecordCount = maximumRecordCount
        self.maximumByteCount = maximumByteCount
        self.maximumRecordByteCount = maximumRecordByteCount
        self.sendsLargeRecordsAlone = sendsLargeRecordsAlone
    }
}
