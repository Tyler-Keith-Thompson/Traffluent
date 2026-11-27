public import Events
import Foundation
public import HTTPDestinations
import JSONValues
import Logging
public import PropertyJSON
public import TrackingPlans

/// The ``/HTTPDestinations/BatchEncoder`` of PostHog's batch capture API, so an `HTTPDestination`
/// can send events to PostHog Cloud or a self-hosted PostHog's `POST /batch/`.
///
/// Make the destination with ``HTTPDestinations/HTTPDestination/postHog(projectToken:host:plan:backoff:clock:)``,
/// which fills in the endpoint, this encoder and PostHog's limits:
///
/// ```swift
/// let postHog = try HTTPDestination.postHog(
///     projectToken: projectToken,
///     host: postHogHost,  // https://eu.i.posthog.com
///     plan: plan)
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
/// Properties are read through the event's schema in `plan`, as `PropertyReader` reads them. A
/// ``/Events/Sensitive`` value is never sent, whatever the record reveals: the property is left
/// out, an element of an array is `null`, and one inside a type the plan can't map is `null`. A
/// property whose name starts with `$`, which only a hand-written `Encodable` conformance can
/// write, or is `distinct_id`, is left out and logged at notice level, as PostHog reads those
/// names as settings (`$set`, `$process_person_profile`) or the identity.
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
/// A record the encoder can't write is left out of the request, and the batch's other records are
/// sent: one whose event and version `plan` doesn't describe, one whose event name starts with `$`
/// (a name PostHog keeps for its own events), one whose event isn't `Encodable`, one that holds a
/// value JSON can't, one whose timestamp has no ISO 8601 form, and one too large for PostHog to
/// store (``PostHogEncodingError``).
/// ``requests(for:)`` returns them as `SkippedRecord`s, which `HTTPDestination` logs and reports
/// on its `dropReports`.
///
/// ``requests(for:)`` splits a batch into requests within the encoder's limit, ``batchLimit`` by
/// default, and makes none for a batch with no record it can write, so `HTTPDestination` sends
/// nothing for it. PostHog answers a batch it takes with
/// 200, so `HTTPDestination` retries one that gets no response, a 5xx, 408 or 429, and drops one
/// it rejects. A record sent again keeps its `uuid`. The bytes are the same for the same records
/// on every run and platform: no whitespace, object members in the order of their names' UTF-8
/// bytes.
public struct PostHogBatchEncoder: BatchEncoder {
    /// PostHog's limits on one request: 10,000,000 bytes of body and 1,000,000 bytes of one event,
    /// with no limit on the count of events.
    ///
    /// PostHog Cloud's legacy batch endpoint takes up to 20 MB, and a self-hosted instance at
    /// least 10 MB, so a request of 10 MB reaches either; PostHog stores an event of about 1 MB at
    /// most and drops a larger one.
    public static let batchLimit = (try? BatchLimit(maximumRecordCount: .max, maximumByteCount: 10_000_000, maximumRecordByteCount: 1_000_000)) ?? .unlimited

    private let envelope: JSONEnvelope
    private let reader: PropertyReader
    private let limit: BatchLimit

    /// Why a record was left out of the batch's requests.
    public typealias Failure = PostHogEncodingError

    private static let logger = Logger(label: "PostHogEncoding.PostHogBatchEncoder")

    /// An encoder of the events `plan` describes, for the PostHog project of `projectToken`,
    /// splitting each batch to `limit`.
    ///
    /// - Parameters:
    ///   - projectToken: The project's token (`phc_...`), from the project's settings: public, as
    ///     every PostHog client sends it, but the adopter's configuration.
    ///   - plan: The tracking plan of every event the encoder is given: each record's event is
    ///     read through the schema of its name and `Event/schemaVersion` here.
    ///   - limit: The most each request holds; ``batchLimit``, PostHog's, by default.
    public init(projectToken: String, plan: TrackingPlan, limit: BatchLimit = PostHogBatchEncoder.batchLimit) {
        envelope = JSONEnvelope(["api_key": .string(projectToken)], arrayMember: "batch")
        reader = PropertyReader(plan: plan)
        self.limit = limit
    }

    /// `batch` as the requests PostHog takes, each within the encoder's limit, with the records
    /// left out of them.
    ///
    /// - Parameter batch: Records of tracked events, oldest first.
    /// - Returns: The requests, in order, none when no record can be written, and each record left
    ///   out, with why (``PostHogEncodingError``): one it can't encode, and one whose event is over
    ///   the limit's bytes for one event, or for a request of it alone
    ///   (``PostHogEncodingError/oversized(byteCount:)``).
    /// - Complexity: O(*n* log *n*) in the batch's size, for sorting each object's members.
    public func requests(for batch: [EventRecord]) -> BatchRequests<PostHogEncodingError> {
        limit.requests(for: batch, in: envelope) { record throws(PostHogEncodingError) in
            try json(of: record)
        } oversized: { byteCount in
            .oversized(byteCount: byteCount)
        }
    }

    private func json(of record: EventRecord) throws(PostHogEncodingError) -> JSON {
        var properties: [String: JSON]
        do {
            // Never a Sensitive value: PostHog is a vendor's store, whatever the record reveals.
            properties = try reader.properties(of: record, includingSensitiveValues: false)
        } catch {
            // A reserved name is reported before the reader's other reasons, but after an event
            // the plan doesn't describe.
            if case .unknownEvent = error {} else if record.name.hasPrefix("$") {
                throw .reservedEventName(name: record.name)
            }
            throw PostHogEncodingError(error)
        }
        guard !record.name.hasPrefix("$") else {
            throw .reservedEventName(name: record.name)
        }
        let timestamp: String
        do {
            timestamp = try record.timestamp.iso8601Timestamp
        } catch {
            throw .unrepresentableTimestamp
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
        // D4: the session is the only identifier sent. A record without one (a recovered record
        // keeps no context) becomes its own anonymous person rather than being skipped, which
        // would let the delivery acknowledge it and the store delete it, or sent without a
        // `distinct_id`, which makes PostHog reject the whole batch.
        let identity = record.pseudonymousIdentity
        // Written after the event's and context's properties, so neither can replace it.
        if case .session(let session) = identity {
            properties["$session_id"] = .string(session.uuidString.lowercased())
        }
        properties["$process_person_profile"] = .boolean(false)
        properties["$geoip_disable"] = .boolean(true)
        return .object([
            "distinct_id": .string(identity.uuid.uuidString.lowercased()),
            "event": .string(record.name),
            "properties": .object(properties),
            "timestamp": .string(timestamp),
            "uuid": .string(record.deduplicationID),
        ])
    }
}

extension PostHogEncodingError {
    /// The reason the property reader gave, as this encoder's.
    fileprivate init(_ error: PropertyReadingError) {
        switch error {
        case .unknownEvent(let name, let version): self = .unknownEvent(name: name, version: version)
        case .notEncodable(let name): self = .notEncodable(name: name)
        case .unrepresentableValue(let event, let property): self = .unrepresentableValue(event: event, property: property)
        }
    }
}
