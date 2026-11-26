public import Events
import Foundation
public import HTTPDestinations
import Instrumentation
import Logging
import PropertyJSON
import Sessions
public import TrackingPlans

/// The ``/HTTPDestinations/BatchEncoder`` of PostHog's batch capture API, so an `HTTPDestination`
/// can send events to PostHog Cloud or a self-hosted PostHog's `POST /batch/`.
///
/// ```swift
/// import HTTPDestinations
/// import Instrumentation
/// import PostHogEncoding
/// import TrackingPlans
///
/// let plan = try TrackingPlan(schemas: [SignedUp.schema, SessionStarted.schema, SessionEnded.schema])
/// let postHog = HTTPDestination(
///     endpoint: batchURL,  // https://us.i.posthog.com/batch/, or your instance's
///     instrument: NoOpInstrument(),  // no trace context in the request's header fields
///     encoder: PostHogBatchEncoder(projectToken: projectToken, plan: plan))
/// let delivery = tracker.records.batch().deliver(to: postHog)
/// ```
///
/// The body is a JSON object of content type `application/json` with two members: `api_key`, the
/// project token, and `batch`, one object per record, oldest first, with these members:
///
/// | Member | Holds |
/// |---|---|
/// | `distinct_id` | The record's session, its `SessionKey`, as a lowercase UUID string; the record's own `EventRecord/id` when its context has no session |
/// | `event` | The event's `Event/name`, as it is |
/// | `properties` | The event's stored properties, by name, then the members listed below |
/// | `timestamp` | When the event was tracked: ISO 8601 in UTC, with milliseconds (`2026-11-23T14:03:27.512Z`) |
/// | `uuid` | The record's `EventRecord/id`, as a lowercase UUID string; a redelivered record keeps it |
///
/// The session is the only identifier sent, and every event is anonymous: `properties` holds
/// `$process_person_profile: false`, so PostHog makes no person profile, and `$geoip_disable: true`,
/// so PostHog doesn't add a location from the request's IP address. A record with no session (one
/// tracked by a tracker without `Enricher.sessions()`, or one a store recovered after a relaunch,
/// which keeps no context) is its own anonymous person, linked to nothing: PostHog rejects a whole
/// batch when one of its events has no `distinct_id`. PostHog counts a person per `distinct_id`,
/// so its unique users are sessions. The session is also sent as `$session_id`, which PostHog's
/// sessions and web analytics group events by (`SessionKey` is the UUIDv7 they require); a record
/// with no session has none. The record's vendor identifier and trace context, and any other
/// context value, aren't sent.
///
/// Properties are read from the event's `Encodable` form, which `@Event` derives, through the
/// types its schema in `plan` lists: a `String` is a string; a `Bool` a boolean; an integer, a
/// `Double` or a `Float` a number; a `Date` an ISO 8601 string, as `timestamp` is; a `UUID` an
/// uppercase UUID string; an array an array; and an optional's `nil` is `null`. A `Refined` value
/// is its value. A type the plan can't map is written as its encoding holds it. A
/// ``/Events/Sensitive`` value is never sent, whatever the record reveals: the property is left
/// out, an element of an array is `null`, and one inside a type the plan can't map is `null`. A property whose name starts with
/// `$`, which only a hand-written `Encodable` conformance can write, or is `distinct_id`, is
/// left out and logged at notice level, as PostHog reads those names as settings (`$set`,
/// `$process_person_profile`) or the identity.
///
/// `properties` also holds these members, for each of the keys the record's context has a value
/// for:
///
/// | Member | Key | Holds |
/// |---|---|---|
/// | `$app_namespace`, `$app_version`, `$app_build` | `ApplicationKey` | The bundle identifier, version and build, each left out when `nil` |
/// | `$device_model`, `$device_type` | `DeviceKey` | The model, and `Mobile`, `Tablet`, `Desktop`, `TV` or `Vision` for the form factor; no `$device_type` for a watch |
/// | `$locale` | `LocaleKey` | The locale's BCP 47 identifier, such as `en-US` |
/// | `$network_wifi`, `$network_cellular` | `NetworkKey` | Whether the connection is Wi-Fi, and whether it is cellular |
/// | `$os_name`, `$os_version` | `OperatingSystemKey` | The operating system's name and version |
///
/// A record the encoder can't write is left out of the body, and the batch's other records are
/// sent: one whose event and version `plan` doesn't describe, one whose event name starts with `$`
/// (a name PostHog keeps for its own events), one whose event isn't `Encodable`, or one that
/// holds a value JSON can't (``PostHogEncodingError``). Each is logged at error level;
/// ``batch(of:)`` returns them as ``PostHogSkippedRecord``s. When every record of a batch is left
/// out, ``encode(_:)`` throws, so `HTTPDestination` sends nothing for it.
///
/// PostHog answers a batch it takes with 200, so `HTTPDestination` retries one that gets no
/// response, a 5xx, 408 or 429, and drops one it rejects. A record sent again keeps its `uuid`.
/// The bytes are the same for the same records on every run and platform: no whitespace, object
/// members in the order of their names' UTF-8 bytes. PostHog takes a body of up to 20 MB, so keep
/// batches far smaller (`batch()` sends 20 records at most).
public struct PostHogBatchEncoder: BatchEncoder {
    private let projectToken: String
    // A dictionary of each event version's property types, parsed once here rather than per
    // record: every record of a batch is looked up in it.
    private let propertyTypes: [EventVersion: [String: WrittenType?]]

    private static let logger = Logger(label: "PostHogEncoding.PostHogBatchEncoder")

    /// An encoder of the events `plan` describes, for the PostHog project of `projectToken`.
    ///
    /// - Parameters:
    ///   - projectToken: The project's token (`phc_...`), from the project's settings: public, as
    ///     every PostHog client sends it, but the adopter's configuration.
    ///   - plan: The tracking plan of every event the encoder is given: each record's event is
    ///     read through the schema of its name and `Event/schemaVersion` here.
    public init(projectToken: String, plan: TrackingPlan) {
        self.projectToken = projectToken
        var propertyTypes: [EventVersion: [String: WrittenType?]] = [:]
        for schema in plan.schemas {
            propertyTypes[EventVersion(name: schema.name, version: schema.version)] = schema.propertyTypes
        }
        self.propertyTypes = propertyTypes
    }

    /// The request body for `batch`: its records as PostHog's batch capture API takes them, but
    /// for those it can't encode, which are logged at error level and left out.
    ///
    /// - Parameter batch: Records of tracked events, oldest first.
    /// - Returns: The body's JSON, of content type `application/json`.
    /// - Throws: The ``PostHogEncodingError`` of the first record when `batch` has records and
    ///   none can be encoded, so `HTTPDestination` sends nothing for it.
    /// - Complexity: O(*n* log *n*) in the batch's size, for sorting each object's members.
    public func encode(_ batch: [EventRecord]) throws(PostHogEncodingError) -> EncodedBatch {
        let encoded = self.batch(of: batch)
        for skipped in encoded.skippedRecords {
            Self.logger.error("Left a record of \(skipped.eventName) version \(skipped.schemaVersion) out of the batch: \(skipped.reason)")
        }
        guard let body = encoded.body else {
            // `body` is nil only when the batch had records and every one was skipped, so the
            // first skipped record exists.
            throw encoded.skippedRecords[0].reason
        }
        return body
    }

    /// `batch` encoded as ``encode(_:)`` encodes it, with the records left out of the body.
    ///
    /// - Parameter batch: Records of tracked events, oldest first.
    /// - Returns: The body of every record that could be encoded, `nil` when `batch` has records
    ///   and none could, and each record left out, with why.
    /// - Complexity: O(*n* log *n*) in the batch's size, for sorting each object's members.
    public func batch(of batch: [EventRecord]) -> PostHogBatch {
        var events: [JSON] = []
        events.reserveCapacity(batch.count)
        var skippedRecords: [PostHogSkippedRecord] = []
        for record in batch {
            do {
                events.append(try json(of: record))
            } catch {
                skippedRecords.append(PostHogSkippedRecord(recordID: record.id, eventName: record.name, schemaVersion: type(of: record.event).schemaVersion, reason: error))
            }
        }
        guard !events.isEmpty || batch.isEmpty else {
            return PostHogBatch(body: nil, skippedRecords: skippedRecords)
        }
        let body = JSON.object(["api_key": .string(projectToken), "batch": .array(events)]).minified
        return PostHogBatch(body: EncodedBatch(body: Data(body.utf8), contentType: "application/json"), skippedRecords: skippedRecords)
    }

    private func json(of record: EventRecord) throws(PostHogEncodingError) -> JSON {
        let version = EventVersion(name: record.name, version: type(of: record.event).schemaVersion)
        guard let types = propertyTypes[version] else {
            throw .unknownEvent(name: version.name, version: version.version)
        }
        let distinctID = record.distinctID
        guard !record.name.hasPrefix("$") else {
            throw .reservedEventName(name: record.name)
        }
        var properties: [String: JSON]
        do {
            // Never a Sensitive value: PostHog is a vendor's store, whatever the record reveals.
            properties = try record.properties(types: types, writingSensitiveValues: false)
        } catch {
            throw PostHogEncodingError(error)
        }
        // PostHog reads $-prefixed properties as settings ($set, $process_person_profile), and a
        // `distinct_id` property as the identity when the top-level one is missing.
        for key in properties.keys.sorted() where key.hasPrefix("$") || key == "distinct_id" {
            Self.logger.notice("Left property \(key) out of a record of \(record.name): PostHog reads the name as identity or a setting")
            properties[key] = nil
        }
        for (key, value) in record.postHogContext {
            properties[key] = value
        }
        // Written after the event's and context's properties, so neither can replace it.
        if let session = record.context[SessionKey.self] {
            properties["$session_id"] = .string(session.uuidString.lowercased())
        }
        properties["$process_person_profile"] = .boolean(false)
        properties["$geoip_disable"] = .boolean(true)
        return .object([
            "distinct_id": .string(distinctID),
            "event": .string(record.name),
            "properties": .object(properties),
            "timestamp": .string(record.timestamp.postHogTimestamp),
            "uuid": .string(record.id.uuidString.lowercased()),
        ])
    }
}

/// An event's name and schema version: what a record's event is looked up in the plan by.
private struct EventVersion: Hashable {
    let name: String
    let version: Int
}

extension EventRecord {
    /// Who the event is PostHog's: its session, or, for a record with none, the record itself.
    ///
    /// D4: the session is the only identifier sent. A record without one (a recovered record keeps
    /// no context) becomes its own anonymous person rather than being skipped, which would let the
    /// delivery acknowledge it and the store delete it, or sent without a `distinct_id`, which
    /// makes PostHog reject the whole batch.
    fileprivate var distinctID: String {
        let identifier = context[SessionKey.self] ?? id
        return identifier.uuidString.lowercased()
    }
}

extension PostHogEncodingError {
    /// The reason the property reader gave, as this encoder's.
    fileprivate init(_ error: PropertyReadingError) {
        switch error {
        case .notEncodable(let name): self = .notEncodable(name: name)
        case .unrepresentableValue(let event, let property): self = .unrepresentableValue(event: event, property: property)
        }
    }
}
