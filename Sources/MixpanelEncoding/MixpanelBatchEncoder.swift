public import Events
import Foundation
public import HTTPDestinations
import JSONValues
import Logging
public import PropertyJSON
public import TrackingPlans

/// The ``/HTTPDestinations/BatchEncoder`` of Mixpanel's track API, so an `HTTPDestination` can send
/// events to a Mixpanel project's `POST /track`.
///
/// Make the destination with ``HTTPDestinations/HTTPDestination/mixpanel(projectToken:region:plan:backoff:clock:)``,
/// which fills in the endpoint, this encoder and Mixpanel's limits:
///
/// ```swift
/// let mixpanel = try HTTPDestination.mixpanel(
///     projectToken: projectToken,
///     region: .eu,  // or .us or .india, where the project's data resides
///     plan: plan)
/// ```
///
/// The body is a JSON array of content type `application/json`, one object per record, oldest
/// first, each with two members: `event`, the event's `Event/name` as it is, and `properties`, the
/// event's stored properties by name, then these members:
///
/// | Member | Holds |
/// |---|---|
/// | `$device_id` | The record's session, its `SessionKey`, as a lowercase UUID string; left out for a record with no session |
/// | `$insert_id` | The record's `EventRecord/id`, as a lowercase UUID string; a redelivered record keeps it |
/// | `distinct_id` | The record's session, as `$device_id` holds it; the record's own `EventRecord/id` when its context has no session |
/// | `ip` | `"0"`, so Mixpanel adds no location from the request's address |
/// | `time` | When the event was tracked, in whole milliseconds since 1970 |
/// | `token` | The project token |
///
/// The session is the only identifier sent: there is no `$user_id`, and no other device
/// identifier. Mixpanel counts a user per `distinct_id`, so its unique users are sessions. A
/// record with no session (one tracked by a tracker without `Enricher.sessions()`) is its own
/// anonymous user, linked to nothing, rather than an event with no `distinct_id`, which Mixpanel
/// would attribute to no user, or to a hash of the request's address. Mixpanel treats two events
/// of the same `event`, `time`, `distinct_id` and `$insert_id` as one. A record a store recovers
/// after a relaunch keeps its session, so it goes out with the `distinct_id` and `$device_id` of
/// its first send, and Mixpanel treats it as the copy it had already stored, if it had. The record's vendor identifier and
/// trace context, and any other context value, aren't sent.
///
/// Properties are read through the event's schema in `plan`, as `PropertyReader` reads them. A
/// ``/Events/Sensitive`` value is never sent, whatever the record reveals: the property is left
/// out, an element of an array is `null`, and one inside a type the plan can't map is `null`.
/// Mixpanel cuts each string down to 255 characters. It drops an event of 255 properties or more,
/// counting the members above and the default properties below, one holding an array of 255
/// elements or more, and one whose property nests objects more than 3 deep, though it answers
/// 200: the encoder enforces these limits, leaving such a record out of the request.
///
/// `properties` also holds Mixpanel's default properties, named as its Swift SDK names them, for
/// each of the keys the record's context has a value for:
///
/// | Member | Key | Holds |
/// |---|---|---|
/// | `$app_version_string`, `$app_build_number` | `ApplicationKey` | The version and build, each left out when `nil` |
/// | `$model` | `DeviceKey` | The model |
/// | `$wifi` | `NetworkKey` | Whether the connection is Wi-Fi |
/// | `$os`, `$os_version` | `OperatingSystemKey` | The operating system's name and version |
///
/// A record the encoder can't write is left out of the request, and the batch's other records are
/// sent: one whose event and version `plan` doesn't describe, one whose event name starts with
/// `$`, as Mixpanel's own events' do, one with a property named as one Mixpanel reads for itself,
/// one past Mixpanel's limits on properties, array elements or nesting, one whose event isn't
/// `Encodable`, one that holds a value JSON can't, one whose timestamp is no
/// `time` Mixpanel takes, and one too large for Mixpanel (``MixpanelEncodingError``).
/// ``requests(for:)`` returns them as `SkippedRecord`s, which `HTTPDestination` logs and reports
/// on its `dropReports`.
///
/// ``requests(for:)`` splits a batch into requests within the encoder's limit, ``batchLimit`` by
/// default, and makes none for a batch with no record it can write, so `HTTPDestination` sends
/// nothing for it. Mixpanel answers a request it reads with 200, so `HTTPDestination` retries one
/// that gets no response, a 5xx, 408 or 429, and drops one it rejects, such as with 400, 401 or
/// 413. Mixpanel answers 200 as well when it ingests none of a request's events: a wrong region,
/// or a token of no project, may be answered 200 with nothing stored, so check the project's Live
/// View after setting it up. Its track API ingests only events from the last 5 days: a record
/// older than that when it is sent, such as one a store kept through a long time offline, is
/// counted as delivered and not stored. A record sent again keeps its `$insert_id`. The bytes are
/// the same for the same records on every run and platform: no whitespace, object members in the
/// order of their names' UTF-8 bytes.
public struct MixpanelBatchEncoder: BatchEncoder {
    /// No status beyond the 408, 429 and 5xx that `HTTPDestination` retries for every encoder.
    public static let transientStatuses: Set<TransientStatus> = []

    // From Mixpanel's ingestion API reference, read on 2026-11-27:
    // https://developer.mixpanel.com/reference/track-event (/track's 2,000 events a request, the
    // project token in each event, `time` in seconds or milliseconds, an event under 1 MB, 255
    // properties, the `ip` query parameter, 200 for a request read, the `api`, `api-eu` and
    // `api-in` servers), https://developer.mixpanel.com/reference/import-events ("the limits for
    // track are the same": 10 MB a request; `$insert_id` at most 36 bytes of letters, digits and
    // `-`; times before 1971 rejected; `ip` 0 to skip geolocation; 400, 401, 403, 413, 429 and
    // 5xx), https://docs.mixpanel.com/troubleshooting/errors/413-payload-too-large (whose sample
    // answer quotes a limit of 2,097,152 bytes), and
    // https://docs.mixpanel.com/docs/data-structure/property-reference/reserved-properties.
    // The body is a JSON array sent as `application/json`, though /track's parameter table says
    // form-encoded: the reference's request body and mixpanel-swift's FlushRequest both post
    // `application/json`, so don't change it to a `data=` form.
    /// Mixpanel's limits on one request: 2,000 events, 2,000,000 bytes of body, and 999,999 bytes
    /// of one event.
    ///
    /// Mixpanel's track API takes up to 2,000 events in one request, and an event smaller than
    /// 1 MB. It documents 10 MB a request, but quotes a limit of 2,097,152 bytes in a sample
    /// answer of 413, so a request of 2,000,000 bytes is under either.
    public static let batchLimit = (try? BatchLimit(maximumRecordCount: 2_000, maximumByteCount: 2_000_000, maximumRecordByteCount: 999_999)) ?? .unlimited

    /// 1971-01-01T00:00:00Z in milliseconds since 1970: Mixpanel rejects an earlier `time`, and
    /// would read a smaller count of milliseconds as seconds.
    private static let earliestTime: Int64 = 31_536_000_000

    /// Mixpanel drops an event of this many properties or more.
    private static let propertyLimit = 255

    /// Mixpanel drops an event holding an array of this many elements or more.
    private static let arrayElementLimit = 255

    /// Mixpanel drops an event whose property's value nests objects deeper than this.
    private static let objectDepthLimit = 3

    private static let logger = Logger(label: "MixpanelEncoding.MixpanelBatchEncoder")

    private let projectToken: String
    private let reader: PropertyReader
    private let limit: BatchLimit

    /// Why a record was left out of the batch's requests.
    public typealias Failure = MixpanelEncodingError

    /// An encoder of the events `plan` describes, for the Mixpanel project of `projectToken`,
    /// splitting each batch to `limit`.
    ///
    /// - Parameters:
    ///   - projectToken: The project's token, from the project's settings: public, as every
    ///     Mixpanel client sends it, but the adopter's configuration. Never the project's secret
    ///     or a service account's credentials, which Mixpanel's import API takes and which must not
    ///     ship in an app.
    ///   - plan: The tracking plan of every event the encoder is given: each record's event is
    ///     read through the schema of its name and `Event/schemaVersion` here.
    ///   - limit: The most each request holds; ``batchLimit``, Mixpanel's, by default.
    ///
    /// The encoder logs a notice for each property of `plan` named as one Mixpanel reads for
    /// itself, as it will skip every record of that event
    /// (``MixpanelEncodingError/reservedPropertyName(event:property:)``).
    public init(projectToken: String, plan: TrackingPlan, limit: BatchLimit = MixpanelBatchEncoder.batchLimit) {
        self.projectToken = projectToken
        reader = PropertyReader(plan: plan)
        self.limit = limit
        // Logged once here, where the plan is set up, as every record of such an event will be
        // skipped: setup still succeeds, since the plan may hold events the app never sends here.
        for schema in plan.schemas {
            for property in schema.properties where property.name.isReservedByMixpanel {
                Self.logger.notice("Mixpanel reserves the name of property \(property.name) of event \(schema.name), version \(schema.version): every record of it will be skipped")
            }
        }
    }

    /// `batch` as the requests Mixpanel takes, each within the encoder's limit, with the records
    /// left out of them.
    ///
    /// - Parameter batch: Records of tracked events, oldest first.
    /// - Returns: The requests, in order, none when no record can be written, and each record left
    ///   out, with why (``MixpanelEncodingError``): one it can't encode, one past Mixpanel's
    ///   limits on properties, array elements or nesting, and one whose event is over
    ///   the limit's bytes for one event, or for a request of it alone
    ///   (``MixpanelEncodingError/oversized(byteCount:)``).
    /// - Complexity: O(*n* log *n*) in the batch's size, for sorting each object's members.
    public func requests(for batch: [EventRecord]) -> BatchRequests<MixpanelEncodingError> {
        limit.requests(for: batch, in: .array) { record throws(MixpanelEncodingError) in
            try json(of: record)
        } oversized: { byteCount in
            .oversized(byteCount: byteCount)
        }
    }

    private func json(of record: EventRecord) throws(MixpanelEncodingError) -> JSON {
        var properties: [String: JSON]
        do {
            // Never a Sensitive value: Mixpanel is a vendor's store, whatever the record reveals.
            properties = try reader.properties(of: record, includingSensitiveValues: false)
        } catch {
            // A reserved name is reported before the reader's other reasons, but after an event
            // the plan doesn't describe.
            if case .unknownEvent = error {} else if record.name.hasPrefix("$") {
                throw .reservedEventName(name: record.name)
            }
            throw MixpanelEncodingError(error)
        }
        guard !record.name.hasPrefix("$") else {
            throw .reservedEventName(name: record.name)
        }
        // Mixpanel's properties share one object with the event's, so an event's property of a
        // name Mixpanel reads would change how it ingests the event (`$ignore` drops it, `bucket`
        // hides it) or be replaced by the encoder's. The record is skipped and reported rather
        // than sent without the property, as `time`, `token` and `ip` are plausible names for an
        // event's own data, and losing one quietly would be a silently wrong row.
        if let reserved = properties.keys.filter(\.isReservedByMixpanel).min(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
            throw .reservedPropertyName(event: record.name, property: reserved)
        }
        let time: Int64
        do {
            time = try record.timestamp.millisecondsSince1970()
        } catch {
            throw .unrepresentableTimestamp
        }
        guard time >= Self.earliestTime else {
            throw .unrepresentableTimestamp
        }
        for (key, value) in record.mixpanelContext {
            properties[key] = value
        }
        // D4: the session is the only identifier sent. A record without one (its tracker has no
        // sessions enricher) becomes its own anonymous user rather than being skipped, which would
        // let the delivery acknowledge it and the store delete it, or sent without a
        // `distinct_id`, which Mixpanel would attribute to no user, or to a hash of the request's
        // address.
        let identity = record.pseudonymousIdentity
        let distinctID = identity.uuid.uuidString.lowercased()
        // Mixpanel's Simplified ID Merge reads `$device_id` without a `$user_id` as an anonymous
        // device, whose ID is the event's `distinct_id`: a session is one. A record with no session
        // is one event, no device's stream, so it gets `distinct_id` alone.
        if case .session = identity {
            properties["$device_id"] = .string(distinctID)
        }
        properties["$insert_id"] = .string(record.deduplicationID)
        properties["distinct_id"] = .string(distinctID)
        // The endpoint's `ip=0` asks Mixpanel not to locate the request's address, and an `ip`
        // of 0 asks it of each event, which is what its docs give for one payload.
        properties["ip"] = .string("0")
        properties["time"] = .integer(time)
        properties["token"] = .string(projectToken)
        // Checked on the event as sent, so the count includes the encoder's members and the
        // context's: Mixpanel answers 200 for a request whose events it drops, so a record past
        // its limits would be acknowledged and deleted without being stored.
        guard properties.count < Self.propertyLimit else {
            throw .tooManyProperties(event: record.name, count: properties.count)
        }
        for (name, value) in properties.sorted(by: { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }) {
            if let count = value.longestArrayCount, count >= Self.arrayElementLimit {
                throw .tooManyArrayElements(event: record.name, property: name, count: count)
            }
            guard value.objectDepth <= Self.objectDepthLimit else {
                throw .nestedTooDeeply(event: record.name, property: name)
            }
        }
        return .object([
            "event": .string(record.name),
            "properties": .object(properties),
        ])
    }
}

extension MixpanelEncodingError {
    /// The reason the property reader gave, as this encoder's.
    fileprivate init(_ error: PropertyReadingError) {
        switch error {
        case .unknownEvent(let name, let version): self = .unknownEvent(name: name, version: version)
        case .notEncodable(let name): self = .notEncodable(name: name)
        case .unrepresentableValue(let event, let property): self = .unrepresentableValue(event: event, property: property)
        }
    }
}

extension String {
    /// Whether Mixpanel reads an event property of this name for itself: a `$`-prefixed one (its
    /// default and reserved properties, `$insert_id`, `$user_id`, `$ignore`), or one of the
    /// unprefixed names its reserved properties list that change how it ingests an event.
    fileprivate var isReservedByMixpanel: Bool {
        hasPrefix("$") || self == "token" || self == "time" || self == "distinct_id" || self == "ip" || self == "bucket"
    }
}

extension JSON {
    /// The most elements of an array in the value, itself or nested in it at any depth; `nil`
    /// when it holds no array.
    fileprivate var longestArrayCount: Int? {
        switch self {
        case .array(let elements):
            return elements.compactMap(\.longestArrayCount).reduce(elements.count, max)
        case .object(let members):
            return members.values.compactMap(\.longestArrayCount).max()
        case .string, .integer, .number, .boolean, .null:
            return nil
        }
    }

    /// How deep the value nests objects: 0 for a scalar, 1 for an object of scalars. An array
    /// adds no depth, as Mixpanel counts objects.
    fileprivate var objectDepth: Int {
        switch self {
        case .array(let elements):
            return elements.map(\.objectDepth).max() ?? 0
        case .object(let members):
            return 1 + (members.values.map(\.objectDepth).max() ?? 0)
        case .string, .integer, .number, .boolean, .null:
            return 0
        }
    }
}
