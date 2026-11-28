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
/// - its event, a value of the decoder's type of that `Event/name` and version, read through the
///   type's schema in `plan`, its `Sensitive` values included;
/// - the context the body's `context` holds: the session's `SessionKey`, the sample rate, the
///   standard context keys, and the trace context, which the decoder's instrument extracts.
///
/// A record has no `EventRecord/sourceLocation` or `EventRecord/deliveryTag`, which the body
/// doesn't hold, and it reveals its sensitive values, as a tracked record does, so a destination
/// made with `redactingSensitiveValues()` still redacts them. Encoding the records again with a
/// ``CollectorBatchEncoder`` of the same plan, and an instrument that injects what it extracts,
/// writes the same bytes.
///
/// Each record is read at the version its `version` member states, into the decoder's type of
/// that name and version, through the plan's schema of both. A server that reads the batches of
/// several releases of an app is given a type of each version they send. It declares the earlier
/// versions in a `private` or `fileprivate` scope, where `@Event` lets a second type of one name
/// build, and a plan made from the same types holds a schema of each. That scope is a file-scope
/// `private` type or a `fileprivate` one, not a `private` member of another type
/// ([Defining Events](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/definingevents)).
///
/// ```swift
/// @Event(name: "checkout_started", version: 2)
/// struct CheckoutStarted {
///     var items: Int
///     var currency: String
/// }
///
/// // Version 1, which releases still installed send.
/// private enum EarlierVersions {
///     @Event(name: "checkout_started")
///     struct CheckoutStarted {
///         var items: Int
///     }
/// }
///
/// let decoder = try CollectorBatchDecoder(plan: try TrackingPlan())
/// ```
///
/// A record without a `version` member, as releases before the member was written send, is read
/// at version 1 when the decoder has a type and the plan a schema of its event at 1, and otherwise
/// at the lowest version it has both of. Those releases sent version 1 unless an event declared
/// another. A record one of them sent at a raised version is read at version 1 too when the
/// decoder has version 1: it is reported as
/// ``CollectorDecodingError/undecodableProperty(event:property:)`` when its properties don't fit
/// that type, and read as version 1 when they do.
///
/// A record the decoder can't read is left out and the batch's other records are read: one whose
/// event it has no type of, one at a version it has no type of or the plan no schema of, a member
/// that is missing or holds what the encoder never writes, and a property the event's type can't read
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
// is decoded into, and the plan holds none, only schemas. Rejected: types alone (each @Event's own
// schema), which would read a version the plan has dropped and could disagree with the encoder's
// schema; and a plan alone, which can't make a value.
//
// The body states each record's version, so a type is found by name and version (TRAF-151).
// Rejected: reading every record at the version of the decoder's one type of its name, as before
// the member, which misreads an older app's records once a version is raised; and trying each
// version held until one decodes, as TraffluentCollector's validator does, which reads a record
// that fits two versions at whichever is tried first.
//
// A record without the member is read at 1, else at the lowest version held, rather than the
// newest: only releases from before the member leave it out, and they sent 1 unless an event
// declared another. The newest would misread every version 1 record of an event raised since.
public struct CollectorBatchDecoder: Sendable {
    // Each event name's types by version, with their property types from the plan, looked up once
    // here rather than per record.
    private let events: [String: EventVersions]
    private let instrument: any Instrument

    /// A decoder of records of `events`, whose properties `plan` describes, extracting each
    /// record's trace context as `instrument` does.
    ///
    /// - Parameters:
    ///   - plan: The tracking plan the encoder that wrote the batches was made with: each record's
    ///     event is read through the schema of its name and version here.
    ///   - events: The event types records are read back into, one per `Event/name` and
    ///     `Event/schemaVersion`. A type in a `private` or `fileprivate` scope is read as any other.
    ///   - instrument: What extracts each record's trace context from its `trace` member; the
    ///     bootstrapped `InstrumentationSystem.instrument`, read once here, by default.
    /// - Throws: ``CollectorBatchDecoderError/duplicateEvent(_:version:firstType:secondType:)``
    ///   when two of `events` share a name and a version.
    public init(
        plan: TrackingPlan,
        events: [any (Event & Decodable).Type],
        instrument: any Instrument = InstrumentationSystem.instrument
    ) throws(CollectorBatchDecoderError) {
        var schemas: [PlannedVersion: EventSchema] = [:]
        for schema in plan.schemas {
            schemas[PlannedVersion(name: schema.name, version: schema.version)] = schema
        }
        // Every type by name and version, for a duplicate's error to name the first.
        var listed: [PlannedVersion: any (Event & Decodable).Type] = [:]
        // The types the plan has a schema of, by name and version; a name whose types have none
        // still has an entry, so its records are unknownVersion rather than unknownEvent.
        var readable: [String: [Int: DecodableEvent]] = [:]
        for type in events {
            let version = PlannedVersion(name: type.name, version: type.schemaVersion)
            if let first = listed[version] {
                throw .duplicateEvent(version.name, version: version.version, firstType: String(reflecting: first), secondType: String(reflecting: type))
            }
            listed[version] = type
            var versions = readable[version.name] ?? [:]
            versions[version.version] = schemas[version].map { DecodableEvent(type: type, propertyTypes: $0.propertyTypes) }
            readable[version.name] = versions
        }
        self.events = readable.mapValues(EventVersions.init(readable:))
        self.instrument = instrument
    }

    /// A decoder of records of every `@Event` the program links (`DiscoveredEvent/all`), whose
    /// properties `plan` describes.
    ///
    /// - Parameters:
    ///   - plan: The tracking plan the encoder that wrote the batches was made with.
    ///   - instrument: What extracts each record's trace context; the bootstrapped
    ///     `InstrumentationSystem.instrument` by default.
    /// - Throws: ``CollectorBatchDecoderError/duplicateEvent(_:version:firstType:secondType:)``
    ///   when two of the discovered events share a name and a version.
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
        let statedVersion: Int?
        switch members["version"] {
        case nil:
            statedVersion = nil
        case .integer(let version)?:
            // Past a 32-bit Int's range, where no event type can have the version, it is malformed.
            guard let version = Int(exactly: version) else { throw .malformedMember("version") }
            statedVersion = version
        case _?:
            throw .malformedMember("version")
        }
        guard let versions = events[name] else { throw .unknownEvent(name: name) }
        let version = statedVersion ?? versions.unstatedVersion
        guard let event = versions.readable[version] else { throw .unknownVersion(name: name, version: version) }
        var record = EventRecord(
            id: id,
            event: try event.decode(properties),
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

/// The event types of one name records can be read into, by version.
private struct EventVersions: Sendable {
    /// The types the plan has a schema of, by version: the versions a record can be read at.
    let readable: [Int: DecodableEvent]
    /// The version a record without a `version` member is read at: 1 when it is readable, else
    /// the lowest that is, and 1 when none is.
    let unstatedVersion: Int

    /// The versions of `readable`, with the version a record without one is read at.
    init(readable: [Int: DecodableEvent]) {
        self.readable = readable
        unstatedVersion = readable[1] != nil ? 1 : readable.keys.min() ?? 1
    }
}

/// An event type records are read into, and its property types in the plan.
private struct DecodableEvent: Sendable {
    let type: any (Event & Decodable).Type
    let propertyTypes: [String: WrittenType?]

    /// The event `properties` hold, read through the plan's property types.
    func decode(_ properties: [String: JSON]) throws(CollectorDecodingError) -> any Event {
        do throws(UndecodableProperty) {
            return try type.init(properties: properties, types: propertyTypes)
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
