import Foundation

/// The part of a collector batch the example server reads: each record's identifier, event name
/// and redelivery marker. `CollectorBatchEncoder` writes the rest too (timestamp, properties,
/// context), which a real collector validates against the tracking plan and stores.
struct IngestedBatch: Decodable {
    struct Record: Decodable {
        let id: UUID
        let name: String
        let isRedelivered: Bool
    }

    let records: [Record]
}
