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
public struct BatchLimit: Sendable, Hashable {
    /// The most records one request holds.
    public let maximumRecordCount: Int
    /// The most bytes one request's body holds, the envelope included.
    public let maximumByteCount: Int
    /// The most bytes one record's JSON holds; a record over it is left out of every request.
    public let maximumRecordByteCount: Int

    /// No limit: every record in one request, however large.
    public static let unlimited = BatchLimit(unchecked: .max, .max, .max)

    /// A limit of `maximumRecordCount` records and `maximumByteCount` bytes per request, and
    /// `maximumRecordByteCount` bytes per record.
    ///
    /// - Parameters:
    ///   - maximumRecordCount: The most records one request holds.
    ///   - maximumByteCount: The most bytes one request's body holds, the envelope included.
    ///   - maximumRecordByteCount: The most bytes one record's JSON holds.
    /// - Throws: ``InvalidBatchLimit`` when any of the three is below 1.
    public init(maximumRecordCount: Int, maximumByteCount: Int, maximumRecordByteCount: Int) throws(InvalidBatchLimit) {
        guard maximumRecordCount >= 1, maximumByteCount >= 1, maximumRecordByteCount >= 1 else {
            throw InvalidBatchLimit()
        }
        self.init(unchecked: maximumRecordCount, maximumByteCount, maximumRecordByteCount)
    }

    private init(unchecked maximumRecordCount: Int, _ maximumByteCount: Int, _ maximumRecordByteCount: Int) {
        self.maximumRecordCount = maximumRecordCount
        self.maximumByteCount = maximumByteCount
        self.maximumRecordByteCount = maximumRecordByteCount
    }
}
