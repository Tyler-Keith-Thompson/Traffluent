public import Events
import Foundation
public import HTTPDestinations
import JSONValues
import Logging
public import PropertyJSON
public import TrackingPlans

/// The ``/HTTPDestinations/BatchEncoder`` of the Segment spec's batch call, so an `HTTPDestination`
/// can send events to Segment, RudderStack, Customer.io Data Pipelines, or another endpoint that
/// takes Segment's `POST /v1/batch`.
///
/// Make the destination with one of the factories, which fill in the endpoint, the credentials'
/// header field, this encoder and its limits:
/// ``HTTPDestinations/HTTPDestination/segment(writeKey:region:plan:backoff:clock:)``,
/// ``HTTPDestinations/HTTPDestination/rudderStack(writeKey:dataPlane:plan:backoff:clock:)`` and
/// ``HTTPDestinations/HTTPDestination/customerIO(apiKey:region:plan:backoff:clock:)``:
///
/// ```swift
/// let segment = try HTTPDestination.segment(
///     writeKey: writeKey,
///     region: .us,  // or .eu, where the workspace is
///     plan: plan)
/// ```
///
/// The body is a JSON object of content type `application/json` with one member, `batch`, an array
/// of track calls, one per record, oldest first, with these members:
///
/// | Member | Holds |
/// |---|---|
/// | `anonymousId` | The record's session, its `SessionKey`, as a lowercase UUID string; the record's own `EventRecord/id` when its context has no session |
/// | `context` | The standard context, in the spec's field names (below), and `ip` as `"0.0.0.0"` |
/// | `event` | The event's `Event/name`, as it is |
/// | `messageId` | The record's `EventRecord/id`, as a lowercase UUID string; a redelivered record keeps it |
/// | `properties` | The event's stored properties, by name |
/// | `request_ip` | `"0.0.0.0"`, in RudderStack's calls alone |
/// | `timestamp` | When the event was tracked, in ISO 8601 with milliseconds, in UTC |
/// | `type` | `"track"` |
///
/// The session is the only identifier sent: there is no `userId`, no `identify` call, no traits,
/// and no `context.device.id` or `advertisingId`. An endpoint counts a user per `anonymousId`, so
/// its anonymous users are sessions. A record with no session (one tracked by a tracker without
/// `Enricher.sessions()`, or one a store recovered after a relaunch, which keeps no context) is its
/// own anonymous user, linked to nothing: the spec rejects a call with neither a `userId` nor an
/// `anonymousId`. Segment deduplicates calls by `messageId` over about the last 24 hours, and
/// drops most duplicates rather than all, so a recovered record Segment had already stored before
/// the app ended is most likely not stored again, whatever its `anonymousId`. RudderStack's and
/// Customer.io's references don't say whether they deduplicate. The record's vendor identifier
/// and trace context, and any other context value, aren't sent.
///
/// `context.ip` is `"0.0.0.0"` in every call, which the spec reads as the user's address, so
/// Segment records no address from the request. RudderStack fills in a `request_ip` member from
/// the request unless the call has one, even when `context.ip` is set, and passes it on to its
/// destinations, so RudderStack's calls also carry `request_ip` as `"0.0.0.0"`. Customer.io's
/// references don't say whether `context.ip` takes the place of the address it reads from an HTTP
/// request. No call to Segment or Customer.io carries `request_ip`, which their specs don't have.
///
/// No `sentAt`, `originalTimestamp` or `channel` is sent. Without `sentAt` the endpoint takes
/// `timestamp` as it is, uncorrected for the device's clock; it is left out on purpose, as a
/// retried request sends the same body again, whose `sentAt` would be the first attempt's.
/// RudderStack, whose references list all three as required, fills them in from when it received
/// the call.
///
/// Properties are read through the event's schema in `plan`, as `PropertyReader` reads them. A
/// ``/Events/Sensitive`` value is never sent, whatever the record reveals: the property is left
/// out, an element of an array is `null`, and one inside a type the plan can't map is `null`.
///
/// `context` holds these members, for each of the keys the record's context has a value for:
///
/// | Member | Key | Holds |
/// |---|---|---|
/// | `app` | `ApplicationKey` | `namespace`, the bundle identifier, `version` and `build`, each left out when `nil`; no `app` when all three are |
/// | `device` | `DeviceKey` | `model`, and `type`, the platform as Segment's Swift library names it: `ios` for a phone or pad, `macos`, `tvos`, `watchos` or `visionos` |
/// | `locale` | `LocaleKey` | The locale's BCP 47 identifier, such as `en-US` |
/// | `network` | `NetworkKey` | `wifi` and `cellular`, whether the connection is each |
/// | `os` | `OperatingSystemKey` | `name` and `version` |
///
/// A record the encoder can't write is left out of the request, and the batch's other records are
/// sent: one whose event and version `plan` doesn't describe, one whose event name is one of
/// Customer.io's semantic events, which delete or suppress people and devices, one whose event
/// isn't `Encodable`, one that holds a value JSON can't, one whose timestamp has no ISO 8601 form,
/// and one too large for a call (``SegmentSpecEncodingError``). ``requests(for:)`` returns them as
/// `SkippedRecord`s, which `HTTPDestination` logs and reports on its `dropReports`.
///
/// ``requests(for:)`` splits a batch into requests within the encoder's limit, ``batchLimit`` by
/// default, and makes none for a batch with no record it can write, so `HTTPDestination` sends
/// nothing for it. A record sent again keeps its `messageId`. The bytes are the same for the same
/// records on every run and platform: no whitespace, object members in the order of their names'
/// UTF-8 bytes.
public struct SegmentSpecBatchEncoder: BatchEncoder {
    // From the docs, read on 2026-11-27:
    // - Segment's HTTP Tracking API,
    //   https://segment.com/docs/connections/sources/catalog/libraries/server/http-api/ ("Batch":
    //   500 KB a request and 32 KB a call; "Errors": up to 2,500 events a batch, each "less than
    //   32 KB", 400 for a payload too large or invalid JSON and 200 for everything else, a batch of
    //   too many events included; "Rate limits": 429 with Retry-After; "Authentication": the write
    //   key as Basic auth's user name with an empty password; "Regional configuration").
    // - Segment's Spec, https://segment.com/docs/connections/spec/common/ (the fields and context,
    //   `messageId` at most 100 characters) and the Analytics.js identity guide,
    //   https://segment.com/docs/connections/sources/catalog/libraries/website/javascript/identity/
    //   ("Anonymizing IP": `context.ip` "0.0.0.0" keeps Segment from recording the request's).
    // - analytics-swift (github.com/segmentio/analytics-swift, main): `device.type` per platform,
    //   and a batch file of at most 475,000 bytes against the server's 500 KB.
    // - RudderStack's HTTP API, https://www.rudderstack.com/docs/api/http-api/ (4 MB a batch,
    //   32 KB a call, nesting up to 200 levels; 400, 401 for a bad write key, 404 for a disabled
    //   source, 413, 429, 500) and common fields,
    //   https://www.rudderstack.com/docs/event-spec/standard-events/common-fields/ (`context.ip`
    //   first for geolocation, but `request_ip` filled in from the request unless the call has
    //   one, "even if context.ip is already present", and passed on to destinations).
    // - Segment's duplicate data guide, https://segment.com/docs/guides/duplicate-data/ (99% of
    //   duplicates dropped, by `messageId`, within about 24 hours).
    // - Customer.io's Pipelines API, https://docs.customer.io/api/cdp/ (500 KB a batch, 32 KB a
    //   call; strict mode) and semantic events,
    //   https://docs.customer.io/integrations/data-in/semantic-events/cio-journeys/.
    // Segment's are the smallest, so one limit serves every endpoint.
    /// The Segment spec's limits on one request, which Segment, RudderStack and Customer.io all
    /// accept: 2,500 calls, 500,000 bytes of body, and 31,999 bytes of one call.
    ///
    /// Segment takes up to 2,500 calls in one batch, of 500 KB at most, each call under 32 KB.
    /// RudderStack takes a batch of up to 4 MB and Customer.io one of 500 KB, each call of 32 KB at
    /// most. Segment answers a batch of too many calls with 200 and drops it, and Customer.io drops
    /// a call over 32 KB, so the encoder keeps within the smallest of each.
    public static let batchLimit = (try? BatchLimit(maximumRecordCount: 2_500, maximumByteCount: 500_000, maximumRecordByteCount: 31_999)) ?? .unlimited

    /// The seconds from 1970 to 0001-01-01T00:00:00Z: an earlier timestamp has no four-digit
    /// ISO 8601 year.
    private static let earliestSeconds: Double = -62_135_596_800

    /// The seconds from 1970 to 10000-01-01T00:00:00Z: a timestamp from then on has no four-digit
    /// ISO 8601 year.
    private static let endSeconds: Double = 253_402_300_800

    private static let logger = Logger(label: "SegmentSpecEncoding.SegmentSpecBatchEncoder")

    private static let envelope = JSONEnvelope([:], arrayMember: "batch")

    private let reader: PropertyReader
    private let limit: BatchLimit
    private let sendsRequestIP: Bool

    /// Why a record was left out of the batch's requests.
    public typealias Failure = SegmentSpecEncodingError

    /// An encoder of the events `plan` describes, splitting each batch to `limit`.
    ///
    /// The encoder takes no key: every factory sends its credentials in a header field.
    ///
    /// - Parameters:
    ///   - plan: The tracking plan of every event the encoder is given: each record's event is
    ///     read through the schema of its name and `Event/schemaVersion` here.
    ///   - limit: The most each request holds; ``batchLimit``, the spec's, by default.
    ///
    /// The encoder logs a notice for each event of `plan` named as one of Customer.io's semantic
    /// events, as it will skip every record of it
    /// (``SegmentSpecEncodingError/reservedEventName(name:)``).
    public init(plan: TrackingPlan, limit: BatchLimit = SegmentSpecBatchEncoder.batchLimit) {
        self.init(plan: plan, limit: limit, sendsRequestIP: false)
    }

    /// An encoder of the events `plan` describes, splitting each batch to `limit`, that writes a
    /// top-level `request_ip` of `"0.0.0.0"` in each call when `sendsRequestIP` is true.
    ///
    /// Only the RudderStack factory sets it, as RudderStack fills in `request_ip` from the request
    /// unless the call has one. Customer.io's strict mode may refuse a member its spec doesn't
    /// have, so the other factories leave it off, and the option isn't public.
    package init(plan: TrackingPlan, limit: BatchLimit = SegmentSpecBatchEncoder.batchLimit, sendsRequestIP: Bool) {
        reader = PropertyReader(plan: plan)
        self.limit = limit
        self.sendsRequestIP = sendsRequestIP
        // Logged once here, where the plan is set up, as every record of such an event will be
        // skipped: setup still succeeds, since the plan may hold events the app never sends here.
        for schema in plan.schemas where schema.name.isSemanticEventName {
            Self.logger.notice("Event \(schema.name), version \(schema.version), is named as a Customer.io semantic event, which deletes or suppresses people or devices: every record of it will be skipped")
        }
    }

    /// `batch` as the batch calls the endpoint takes, each within the encoder's limit, with the
    /// records left out of them.
    ///
    /// - Parameter batch: Records of tracked events, oldest first.
    /// - Returns: The requests, in order, none when no record can be written, and each record left
    ///   out, with why (``SegmentSpecEncodingError``): one it can't encode, and one whose call is
    ///   over the limit's bytes for one call, or for a request of it alone
    ///   (``SegmentSpecEncodingError/oversized(byteCount:)``).
    /// - Complexity: O(*n* log *n*) in the batch's size, for sorting each object's members.
    public func requests(for batch: [EventRecord]) -> BatchRequests<SegmentSpecEncodingError> {
        limit.requests(for: batch, in: Self.envelope) { record throws(SegmentSpecEncodingError) in
            try json(of: record)
        } oversized: { byteCount in
            .oversized(byteCount: byteCount)
        }
    }

    private func json(of record: EventRecord) throws(SegmentSpecEncodingError) -> JSON {
        let properties: [String: JSON]
        do {
            // Never a Sensitive value: these endpoints are a vendor's store, whatever the record
            // reveals.
            properties = try reader.properties(of: record, includingSensitiveValues: false)
        } catch {
            // A reserved name is reported before the reader's other reasons, but after an event
            // the plan doesn't describe.
            if case .unknownEvent = error {} else if record.name.isSemanticEventName {
                throw .reservedEventName(name: record.name)
            }
            throw SegmentSpecEncodingError(error)
        }
        guard !record.name.isSemanticEventName else {
            throw .reservedEventName(name: record.name)
        }
        let seconds = record.timestamp.timeIntervalSince1970
        // A comparison that is false for NaN, so NaN and both infinities fall outside too.
        guard seconds >= Self.earliestSeconds, seconds < Self.endSeconds else {
            throw .unrepresentableTimestamp
        }
        let timestamp: String
        do {
            timestamp = try record.timestamp.iso8601Timestamp
        } catch {
            // Unreached: every four-digit year has a millisecond count in Int64. The catch keeps
            // the reason the guard gives, should the two ranges ever part.
            throw .unrepresentableTimestamp
        }
        var context = record.segmentSpecContext
        // The spec's reading of `context.ip` is the user's address, which Segment takes in place
        // of the request's, so it records none. `context.direct`, which asks Segment to record the
        // request's, is never sent. RudderStack reads `context.ip` first for geolocation, but still
        // fills in `request_ip` from the request unless the call has one, hence sendsRequestIP.
        context["ip"] = .string("0.0.0.0")
        // D4: the session is the only identifier sent. A record without one (a recovered record
        // keeps no context) becomes its own anonymous user rather than being skipped, which would
        // let the delivery acknowledge it and the store delete it, or sent without an
        // `anonymousId`, which the spec rejects.
        var call: [String: JSON] = [
            "anonymousId": .string(record.pseudonymousIdentity.uuid.uuidString.lowercased()),
            "context": .object(context),
            "event": .string(record.name),
            "messageId": .string(record.deduplicationID),
            "properties": .object(properties),
            "timestamp": .string(timestamp),
            "type": .string("track"),
        ]
        if sendsRequestIP {
            call["request_ip"] = .string("0.0.0.0")
        }
        return .object(call)
    }
}

extension SegmentSpecEncodingError {
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
    /// Whether the name is one of Customer.io's semantic events, track calls it reads as an action
    /// on the person or a device rather than as an event: deleting or suppressing the person,
    /// deleting a device, an object or a relationship, or reporting a message's delivery.
    ///
    /// Checked for every endpoint, as Segment and RudderStack can forward track calls to a
    /// Customer.io destination, which reads them the same way. Compared exactly, as Customer.io
    /// lists them.
    fileprivate var isSemanticEventName: Bool {
        Self.semanticEventNames.contains(self)
    }

    private static let semanticEventNames: Set<String> = [
        "Device Created or Updated", "Device Deleted", "Object Deleted", "Relationship Deleted",
        "Report Delivery Event", "User Deleted", "User Suppressed", "User Unsuppressed",
    ]
}
