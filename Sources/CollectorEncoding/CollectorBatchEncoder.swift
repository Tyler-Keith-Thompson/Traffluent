public import Events
import Foundation
public import HTTPDestinations
public import Instrumentation
import Persistence
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
/// let plan = TrackingPlan(schemas: [SignedUp.schema, CheckoutStarted.schema])
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
/// Properties are read from the event's `BinaryCodable` form, which `@Event` derives, through
/// the types its schema in `plan` lists, so the values are the ones the plan's documents describe:
/// a `String` is a string; a `Bool` a boolean; an integer or a `Double` or `Float` a number; a
/// `Date` an ISO 8601 string, as `timestamp` is; a `UUID` an uppercase UUID string; an array an
/// array; and an optional's `nil` is `null`. A `Refined` value is its value. A type the plan can't
/// map is written as its encoding holds it: a map with text keys is an object.
///
/// A ``/Events/Sensitive`` value is written as its value when the record reveals it
/// (`EventRecord/revealsSensitiveValues`), as every destination may, and left out once a delivery
/// redacts it (`redactingSensitiveValues()`): a redacted property is missing from `properties`,
/// and an element of an array is `null`. A collector that validates against the plan then rejects
/// the record, naming the property, rather than storing a value that isn't the one tracked.
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
/// Other context values aren't written. The bytes are the same for the same records on every
/// run and platform: no whitespace, object members in the order of their names' UTF-8 bytes, a
/// whole number without a fraction and any other in the shortest form that reads back as the
/// same `Double` (`0.25`, `1e-05`).
public struct CollectorBatchEncoder: BatchEncoder {
    // A dictionary of each event version's property types, parsed once here rather than per
    // record: every record of a batch is looked up in it.
    private let propertyTypes: [EventVersion: [String: WrittenType?]]
    private let instrument: any Instrument

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

    /// The request body for `batch`: its records in TraffluentCollector's ingest format.
    ///
    /// - Parameter batch: Records of tracked events, oldest first.
    /// - Returns: The body's JSON, of content type `application/json`.
    /// - Throws: ``CollectorEncodingError/unknownEvent(name:version:)`` for a record whose event
    ///   and version the plan doesn't describe, ``CollectorEncodingError/notBinaryCodable(name:)``
    ///   for one whose event isn't `BinaryCodable`, and
    ///   ``CollectorEncodingError/unrepresentableValue(event:property:)`` for a property JSON
    ///   can't hold.
    /// - Complexity: O(*n* log *n*) in the batch's size, for sorting each object's members.
    public func encode(_ batch: [EventRecord]) throws(CollectorEncodingError) -> EncodedBatch {
        var records: [JSON] = []
        records.reserveCapacity(batch.count)
        for record in batch {
            records.append(try json(of: record))
        }
        let body = JSON.object(["records": .array(records)]).minified
        return EncodedBatch(body: Data(body.utf8), contentType: "application/json")
    }

    private func json(of record: EventRecord) throws(CollectorEncodingError) -> JSON {
        let version = EventVersion(name: record.name, version: type(of: record.event).schemaVersion)
        guard let types = propertyTypes[version] else {
            throw .unknownEvent(name: version.name, version: version.version)
        }
        return .object([
            "id": .string(record.id.uuidString),
            "name": .string(record.name),
            "timestamp": .string(record.timestamp.collectorTimestamp),
            "properties": .object(try record.properties(types: types)),
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

extension EventSchema {
    /// Each property's type as written, optional when the property is; `nil` for a type the plan
    /// can't parse, whose value is written as its encoding holds it.
    fileprivate var propertyTypes: [String: WrittenType?] {
        // Unique: TrackingPlan rejects a schema with two properties of one name.
        Dictionary(uniqueKeysWithValues: properties.map { property in
            let type = WrittenType(parsing: property.typeName)
            return (property.name, property.isOptional ? type.map(WrittenType.optional) : type)
        })
    }
}

extension EventRecord {
    /// The event's properties as JSON, read from its `BinaryCodable` form through `types`.
    fileprivate func properties(types: [String: WrittenType?]) throws(CollectorEncodingError) -> [String: JSON] {
        guard let event = event as? any BinaryCodable else {
            throw .notBinaryCodable(name: name)
        }
        // The store's encoder only for a record that reveals its sensitive values; otherwise each
        // is written as `undefined`, which leaves it out.
        var encoder = BinaryEncoder(writingSensitiveValues: revealsSensitiveValues)
        encoder.encode(event)
        var reader = PropertyReader(bytes: encoder.bytes)
        return try reader.properties(types: types, event: name)
    }
}
