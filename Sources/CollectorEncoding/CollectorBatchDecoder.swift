public import Events
public import Foundation
public import Instrumentation
import JSONValues
import PropertyJSON
public import TrackingPlans

/// Reads a body ``CollectorBatchEncoder`` wrote back into the `EventRecord`s it holds, so a server
/// that receives an app's batches can hand them to another destination.
///
/// ```swift
/// import CollectorEncoding
/// import TrackingPlans
///
/// let decoder = try CollectorBatchDecoder(plan: try TrackingPlan())
/// let batch = try decoder.batch(from: body)  // the body of a POST /v1/batches
/// await destination.receive(batch.records)
/// ```
///
/// Each record keeps what the body holds of it:
///
/// - its `EventRecord/id` and `EventRecord/isRedelivered`;
/// - its `EventRecord/timestamp`, to the millisecond the body holds;
/// - its event, a value of the decoder's type of that `Event/name`, read through the type's
///   schema in `plan`, its `Sensitive` values included;
/// - the context the body's `context` holds: the session's `SessionKey`, the sample rate, the
///   standard context keys, and the trace context, which the decoder's instrument extracts.
///
/// A record has no `EventRecord/sourceLocation` or `EventRecord/deliveryTag`, which the body
/// doesn't hold, and it reveals its sensitive values, as a tracked record does, so a destination
/// made with `redactingSensitiveValues()` still redacts them. Encoding the records again with a
/// ``CollectorBatchEncoder`` of the same plan, and an instrument that injects what it extracts,
/// writes the same bytes.
///
/// The body names each record's event but not its version, so a record is read at the version of
/// the decoder's type of that name, and the plan must hold a schema of that version. Deploy the
/// decoder with the event types the apps send. Once a type's version is raised, a record an older
/// app sends at the earlier version is read as the newer one: it is reported as
/// ``CollectorDecodingError/undecodableProperty(event:property:)`` when its properties don't fit
/// the newer type, and read as the newer version when they do.
///
/// A record the decoder can't read is left out and the batch's other records are read: one whose
/// event it has no type of, one whose type's version the plan has no schema of, a member that is
/// missing or holds what the encoder never writes, and a property the event's type can't read
/// (``CollectorDecodingError``). ``batch(from:)`` returns each as an ``UndecodedRecord``. A
/// `Sensitive` property a delivery redacted is missing, so its record reads back only when the
/// property is optional or has a default value; a redacted `Sensitive` element of an array is
/// `null`, so a record whose array of non-optional `Sensitive` elements was redacted is reported as
/// ``CollectorDecodingError/undecodableProperty(event:property:)``. An integer outside its
/// property's type, such as 300 for a `UInt8`, is reported the same way. A property of a type the plan can't map reads
/// back only as far as its JSON holds what its `Decodable` conformance reads: a whole `Double`
/// inside it is written without a fraction, and a `Date` inside it as a timestamp, neither of
/// which it reads.
///
/// A body that isn't a collector batch at all throws ``NotACollectorBatch``.
// The event types come from a TrackingPlan and a list of types, rather than from either alone. The
// plan is what the encoder reads properties through, so the decoder reads them back through the
// same schemas, and it says which versions the collector accepts. A type is what a record's event
// is decoded into, and the plan holds none, only schemas. The body has no version member, so the
// type of a name decides the version, and the plan only confirms it. Rejected: types alone (each
// @Event's own schema), which would read a version the plan has dropped and could disagree with
// the encoder's schema; a plan alone, which can't make a value; and a version member in the body,
// which would change the collector's format for every reader of it.
public struct CollectorBatchDecoder: Sendable {
    // Each event type by name, with its property types from the plan, looked up once here rather
    // than per record; nil property types mean the plan has no schema of the type's version.
    private let events: [String: DecodableEvent]
    private let instrument: any Instrument

    /// A decoder of records of `events`, whose properties `plan` describes, extracting each
    /// record's trace context as `instrument` does.
    ///
    /// - Parameters:
    ///   - plan: The tracking plan the encoder that wrote the batches was made with: each record's
    ///     event is read through the schema of its type's name and `Event/schemaVersion` here.
    ///   - events: The event types records are read back into, one per `Event/name`.
    ///   - instrument: What extracts each record's trace context from its `trace` member; the
    ///     bootstrapped `InstrumentationSystem.instrument`, read once here, by default.
    /// - Throws: ``CollectorBatchDecoderError/duplicateEventName(_:firstType:secondType:)`` when
    ///   two of `events` share a name.
    public init(
        plan: TrackingPlan,
        events: [any (Event & Decodable).Type],
        instrument: any Instrument = InstrumentationSystem.instrument
    ) throws(CollectorBatchDecoderError) {
        var schemas: [PlannedVersion: EventSchema] = [:]
        for schema in plan.schemas {
            schemas[PlannedVersion(name: schema.name, version: schema.version)] = schema
        }
        var decodable: [String: DecodableEvent] = [:]
        for type in events {
            if let first = decodable[type.name] {
                throw .duplicateEventName(type.name, firstType: String(reflecting: first.type), secondType: String(reflecting: type))
            }
            let schema = schemas[PlannedVersion(name: type.name, version: type.schemaVersion)]
            decodable[type.name] = DecodableEvent(type: type, propertyTypes: schema?.propertyTypes)
        }
        self.events = decodable
        self.instrument = instrument
    }

    /// A decoder of records of every `@Event` the program links (`DiscoveredEvent/all`), whose
    /// properties `plan` describes.
    ///
    /// - Parameters:
    ///   - plan: The tracking plan the encoder that wrote the batches was made with.
    ///   - instrument: What extracts each record's trace context; the bootstrapped
    ///     `InstrumentationSystem.instrument` by default.
    /// - Throws: ``CollectorBatchDecoderError/duplicateEventName(_:firstType:secondType:)`` when
    ///   two of the discovered events share a name.
    public init(plan: TrackingPlan, instrument: any Instrument = InstrumentationSystem.instrument) throws(CollectorBatchDecoderError) {
        try self.init(plan: plan, events: DiscoveredEvent.all.map { $0.type }, instrument: instrument)
    }

    /// The records `body` holds, and the ones it couldn't read.
    ///
    /// - Parameter body: A request body in TraffluentCollector's ingest format, as
    ///   ``CollectorBatchEncoder`` writes it.
    /// - Returns: Every record read back, in the body's order, and a report of each that couldn't
    ///   be, with why.
    /// - Throws: ``NotACollectorBatch`` when `body` isn't JSON, isn't an object, or has no
    ///   `records` array.
    /// - Complexity: O(*n* log *n*) in the body's length, for sorting each event's properties.
    public func batch(from body: Data) throws(NotACollectorBatch) -> DecodedCollectorBatch {
        guard let json = JSON(parsing: Array(body)) else { throw .notJSON }
        guard let members = json.object else { throw .notAnObject }
        guard let member = members["records"] else { throw .missingRecords }
        guard let items = member.array else { throw .recordsNotAnArray }
        var records: [EventRecord] = []
        records.reserveCapacity(items.count)
        var undecodedRecords: [UndecodedRecord] = []
        for (offset, item) in items.enumerated() {
            do throws(CollectorDecodingError) {
                records.append(try record(from: item))
            } catch {
                undecodedRecords.append(UndecodedRecord(offset: offset, recordID: item.recordID, eventName: item.eventName, reason: error))
            }
        }
        return DecodedCollectorBatch(records: records, undecodedRecords: undecodedRecords)
    }

    private func record(from item: JSON) throws(CollectorDecodingError) -> EventRecord {
        guard let members = item.object else { throw .notAnObject }
        guard let id = item.recordID else { throw .malformedMember("id") }
        guard let name = item.eventName else { throw .malformedMember("name") }
        guard let timestamp = members["timestamp"]?.string.flatMap(Date.init(iso8601Timestamp:)) else { throw .malformedMember("timestamp") }
        guard let properties = members["properties"]?.object else { throw .malformedMember("properties") }
        guard let context = members["context"]?.object else { throw .malformedMember("context") }
        guard case .boolean(let isRedelivered)? = members["isRedelivered"] else { throw .malformedMember("isRedelivered") }
        guard let event = events[name] else { throw .unknownEvent(name: name) }
        guard let types = event.propertyTypes else { throw .unknownVersion(name: name, version: event.type.schemaVersion) }
        var record = EventRecord(
            id: id,
            event: try event.decode(properties, types: types),
            timestamp: timestamp,
            sourceLocation: nil,
            context: try ServiceContext(collectorContext: context, instrument: instrument),
            isRedelivered: isRedelivered
        )
        // As the tracker's worker sets it: the body held the values, and a destination that
        // redacts them clears it again.
        record.revealsSensitiveValues = true
        return record
    }
}

/// An event's name and schema version: what a type is looked up in the plan by.
private struct PlannedVersion: Hashable {
    let name: String
    let version: Int
}

/// An event type records are read into, and its property types in the plan, `nil` when the plan
/// has no schema of its version.
private struct DecodableEvent: Sendable {
    let type: any (Event & Decodable).Type
    let propertyTypes: [String: WrittenType?]?

    /// The event `properties` hold, read through `types`.
    func decode(_ properties: [String: JSON], types: [String: WrittenType?]) throws(CollectorDecodingError) -> any Event {
        do throws(UndecodableProperty) {
            return try type.init(properties: properties, types: types)
        } catch {
            throw .undecodableProperty(event: type.name, property: error.property)
        }
    }
}

extension JSON {
    /// A record's `id`, when it is an object with one that is a UUID string.
    fileprivate var recordID: UUID? {
        object?["id"]?.string.flatMap(UUID.init(uuidString:))
    }

    /// A record's event `name`, when it is an object with one that is a string.
    fileprivate var eventName: String? {
        object?["name"]?.string
    }
}
