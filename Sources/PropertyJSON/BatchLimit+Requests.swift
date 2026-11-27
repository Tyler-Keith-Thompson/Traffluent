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
    /// JSON is over ``maximumRecordByteCount`` is left out with `oversized`'s reason, and so is one
    /// too large for a request of it alone, unless ``sendsLargeRecordsAlone`` is set: such a record
    /// is then a request of its own, the only one whose body is over ``maximumByteCount``.
    ///
    /// No request has a deadline; ``requests(for:in:maximumAge:encoding:oversized:)`` gives each
    /// one.
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
        split(batch, in: envelope, maximumAge: nil, encoding: encoding, oversized: oversized)
    }

    /// `batch` as the fewest requests in order that keep within the limit, as
    /// ``requests(for:in:encoding:oversized:)`` splits it, each with a deadline `maximumAge` after
    /// its oldest record was tracked.
    ///
    /// Each request's `EncodedRequest/deadline` is `maximumAge` after the earliest
    /// `EventRecord/timestamp` of the records it holds, whatever their order, so `HTTPDestination`
    /// drops and reports a request still being retried by then, every record of it, rather than
    /// send it to a vendor that would misdate or ignore records that old. A request holding a
    /// record whose timestamp is NaN or infinite has a NaN deadline, which `HTTPDestination` takes
    /// as passed.
    ///
    /// ```swift
    /// let requests = try limit.requests(for: batch, in: envelope, maximumAge: .seconds(23 * 60 * 60)) { record throws(VendorError) in
    ///     try json(of: record)
    /// } oversized: { byteCount in
    ///     .oversized(byteCount: byteCount)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - batch: Records of tracked events, oldest first.
    ///   - envelope: What each request's body wraps its records' JSON in.
    ///   - maximumAge: How long after its oldest record was tracked a request may be sent; zero or
    ///     more.
    ///   - encoding: Each record's JSON; what it throws leaves the record out, with that reason.
    ///   - oversized: The reason a record is left out for being too large, given its JSON's byte
    ///     count.
    /// - Returns: The requests, none for an empty batch, and each record left out, in the batch's
    ///   order.
    /// - Throws: ``NegativeMaximumAge`` when `maximumAge` is below zero.
    /// - Complexity: O(*n*) in the length of the records' JSON, besides what `encoding` takes.
    public func requests<Failure: Error>(
        for batch: [EventRecord],
        in envelope: JSONEnvelope,
        maximumAge: Duration,
        encoding: (EventRecord) throws(Failure) -> JSON,
        oversized: (_ byteCount: Int) -> Failure
    ) throws(NegativeMaximumAge) -> BatchRequests<Failure> {
        guard maximumAge >= .zero else { throw NegativeMaximumAge() }
        let components = maximumAge.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) * 1e-18
        return split(batch, in: envelope, maximumAge: seconds, encoding: encoding, oversized: oversized)
    }

    /// The split both spellings make, with a deadline `maximumAge` seconds after each request's
    /// oldest record, or none.
    private func split<Failure: Error>(
        _ batch: [EventRecord],
        in envelope: JSONEnvelope,
        maximumAge: TimeInterval?,
        encoding: (EventRecord) throws(Failure) -> JSON,
        oversized: (_ byteCount: Int) -> Failure
    ) -> BatchRequests<Failure> {
        var skippedRecords: [SkippedRecord<Failure>] = []
        var builder = RequestBuilder(limit: self, envelope: envelope, maximumAge: maximumAge)
        // What one record may hold: its own limit, and, unless a large record goes alone, what a
        // request of it alone leaves beside the envelope. Negative when the envelope alone is over
        // the request's limit, so every record is too large. A record sent alone needs nothing of
        // the builder: it never fits beside another, so it is flushed before and after.
        let recordCapacity = sendsLargeRecordsAlone ? maximumRecordByteCount : Swift.min(maximumRecordByteCount, maximumByteCount - envelope.byteCount)
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
            builder.append(text, byteCount: byteCount, id: record.id, timestamp: record.timestamp)
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
    let maximumAge: TimeInterval?
    private(set) var requests: [EncodedRequest] = []
    private var elements: [String] = []
    private var recordIDs: [UUID] = []
    /// The earliest timestamp of the request being filled's records, `nil` while it holds none.
    private var oldest: Date?
    /// The bytes of the request being filled: its envelope, elements and the commas between.
    private var byteCount: Int

    init(limit: BatchLimit, envelope: JSONEnvelope, maximumAge: TimeInterval?) {
        self.limit = limit
        self.envelope = envelope
        self.maximumAge = maximumAge
        byteCount = envelope.byteCount
    }

    /// Adds a record's JSON, `byteCount` bytes that fit in a request of it alone (or that the limit
    /// sends alone), to the request being filled, or to a new one when that one is full.
    mutating func append(_ text: String, byteCount recordByteCount: Int, id: UUID, timestamp: Date) {
        // Written as a comparison with what is left, which can't overflow, where the sum could.
        let fits = elements.isEmpty || (elements.count < limit.maximumRecordCount && recordByteCount < limit.maximumByteCount - byteCount)
        if !fits {
            flush()
        }
        // A comma before every element but the first.
        byteCount += elements.isEmpty ? recordByteCount : recordByteCount + 1
        elements.append(text)
        recordIDs.append(id)
        // The earliest, not the first, so the deadline holds whatever order the batch is in. A
        // timestamp that isn't finite makes it NaN for the rest of the request, whichever of its
        // records comes first, as `min` with a NaN depends on the order; HTTPDestination takes a
        // NaN deadline as passed.
        if !timestamp.timeIntervalSinceReferenceDate.isFinite || oldest?.timeIntervalSinceReferenceDate.isNaN == true {
            oldest = Date(timeIntervalSinceReferenceDate: .nan)
        } else {
            oldest = oldest.map { Swift.min($0, timestamp) } ?? timestamp
        }
    }

    /// Every request, the last one filled included.
    mutating func finish() -> [EncodedRequest] {
        flush()
        return requests
    }

    private mutating func flush() {
        guard !elements.isEmpty else { return }
        let deadline = maximumAge.flatMap { maximumAge in oldest.map { $0.addingTimeInterval(maximumAge) } }
        requests.append(EncodedRequest(body: envelope.body(of: elements), recordIDs: recordIDs, deadline: deadline))
        elements = []
        recordIDs = []
        oldest = nil
        byteCount = envelope.byteCount
    }
}

extension SkippedRecord {
    /// `record` left out for `reason`.
    fileprivate init(_ record: EventRecord, reason: Reason) {
        self.init(recordID: record.id, eventName: record.name, schemaVersion: type(of: record.event).schemaVersion, reason: reason)
    }
}
