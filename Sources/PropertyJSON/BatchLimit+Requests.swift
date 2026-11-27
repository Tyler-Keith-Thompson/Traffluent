public import Events
public import Foundation
public import HTTPDestinations
public import JSONValues

extension BatchLimit {
    /// `batch` as the fewest requests in order that keep within the limit, each of `envelope`
    /// around its records' JSON, leaving out a record that can't be encoded or that no request
    /// could hold.
    ///
    /// Records keep the batch's order, across requests and within each. A request takes the next
    /// record while it holds fewer than ``maximumRecordCount`` records and the record's JSON fits
    /// in its ``maximumByteCount``; otherwise the record starts the next request. A record whose
    /// JSON is over ``maximumRecordByteCount``, or too large for a request of it alone, is left
    /// out with `oversized`'s reason.
    ///
    /// ```swift
    /// let requests = limit.requests(for: batch, in: envelope) { record throws(VendorError) in
    ///     try json(of: record)
    /// } oversized: { byteCount in
    ///     .oversized(byteCount: byteCount)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - batch: Records of tracked events, oldest first.
    ///   - envelope: What each request's body wraps its records' JSON in.
    ///   - encoding: Each record's JSON; what it throws leaves the record out, with that reason.
    ///   - oversized: The reason a record is left out for being too large, given its JSON's byte
    ///     count.
    /// - Returns: The requests, none for an empty batch, and each record left out, in the batch's
    ///   order.
    /// - Complexity: O(*n*) in the length of the records' JSON, besides what `encoding` takes.
    public func requests<Failure: Error>(
        for batch: [EventRecord],
        in envelope: JSONEnvelope,
        encoding: (EventRecord) throws(Failure) -> JSON,
        oversized: (_ byteCount: Int) -> Failure
    ) -> BatchRequests<Failure> {
        var skippedRecords: [SkippedRecord<Failure>] = []
        var builder = RequestBuilder(limit: self, envelope: envelope)
        // What one record may hold: its own limit, and what a request of it alone leaves beside
        // the envelope. Negative when the envelope alone is over the request's limit, so every
        // record is too large.
        let recordCapacity = Swift.min(maximumRecordByteCount, maximumByteCount - envelope.byteCount)
        for record in batch {
            let text: String
            do {
                text = try encoding(record).minified
            } catch {
                skippedRecords.append(SkippedRecord(record, reason: error))
                continue
            }
            let byteCount = text.utf8.count
            guard byteCount <= recordCapacity else {
                skippedRecords.append(SkippedRecord(record, reason: oversized(byteCount)))
                continue
            }
            builder.append(text, byteCount: byteCount, id: record.id)
        }
        return BatchRequests(requests: builder.finish(), skippedRecords: skippedRecords)
    }
}

/// The requests of a batch so far, and the one being filled.
///
/// A struct the loop mutates rather than a nested function capturing the loop's locals, which
/// would box them and retain the box per record.
private struct RequestBuilder {
    let limit: BatchLimit
    let envelope: JSONEnvelope
    private(set) var requests: [EncodedRequest] = []
    private var elements: [String] = []
    private var recordIDs: [UUID] = []
    /// The bytes of the request being filled: its envelope, elements and the commas between.
    private var byteCount: Int

    init(limit: BatchLimit, envelope: JSONEnvelope) {
        self.limit = limit
        self.envelope = envelope
        byteCount = envelope.byteCount
    }

    /// Adds a record's JSON, `byteCount` bytes that fit in a request of it alone, to the request
    /// being filled, or to a new one when that one is full.
    mutating func append(_ text: String, byteCount recordByteCount: Int, id: UUID) {
        // Written as a comparison with what is left, which can't overflow, where the sum could.
        let fits = elements.isEmpty || (elements.count < limit.maximumRecordCount && recordByteCount < limit.maximumByteCount - byteCount)
        if !fits {
            flush()
        }
        // A comma before every element but the first.
        byteCount += elements.isEmpty ? recordByteCount : recordByteCount + 1
        elements.append(text)
        recordIDs.append(id)
    }

    /// Every request, the last one filled included.
    mutating func finish() -> [EncodedRequest] {
        flush()
        return requests
    }

    private mutating func flush() {
        guard !elements.isEmpty else { return }
        requests.append(EncodedRequest(body: envelope.body(of: elements), recordIDs: recordIDs))
        elements = []
        recordIDs = []
        byteCount = envelope.byteCount
    }
}

extension SkippedRecord {
    /// `record` left out for `reason`.
    fileprivate init(_ record: EventRecord, reason: Reason) {
        self.init(recordID: record.id, eventName: record.name, schemaVersion: type(of: record.event).schemaVersion, reason: reason)
    }
}
