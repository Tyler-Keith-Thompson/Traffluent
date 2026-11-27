public import Events
import Foundation
public import HTTPDestinations
public import Instrumentation
import JSONValues
import PropertyJSON
public import TrackingPlans

/// The ``/HTTPDestinations/BatchEncoder`` of TraffluentCollector's ingest format, so an
/// `HTTPDestination` can send to a self-hosted collector's `POST /v1/batches`.
///
/// The collector's API key isn't the encoder's: pass it to the destination as an `Authorization`
/// header field.
///
/// ```swift
/// import CollectorEncoding
/// import HTTPDestinations
/// import TrackingPlans
///
/// let plan = try TrackingPlan()
/// let collector = HTTPDestination(
///     endpoint: collectorURL,  // https://collector.example.com/v1/batches
///     headerFields: [.authorization: "Bearer \(apiKey)"],
///     encoder: CollectorBatchEncoder(plan: plan))
/// let delivery = tracker.records.batch().deliver(to: collector)
/// ```
///
/// The body is a JSON object whose `records` member holds one object per record, oldest first,
/// with these members, and its content type is `application/json`:
///
/// | Member | Holds |
/// |---|---|
/// | `id` | The record's `EventRecord/id`, as a UUID string; a redelivered record keeps it |
/// | `name` | The event's `Event/name` |
/// | `timestamp` | When the event was tracked: ISO 8601 in UTC, with milliseconds (`2026-11-23T14:03:27.512Z`) |
/// | `properties` | The event's stored properties, by name |
/// | `context` | The context values listed below that the record's context holds |
/// | `isRedelivered` | The record's `EventRecord/isRedelivered` |
///
/// Properties are read from the event's `Encodable` form, which `@Event` derives, through
/// the types its schema in `plan` lists, so the values are the ones the plan's documents describe:
/// a `String` is a string; a `Bool` a boolean; an integer or a `Double` or `Float` a number; a
/// `Date` an ISO 8601 string, as `timestamp` is; a `UUID` an uppercase UUID string; an array an
/// array; and an optional's `nil` is `null`. A `Refined` value is its value. A type the plan can't
/// map is written as its encoding holds it: a map with text keys is an object.
///
/// A ``/Events/Sensitive`` value is written as its value when the record reveals it
/// (`EventRecord/revealsSensitiveValues`), as every destination may, and left out once a delivery
/// redacts it (`redactingSensitiveValues()`): a redacted property is missing from `properties`,
/// and an element of an array, or a value inside a type the plan can't map, is `null`. The plan's
/// documents allow both, as they never require a
/// `Sensitive` property and let a `Sensitive` element be `null`, so a collector that validates
/// against the plan accepts the record.
///
/// `context` holds, for each of these keys the record's context has a value for:
///
/// | Member | Key | Holds |
/// |---|---|---|
/// | `application` | `ApplicationKey` | An object of `bundleIdentifier`, `version` and `build`, each left out when `nil` |
/// | `device` | `DeviceKey` | An object of `model` and `formFactor` (`phone`, `pad`, `mac`, `tv`, `watch` or `vision`) |
/// | `locale` | `LocaleKey` | The locale's BCP 47 identifier, such as `en-US` |
/// | `network` | `NetworkKey` | `wifi`, `cellular`, `wiredEthernet`, `other` or `offline` |
/// | `operatingSystem` | `OperatingSystemKey` | An object of `name` and `version` |
/// | `sampleRate` | `SampleRateKey` | The rate the record was kept at, a number |
/// | `session` | `SessionKey` | The session's identifier, a UUID string |
/// | `trace` | The instrument's | An object of the fields the instrument injects for the record's context (`traceparent` and `tracestate` for a W3C Trace Context tracer), left out when it injects none |
/// | `vendorIdentifier` | `VendorIdentifierKey` | The vendor identifier, a UUID string; left out when redacted |
///
/// A record the encoder can't write is left out of the body, and the batch's other records are
/// sent: one whose event and version `plan` doesn't describe, whose event isn't `Encodable`,
/// that holds a value JSON can't, or whose timestamp has no ISO 8601 form
/// (``CollectorEncodingError``). ``requests(for:)`` returns them
/// as `SkippedRecord`s, which `HTTPDestination` logs and reports on its `dropReports`; when every
/// record of a batch is left out, it sends nothing for it. A batch is one request: the collector
/// sets no limit on its size.
///
/// Other context values aren't written. The bytes are the same for the same records on every
/// run and platform: no whitespace, object members in the order of their names' UTF-8 bytes, a
/// whole number without a fraction and any other in the shortest form that reads back as the
/// same `Double` (`0.25`, `1e-05`).
public struct CollectorBatchEncoder: BatchEncoder {
    /// No status beyond the 408, 429 and 5xx that `HTTPDestination` retries for every encoder.
    public static let transientStatuses: Set<TransientStatus> = []

    // A dictionary of each event version's property types, parsed once here rather than per
    // record: every record of a batch is looked up in it.
    private let propertyTypes: [EventVersion: [String: WrittenType?]]
    private let instrument: any Instrument

    /// Why a record was left out of the batch's request.
    public typealias Failure = CollectorEncodingError

    /// An encoder of the events `plan` describes, writing each record's trace context as
    /// `instrument` injects it.
    ///
    /// - Parameters:
    ///   - plan: The tracking plan of every event the encoder is given, the one the collector
    ///     validates against: each record's event is read through the schema of its name and
    ///     `Event/schemaVersion` here.
    ///   - instrument: What injects each record's trace context into its `trace` member; the
    ///     bootstrapped `InstrumentationSystem.instrument`, read once here, by default.
    public init(plan: TrackingPlan, instrument: any Instrument = InstrumentationSystem.instrument) {
        var propertyTypes: [EventVersion: [String: WrittenType?]] = [:]
        for schema in plan.schemas {
            propertyTypes[EventVersion(name: schema.name, version: schema.version)] = schema.propertyTypes
        }
        self.propertyTypes = propertyTypes
        self.instrument = instrument
    }

    /// The one request carrying `batch` in TraffluentCollector's ingest format, and the records
    /// left out of it.
    ///
    /// - Parameter batch: Records of tracked events, oldest first.
    /// - Returns: A request of ``batch(of:)``'s body, carrying every record but the skipped ones,
    ///   or no request when every record was skipped, and the skipped records.
    /// - Complexity: O(*n* log *n*) in the batch's size, for sorting each object's members.
    public func requests(for batch: [EventRecord]) -> BatchRequests<CollectorEncodingError> {
        let encoded = self.batch(of: batch)
        guard let body = encoded.body else {
            return BatchRequests(requests: [], skippedRecords: encoded.skippedRecords)
        }
        // The request names only the records its body holds, so a rejection reports those and
        // not the skipped ones, which are reported as skipped.
        let skipped = Set(encoded.skippedRecords.map(\.recordID))
        let recordIDs = batch.map(\.id).filter { !skipped.contains($0) }
        return BatchRequests(requests: [EncodedRequest(body: body, recordIDs: recordIDs)], skippedRecords: encoded.skippedRecords)
    }

    /// The body of `batch` in TraffluentCollector's ingest format, and the records left out of it.
    ///
    /// - Parameter batch: Records of tracked events, oldest first.
    /// - Returns: The body of every record that could be encoded, `nil` when `batch` has records
    ///   and none could, and each record left out, with why.
    /// - Complexity: O(*n* log *n*) in the batch's size, for sorting each object's members.
    public func batch(of batch: [EventRecord]) -> CollectorBatch {
        var records: [JSON] = []
        records.reserveCapacity(batch.count)
        var skippedRecords: [SkippedRecord<CollectorEncodingError>] = []
        for record in batch {
            do {
                records.append(try json(of: record))
            } catch {
                skippedRecords.append(SkippedRecord(recordID: record.id, eventName: record.name, schemaVersion: type(of: record.event).schemaVersion, reason: error))
            }
        }
        guard !records.isEmpty || batch.isEmpty else {
            return CollectorBatch(body: nil, skippedRecords: skippedRecords)
        }
        let body = JSON.object(["records": .array(records)]).minified
        return CollectorBatch(body: EncodedBatch(body: Data(body.utf8), contentType: "application/json"), skippedRecords: skippedRecords)
    }

    private func json(of record: EventRecord) throws(CollectorEncodingError) -> JSON {
        let version = EventVersion(name: record.name, version: type(of: record.event).schemaVersion)
        guard let types = propertyTypes[version] else {
            throw .unknownEvent(name: version.name, version: version.version)
        }
        let properties = try record.properties(types: types)
        let timestamp: String
        do {
            timestamp = try record.timestamp.iso8601Timestamp
        } catch {
            throw .unrepresentableTimestamp
        }
        return .object([
            "id": .string(record.id.uuidString),
            "name": .string(record.name),
            "timestamp": .string(timestamp),
            "properties": .object(properties),
            "context": .object(record.collectorContext(instrument: instrument)),
            "isRedelivered": .boolean(record.isRedelivered),
        ])
    }
}

/// An event's name and schema version: what a record's event is looked up in the plan by.
private struct EventVersion: Hashable {
    let name: String
    let version: Int
}

extension EventRecord {
    /// The event's properties as JSON, read from its `Encodable` form through `types`, with
    /// its sensitive values while the record reveals them.
    fileprivate func properties(types: [String: WrittenType?]) throws(CollectorEncodingError) -> [String: JSON] {
        do {
            return try properties(types: types, writingSensitiveValues: revealsSensitiveValues)
        } catch {
            throw CollectorEncodingError(error)
        }
    }
}

extension CollectorEncodingError {
    /// The reason the property reader gave, as this encoder's.
    fileprivate init(_ error: PropertyReadingError) {
        switch error {
        case .unknownEvent(let name, let version): self = .unknownEvent(name: name, version: version)
        case .notEncodable(let name): self = .notEncodable(name: name)
        case .unrepresentableValue(let event, let property): self = .unrepresentableValue(event: event, property: property)
        }
    }
}
