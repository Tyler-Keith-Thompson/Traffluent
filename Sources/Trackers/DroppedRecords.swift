internal import Events
internal import Foundation

/// How many records were dropped, and the range of times they were tracked in.
struct DroppedRecords: Sendable {
    var count = 0
    /// `nil` while none was dropped.
    var timestamps: ClosedRange<Date>?

    mutating func add(_ record: EventRecord) {
        count += 1
        // min and max rather than first and last: a tracker's clock is the caller's, and needn't
        // move forwards.
        timestamps = timestamps.map { min($0.lowerBound, record.timestamp) ... max($0.upperBound, record.timestamp) }
            ?? record.timestamp ... record.timestamp
    }
}

/// Records dropped for a denial, by category, in the order each category first appeared.
struct DroppedRecordsByCategory: Sendable {
    private var categories: [ConsentCategory] = []
    private var dropped: [ConsentCategory: DroppedRecords] = [:]

    mutating func add(_ record: EventRecord) {
        let category = record.consentCategory
        if dropped[category] == nil {
            categories.append(category)
        }
        dropped[category, default: DroppedRecords()].add(record)
    }

    /// A ``ConsentDropReport/denied(category:recordCount:timestamps:)`` per category.
    var reports: [ConsentDropReport] {
        categories.compactMap { category in
            guard let records = dropped[category], let timestamps = records.timestamps else { return nil }
            return .denied(category: category, recordCount: records.count, timestamps: timestamps)
        }
    }
}
