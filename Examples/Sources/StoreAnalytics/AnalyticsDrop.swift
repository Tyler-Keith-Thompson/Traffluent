public import Destinations
public import CollectorEncoding
public import HTTPDestinations
public import Persistence
public import Trackers

/// Events the store's analytics tracked but won't deliver, and why: every drop report of the
/// tracker, its consent, its store, its collector and its delivery, as one kind of value.
///
/// None of these is an error the app can fix as it runs, but each means data is missing from the
/// dashboard, so the app logs every one (``StoreAnalytics/drops``).
public enum AnalyticsDrop: Sendable, CustomStringConvertible {
    /// An event broke a constraint its type declares, such as a quantity of 0: never delivered.
    case rejected(RejectionReport)
    /// Events the shopper's consent dropped: their category was denied, or the hold for undecided
    /// categories was full.
    case notConsented(ConsentDropReport)
    /// Records the store couldn't keep, or lost: an event type it doesn't list, its byte bound, a
    /// failed write, or a record it couldn't read back.
    case notStored(DropReport)
    /// A batch the collector refused, that couldn't be sent, or that couldn't be encoded.
    case notSent(HTTPDropReport<CollectorEncodingError>)
    /// A batch the delivery dropped while the collector was behind; the store sends its records
    /// again, so only `recordCount - storedRecordCount` of them are lost.
    case bufferFull(BufferDropReport)

    /// The drop, for a log line.
    public var description: String {
        switch self {
        case .rejected(let report): "Rejected: \(report)"
        case .notConsented(let report): "Not consented: \(report)"
        case .notStored(let report): "Not stored: \(report)"
        case .notSent(let report): "Not sent: \(report)"
        case .bufferFull(let report): "Buffer full: \(report)"
        }
    }
}
