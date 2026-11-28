public import Events
public import Foundation
public import HTTPDestinations
import JSONValues
import Logging
public import PropertyJSON
public import TrackingPlans

/// The ``/HTTPDestinations/BatchEncoder`` of Mixpanel's track API, so an `HTTPDestination` can send
/// events to a Mixpanel project's `POST /track`.
///
/// Make the destination with ``HTTPDestinations/HTTPDestination/mixpanel(projectToken:region:plan:backoff:clock:now:)``,
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
/// `time` Mixpanel takes, one tracked more than 119 hours (5 days less an hour) before the batch
/// is encoded or more than an hour after, and one too large for Mixpanel
/// (``MixpanelEncodingError``).
/// ``requests(for:)`` returns them as `SkippedRecord`s, which `HTTPDestination` logs and reports
/// on its `dropReports`.
///
/// ``requests(for:)`` splits a batch into requests within the encoder's limit, ``batchLimit`` by
/// default, gives each a deadline 119 hours after its oldest record was tracked, and makes none
/// for a batch with no record it can write, so `HTTPDestination` sends nothing for it. Mixpanel
/// answers a request it reads with 200, so `HTTPDestination` retries one
/// that gets no response, a 5xx, 408 or 429, and drops one it rejects, such as with 400, 401 or
/// 413. It answers 200 as well to a request in which it finds no valid event, and says so in the
/// body: with `verbose=1`, which the destination's endpoint sets, `{"status": 0, "error": ...}`.
/// ``outcome(of:for:)`` reads that as rejected, so `HTTPDestination` drops the request and reports it
/// with Mixpanel's error. A `status` of 1 means only that one event or more was well formed, not
/// that the token names a project, so a wrong region, or a token of no project, may still be
/// answered 200 with nothing stored: check the project's Live View after setting it up.
///
/// The track API ingests only events from the last 5 days, and answers 200 while storing nothing
/// for an older one. So a record older than that, such as one a store kept through a long time
/// offline, is dropped and reported rather than sent: left out when its batch is encoded
/// (``MixpanelEncodingError/timestampOutsideWindow``), or, when its request is still being retried
/// at the deadline, dropped with the request and reported as
/// `HTTPDropReport.deadlineExceeded(deadline:recordIDs:)`. The hour to spare is for a queue on
/// Mixpanel's side and clocks that disagree. Mixpanel also rejects an event more than an hour in
/// the future, so a record tracked more than an hour after its batch is encoded is left out as
/// ``MixpanelEncodingError/timestampOutsideWindow`` too.
///
/// A record sent again keeps its `$insert_id`. The bytes are the same for the same records on
/// every run and platform: no whitespace, object members in the order of their names' UTF-8 bytes.
public struct MixpanelBatchEncoder: BatchEncoder {
    /// No status beyond the 408, 429 and 5xx that `HTTPDestination` retries for every encoder.
    public static let transientStatuses: Set<TransientStatus> = []

    // From Mixpanel's track reference, https://developer.mixpanel.com/reference/track-event, read
    // on 2026-11-27: `verbose=1` answers "a JSON Object describing the success or failure of the
    // tracking call" with "two keys: `status`, with the value 1 on success and 0 on failure, and
    // `error`, with a string-valued error message if the request wasn't successful"; without it,
    // the 200 body is `1`, "One or more objects provided are valid. This does not signify a valid
    // project token or secret", or `0`, "No data objects in the body are valid". Its SDKs drop a
    // request answered 0 rather than send it again (mixpanel-swift's FlushRequest, mixpanel-js's
    // request batcher), and its docs give no 200 that a retry would mend.
    /// What Mixpanel's 2xx answer means: rejected when it found no valid event in the request,
    /// and delivered otherwise.
    ///
    /// A body of `{"status": 0, "error": ...}`, as Mixpanel answers with `verbose=1`, or a bare
    /// `0`, is ``/HTTPDestinations/ResponseOutcome/rejected(reason:)``, with Mixpanel's `error` as
    /// the reason, so `HTTPDestination` drops the request and reports it. A `status` of 1, or a
    /// bare `1`, is delivered. So is a body Mixpanel doesn't document, an empty one included,
    /// logged as a notice: the request arrived, and sending it again would repeat it for as long as
    /// Mixpanel answered that way.
    ///
    /// - Parameters:
    ///   - response: The 2xx answer.
    ///   - request: The request it answers, which the answer is read without.
    /// - Returns: Whether Mixpanel stored the request's events, as far as its answer says.
    public static func outcome(of response: HTTPTransportResponse, for request: EncodedRequest) -> ResponseOutcome {
        let decoder = JSONDecoder()
        if let answer = try? decoder.decode(VerboseAnswer.self, from: response.body) {
            switch answer.status {
            case 1:
                return .delivered
            case 0:
                // An empty error says nothing, so the reason falls back to what status 0 means.
                return .rejected(reason: answer.error.flatMap { $0.isEmpty ? nil : $0 } ?? noValidEvent)
            default:
                break
            }
        } else if let status = try? decoder.decode(Int.self, from: response.body) {
            switch status {
            case 1:
                return .delivered
            case 0:
                return .rejected(reason: noValidEvent)
            default:
                break
            }
        }
        logger.notice("Mixpanel answered \(response.head.status) with a body its track API doesn't document; the request counts as delivered")
        return .delivered
    }

    /// The reason of a rejection whose answer gives no error: what Mixpanel's docs say a status of
    /// 0 means.
    private static let noValidEvent = "No data objects in the body are valid"

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

    // https://developer.mixpanel.com/reference/track-event (read 2026-11-27): /track takes
    // "events that occurred within the last 5 days"; /import, with the project's secret, takes
    // older ones, which an app never holds. An hour less, as the GA4, Matomo and Aptabase encoders
    // keep an hour off their vendors' windows.
    /// How long before a batch is encoded, or before its request is sent, a record may have been
    /// tracked, in seconds: 119 hours. Mixpanel's track API takes an event up to 5 days old; the
    /// hour to spare is for a queue on Mixpanel's side and clocks that disagree.
    private static let windowSeconds: TimeInterval = (5 * 24 - 1) * 60 * 60

    /// ``windowSeconds`` as the maximum age of a request's oldest record.
    private static let window: Duration = .seconds(windowSeconds)

    // https://developer.mixpanel.com/reference/track-event (read 2026-11-28) says "The limits for
    // track are the same as /import", and https://developer.mixpanel.com/reference/import-events
    // says "We will reject events with time values that are before 1971-01-01 or more than 1 hour
    // in the future as measured on our servers". The track page also says a future time "will be
    // overwritten with the current present time at ingestion", which holds within that hour. No
    // hour to spare: the record and the batch's encoding read the same device clock, and the
    // request reaches Mixpanel later than it is encoded, when the record is less far ahead.
    /// How long after a batch is encoded a record may say it was tracked, in seconds: 1 hour,
    /// past which Mixpanel rejects an event.
    private static let latestOffset: TimeInterval = 60 * 60

    private static let logger = Logger(label: "MixpanelEncoding.MixpanelBatchEncoder")

    private let projectToken: String
    private let reader: PropertyReader
    private let limit: BatchLimit
    private let now: @Sendable () -> Date

    /// Why a record was left out of the batch's requests.
    public typealias Failure = MixpanelEncodingError

    /// An encoder of the events `plan` describes, for the Mixpanel project of `projectToken`,
    /// splitting each batch to `limit`, leaving out records more than 119 hours older than `now`
    /// gives, or more than an hour newer.
    ///
    /// - Parameters:
    ///   - projectToken: The project's token, from the project's settings: public, as every
    ///     Mixpanel client sends it, but the adopter's configuration. Never the project's secret
    ///     or a service account's credentials, which Mixpanel's import API takes and which must not
    ///     ship in an app.
    ///   - plan: The tracking plan of every event the encoder is given: each record's event is
    ///     read through the schema of its name and `Event/schemaVersion` here.
    ///   - limit: The most each request holds; ``batchLimit``, Mixpanel's, by default.
    ///   - now: The wall-clock time a batch is encoded at, read once a batch; the system's clock by
    ///     default. When it reads NaN or infinite, every record is left out as
    ///     ``MixpanelEncodingError/timestampOutsideWindow``.
    ///
    /// The encoder logs a notice for each property of `plan` named as one Mixpanel reads for
    /// itself, as it will skip every record of that event
    /// (``MixpanelEncodingError/reservedPropertyName(event:property:)``).
    public init(projectToken: String, plan: TrackingPlan, limit: BatchLimit = MixpanelBatchEncoder.batchLimit, now: @escaping @Sendable () -> Date = { Date.now }) {
        self.projectToken = projectToken
        reader = PropertyReader(plan: plan)
        self.limit = limit
        self.now = now
        // Logged once here, where the plan is set up, as every record of such an event will be
        // skipped: setup still succeeds, since the plan may hold events the app never sends here.
        for schema in plan.schemas {
            for property in schema.properties where property.name.isReservedByMixpanel {
                Self.logger.notice("Mixpanel reserves the name of property \(property.name) of event \(schema.name), version \(schema.version): every record of it will be skipped")
            }
        }
    }

    /// `batch` as the requests Mixpanel takes, each within the encoder's limit and with a deadline
    /// 119 hours after its oldest record was tracked, with the records left out of them.
    ///
    /// - Parameter batch: Records of tracked events, oldest first.
    /// - Returns: The requests, in order, none when no record can be written, and each record left
    ///   out, with why (``MixpanelEncodingError``): one it can't encode, one past Mixpanel's
    ///   limits on properties, array elements or nesting or its window of time, and one whose
    ///   event is over the limit's bytes for one event, or for a request of it alone
    ///   (``MixpanelEncodingError/oversized(byteCount:)``).
    /// - Complexity: O(*n* log *n*) in the batch's size, for sorting each object's members.
    public func requests(for batch: [EventRecord]) -> BatchRequests<MixpanelEncodingError> {
        let encodedAt = now()
        let encoding = { (record: EventRecord) throws(MixpanelEncodingError) -> JSON in
            try json(of: record, encodedAt: encodedAt)
        }
        let oversized = { (byteCount: Int) -> MixpanelEncodingError in
            .oversized(byteCount: byteCount)
        }
        do {
            // Each request's deadline is its oldest record's 119 hours, as Mixpanel checks an
            // event's age when the request arrives, and a retry only ever arrives later. A record
            // is reported once: one left out here is in no request, and a request past its
            // deadline is never sent, so no `{"status": 0}` answer can report its records again.
            return try limit.requests(for: batch, in: .array, maximumAge: Self.window, encoding: encoding, oversized: oversized)
        } catch {
            // Never reached: the window is a positive constant, and only a negative age throws.
            // Requests without a deadline rather than a trap (D10).
            return limit.requests(for: batch, in: .array, encoding: encoding, oversized: oversized)
        }
    }

    private func json(of record: EventRecord, encodedAt: Date) throws(MixpanelEncodingError) -> JSON {
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
        let offset = record.timestamp.timeIntervalSince(encodedAt)
        // Before the window, so a record before 1971 is reported as unrepresentable under any
        // clock: no clock makes it a `time` Mixpanel takes.
        guard time >= Self.earliestTime else {
            throw .unrepresentableTimestamp
        }
        // Measured from when the batch is encoded: Mixpanel answers 200 for a request whose event
        // it drops for its time, so a record outside the window would be acknowledged and deleted
        // without being stored. The future side has no deadline: a retry only ever arrives later,
        // when the record is less far ahead. The timestamp is finite here, so the offset is NaN or
        // infinite only for a `now` that is, and every record is then reported (D10): both
        // comparisons are false for NaN, and each infinity falls outside one bound. Rejected:
        // leaving such a clock to Mixpanel, which would drop the records it refuses without a
        // report.
        guard offset >= -Self.windowSeconds, offset <= Self.latestOffset else {
            throw .timestampOutsideWindow
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

/// Mixpanel's answer to a track request sent with `verbose=1`.
private struct VerboseAnswer: Decodable {
    /// 1 when one event or more of the request was valid, 0 when none was.
    let status: Int
    /// Why none was, when `status` is 0.
    let error: String?
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
