public import Events
import Foundation
public import HTTPDestinations
import JSONValues
public import PropertyJSON
public import TrackingPlans

/// The ``/HTTPDestinations/BatchEncoder`` of Amplitude's HTTP V2 API, so an `HTTPDestination` can
/// send events to an Amplitude project's `POST /2/httpapi`.
///
/// Make the destination with ``HTTPDestinations/HTTPDestination/amplitude(apiKey:region:plan:backoff:clock:)``,
/// which fills in the endpoint, this encoder and Amplitude's limits:
///
/// ```swift
/// let amplitude = try HTTPDestination.amplitude(
///     apiKey: apiKey,
///     region: .eu,  // or .us, where the project's data resides
///     plan: plan)
/// ```
///
/// The body is a JSON object of content type `application/json` with two members: `api_key`, the
/// project's API key, and `events`, one object per record, oldest first, with these members:
///
/// | Member | Holds |
/// |---|---|
/// | `device_id` | The record's session, its `SessionKey`, as a lowercase UUID string; the record's own `EventRecord/id` when its context has no session |
/// | `event_properties` | The event's stored properties, by name |
/// | `event_type` | The event's `Event/name`, as it is |
/// | `insert_id` | The record's `EventRecord/id`, as a lowercase UUID string; a redelivered record keeps it |
/// | `session_id` | The session's start in Unix milliseconds, the first 48 bits of its version 7 `SessionKey`; left out for a record with no session, or a session key of another version |
/// | `time` | When the event was tracked, in whole milliseconds since 1970 |
///
/// The session is the only identifier sent: there is no `user_id`, and no `ip`, `idfv` or other
/// device identifier. Amplitude counts a user per `device_id`, so its unique users are sessions. A
/// record with no session (one tracked by a tracker without `Enricher.sessions()`, or one a store
/// recovered after a relaunch, which keeps no context) is its own anonymous user, linked to
/// nothing: Amplitude rejects an event with neither a `device_id` nor a `user_id`. Amplitude drops
/// a second copy of an event with the same `insert_id` and `device_id`, so a recovered record that
/// Amplitude had already stored under its session, before the app ended, is stored again. The
/// record's vendor identifier and trace context, and any other context value, aren't sent. Nor is
/// an `ip`: neither an address nor `$remote`, which asks Amplitude to look the user's location up
/// from the request's address.
///
/// Properties are read through the event's schema in `plan`, as `PropertyReader` reads them. A
/// ``/Events/Sensitive`` value is never sent, whatever the record reveals: the property is left
/// out, an element of an array is `null`, and one inside a type the plan can't map is `null`.
/// Amplitude limits each string value to 1,024 characters; the encoder sends longer ones as they
/// are.
///
/// Each event also holds these members, for each of the keys the record's context has a value
/// for:
///
/// | Member | Key | Holds |
/// |---|---|---|
/// | `app_version` | `ApplicationKey` | The version, left out when `nil` |
/// | `device_model` | `DeviceKey` | The model |
/// | `language` | `LocaleKey` | The locale's BCP 47 identifier, such as `en-US`, which Amplitude stores as the language's name |
/// | `platform`, `os_name`, `os_version` | `OperatingSystemKey` | The operating system's name, its name again, and its version |
///
/// A record the encoder can't write is left out of the request, and the batch's other records are
/// sent: one whose event and version `plan` doesn't describe, one whose event name Amplitude keeps
/// for its own events, one whose event isn't `Encodable`, one that holds a value JSON can't, one
/// whose timestamp has no epoch-milliseconds form, and one too large for a request
/// (``AmplitudeEncodingError``). ``requests(for:)`` returns them as `SkippedRecord`s, which
/// `HTTPDestination` logs and reports on its `dropReports`.
///
/// ``requests(for:)`` splits a batch into requests within the encoder's limit, ``batchLimit`` by
/// default, and makes none for a batch with no record it can write, so `HTTPDestination` sends
/// nothing for it. Amplitude answers a request it takes with 200, so `HTTPDestination` retries
/// one that gets no response, a 5xx, 408 or 429, and drops one it rejects, such as with 400 or
/// 413. A record sent again keeps its `insert_id`. The bytes are the same for the same records on
/// every run and platform: no whitespace, object members in the order of their names' UTF-8
/// bytes.
public struct AmplitudeBatchEncoder: BatchEncoder {
    /// No status beyond the 408, 429 and 5xx that `HTTPDestination` retries for every encoder.
    public static let transientStatuses: Set<TransientStatus> = []

    // From Amplitude's HTTP V2 reference, https://amplitude.com/docs/apis/analytics/http-v2, read
    // on 2026-11-26: "Upload limit" (2,000 events a request, a body under 1 MB, 10 events a
    // request on the Free plan), "Device IDs and User IDs minimum length" (5 characters, which a
    // UUID's 36 meet), "Event array keys" (the reserved event names, `session_id`, `ip`) and
    // "Response" (400 invalid, 413 too large, 429 and 5xx to retry).
    /// Amplitude's limits on one request: 10 events and 1,000,000 bytes of body, an event's
    /// included.
    ///
    /// Amplitude takes up to 2,000 events in one request, but asks a project on its Free plan to
    /// send no more than 10, so a request of 10 reaches a project on any plan. It asks every
    /// request's body to stay under 1 MB, and answers a larger one with 413. It documents no limit
    /// on one event beyond what a request holds.
    public static let batchLimit = (try? BatchLimit(maximumRecordCount: 10, maximumByteCount: 1_000_000, maximumRecordByteCount: 1_000_000)) ?? .unlimited

    private let envelope: JSONEnvelope
    private let reader: PropertyReader
    private let limit: BatchLimit

    /// Why a record was left out of the batch's requests.
    public typealias Failure = AmplitudeEncodingError

    /// An encoder of the events `plan` describes, for the Amplitude project of `apiKey`, splitting
    /// each batch to `limit`.
    ///
    /// - Parameters:
    ///   - apiKey: The project's API key, from the project's settings: public, as every Amplitude
    ///     client sends it, but the adopter's configuration. Never the project's secret key.
    ///   - plan: The tracking plan of every event the encoder is given: each record's event is
    ///     read through the schema of its name and `Event/schemaVersion` here.
    ///   - limit: The most each request holds; ``batchLimit``, Amplitude's, by default.
    public init(apiKey: String, plan: TrackingPlan, limit: BatchLimit = AmplitudeBatchEncoder.batchLimit) {
        envelope = JSONEnvelope(["api_key": .string(apiKey)], arrayMember: "events")
        reader = PropertyReader(plan: plan)
        self.limit = limit
    }

    /// `batch` as the requests Amplitude takes, each within the encoder's limit, with the records
    /// left out of them.
    ///
    /// - Parameter batch: Records of tracked events, oldest first.
    /// - Returns: The requests, in order, none when no record can be written, and each record left
    ///   out, with why (``AmplitudeEncodingError``): one it can't encode, and one whose event is
    ///   over the limit's bytes for one event, or for a request of it alone
    ///   (``AmplitudeEncodingError/oversized(byteCount:)``).
    /// - Complexity: O(*n* log *n*) in the batch's size, for sorting each object's members.
    public func requests(for batch: [EventRecord]) -> BatchRequests<AmplitudeEncodingError> {
        limit.requests(for: batch, in: envelope) { record throws(AmplitudeEncodingError) in
            try json(of: record)
        } oversized: { byteCount in
            .oversized(byteCount: byteCount)
        }
    }

    private func json(of record: EventRecord) throws(AmplitudeEncodingError) -> JSON {
        let properties: [String: JSON]
        do {
            // Never a Sensitive value: Amplitude is a vendor's store, whatever the record reveals.
            properties = try reader.properties(of: record, includingSensitiveValues: false)
        } catch {
            // A reserved name is reported before the reader's other reasons, but after an event
            // the plan doesn't describe.
            if case .unknownEvent = error {} else if record.name.isReservedByAmplitude {
                throw .reservedEventName(name: record.name)
            }
            throw AmplitudeEncodingError(error)
        }
        guard !record.name.isReservedByAmplitude else {
            throw .reservedEventName(name: record.name)
        }
        let time: Int64
        do {
            time = try record.timestamp.millisecondsSince1970()
        } catch {
            throw .unrepresentableTimestamp
        }
        var event = record.amplitudeContext
        // D4: the session is the only identifier sent. A record without one (a recovered record
        // keeps no context) becomes its own anonymous user rather than being skipped, which would
        // let the delivery acknowledge it and the store delete it, or sent without a `device_id`,
        // which Amplitude rejects.
        let identity = record.pseudonymousIdentity
        if case .session(let session) = identity, let start = session.version7Milliseconds {
            event["session_id"] = .integer(start)
        }
        event["device_id"] = .string(identity.uuid.uuidString.lowercased())
        event["event_type"] = .string(record.name)
        event["event_properties"] = .object(properties)
        event["insert_id"] = .string(record.deduplicationID)
        event["time"] = .integer(time)
        return .object(event)
    }
}

extension AmplitudeEncodingError {
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
    /// Whether Amplitude keeps this event name for its own events: its session and revenue events
    /// (`[Amplitude] Start Session`, `[Amplitude] Revenue`), and the identify calls, which it
    /// reads as changes to a user's or group's properties.
    fileprivate var isReservedByAmplitude: Bool {
        hasPrefix("[Amplitude]") || self == "$identify" || self == "$groupidentify"
    }
}

extension UUID {
    /// The first 48 bits of a version 7 UUID, its time in Unix milliseconds, as Amplitude's
    /// `session_id`; `nil` for a UUID of any other version or variant, whose first bits are no
    /// time.
    fileprivate var version7Milliseconds: Int64? {
        let bytes = uuid
        // RFC 9562: the version is the high nibble of byte 6, and the variant the top two bits of
        // byte 8, `10`.
        guard bytes.6 >> 4 == 7, bytes.8 >> 6 == 0b10 else { return nil }
        var milliseconds: Int64 = 0
        for byte in [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5] {
            milliseconds = milliseconds << 8 | Int64(byte)
        }
        return milliseconds
    }
}
