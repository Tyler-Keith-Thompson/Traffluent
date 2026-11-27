public import Events
import Foundation
public import HTTPDestinations
import JSONValues
import Logging
public import PropertyJSON
public import TrackingPlans

/// The ``/HTTPDestinations/BatchEncoder`` of Heap's server-side bulk track API, so an
/// `HTTPDestination` can send events to a Heap environment's `POST /api/track`.
///
/// Make the destination with ``HTTPDestinations/HTTPDestination/heap(appID:region:plan:backoff:clock:)``,
/// which fills in the endpoint, this encoder and its limits:
///
/// ```swift
/// let heap = try HTTPDestination.heap(
///     appID: appID,  // the environment's ID, from Heap's project settings
///     region: .us,  // or .eu, where the project's data resides
///     plan: plan)
/// ```
///
/// The body is a JSON object of content type `application/json` with two members: `app_id`, the
/// app ID the encoder is made with, without leading or trailing whitespace, and `events`, an array
/// of one track event per record, oldest first. Each event is an object of these members:
///
/// | Member | Holds |
/// |---|---|
/// | `event` | The event's `Event/name`, as it is |
/// | `identity` | The record's session, its `SessionKey`, as a lowercase UUID string; the record's own `EventRecord/id` the same way when its context has no session |
/// | `idempotency_key` | The record's `EventRecord/id`, as a lowercase UUID string; a redelivered record keeps it |
/// | `properties` | The event's stored properties, flattened; left out when there are none |
/// | `timestamp` | When the event was tracked, in ISO 8601, in UTC with milliseconds |
///
/// The session is the only identifier sent: there is no `user_id`, which is Heap's own ID of a
/// user, and no `session_id`. Heap makes a user for each identity it hasn't seen, so its users are
/// sessions. A record with no session (one tracked by a tracker without `Enricher.sessions()`, or
/// one a store recovered after a relaunch, which keeps no context) is its own user of one event,
/// linked to nothing: Heap takes no event without an identity. The record's vendor identifier,
/// trace context and standard context, and any other context value, aren't sent: Heap keeps no
/// built-in property of a server-side event, so they would sit among the event's own properties,
/// under names of the encoder's choosing.
///
/// Properties are read through the event's schema in `plan`, as `PropertyReader` reads them. A
/// ``/Events/Sensitive`` value is never sent, whatever the record reveals: the property is left
/// out, and so is an element of an array. Heap takes a number or a string as a property's value,
/// so an object or array is spread into a property per value it holds, named after its path,
/// joined by `.` (`cart.size`, `tags.0`), a boolean is sent as the string `true` or `false`, and a
/// `null` is left out.
///
/// A record the encoder can't write is left out of the request, and the batch's other records are
/// sent: one whose event and version `plan` doesn't describe, one whose event name is over 1,024
/// characters, one with a property Heap reserves or a property name or string value of
/// 1,024 characters or more, one whose values flatten to one name, one whose event isn't
/// `Encodable`, one that holds a value JSON can't, one whose timestamp is outside the years 1 to
/// 9999, and one too large for a request (``HeapEncodingError``). ``requests(for:)`` returns them
/// as `SkippedRecord`s, which `HTTPDestination` logs and reports on its `dropReports`.
///
/// ``requests(for:)`` splits a batch into requests within the encoder's limit, ``batchLimit`` by
/// default, and makes none for a batch with no record it can write, so `HTTPDestination` sends
/// nothing for it. Heap answers a request it takes with 200 and one it can't with 400, which
/// `HTTPDestination` drops and reports with every record of the request. Heap stores an event
/// once per `idempotency_key` within one identity, so a record sent again under the same session
/// is stored once. A record a store recovers after a relaunch keeps no context, so it is sent
/// under its own identifier, not its session's, and Heap may store it twice. The bytes are the same for
/// the same records on every run and platform: no whitespace, object members in the order of their
/// names' UTF-8 bytes.
public struct HeapBatchEncoder: BatchEncoder {
    // From Heap's developer docs, read on 2026-11-27:
    // - Track, https://developers.heap.io/reference/track-1 (POST https://heapanalytics.com/api/track,
    //   or https://c.eu.heap-api.com/api/track for the EU data center; its OpenAPI definition's
    //   `security: [{}]`, so no credential; app_id and event required; identity "Case-sensitive
    //   string, limited to 255 characters"; event "Limited to 1024 characters"; properties "a
    //   number or string with fewer than 1024 characters"; user_id, session_id and screen_name
    //   reserved as keys; timestamp ISO 8601, the current time when left out; idempotency_key
    //   "Subsequent calls with the same idempotency key will not update data"; 200 and 400, each
    //   `{}`; 30 requests per 30 seconds per identity per app_id).
    // - Bulk Track, https://developers.heap.io/reference/bulk-track (the same endpoint, an
    //   `events` array beside app_id, "a max of 1000 events per request"; 1000 events a minute per
    //   identity per app_id and 15,000 a minute per app_id).
    // - Server-side APIs Overview, https://developers.heap.io/reference/server-side-apis-overview
    //   (the server-side APIs complement Heap's SDKs, and "you can only send events to identified
    //   users"), and User Deletion, https://developers.heap.io/reference/user-deletion: only
    //   deletion "requires an auth token", from the app_id and an api_key.
    // From Heap's help center, the same day: a user with only server-side events shows "events
    // are hidden", and the events sit in the Hidden Events category
    // (https://help.heap.io/hc/en-us/articles/37271959816465); server-side events aren't
    // sessionized, so they never appear in the Sessions list
    // (https://help.heap.io/hc/en-us/articles/37271954812049); and a session filter on a user
    // property sees only SDK sessions (https://help.heap.io/hc/en-us/articles/37271885557265).
    // Every user this encoder makes has only server-side events, which is why the docs lead with
    // it. The standard context still isn't sent as properties: Heap has no built-in keys for a
    // server-side event, so app and device fields would sit among each event's own properties
    // and collide with an app's names.
    // Contentsquare, which owns Heap, documents no other server-side track API
    // (https://docs.contentsquare.com/llms.txt, the same day); its data model says "Server-side
    // events exist outside the context of a session, and only have the properties that you send"
    // (https://docs.contentsquare.com/en/connect/data-model/).
    /// Heap's limits on one request: 1,000 events and 1,000,000 bytes of body, and 1,000,000 bytes
    /// of one event.
    ///
    /// Heap's bulk track API takes up to 1,000 events in a request. It documents no limit on a
    /// request's size; the 1,000,000 bytes are the encoder's own bound, which keeps a request to a
    /// size a retry can send again. An event's values are each under 1,024 characters, so only an
    /// event of many properties comes near it.
    public static let batchLimit = (try? BatchLimit(maximumRecordCount: 1_000, maximumByteCount: 1_000_000, maximumRecordByteCount: 1_000_000)) ?? .unlimited

    /// The seconds from 1970 to 0001-01-01T00:00:00Z: an earlier timestamp has no four-digit ISO
    /// 8601 year.
    private static let earliestSeconds: Double = -62_135_596_800

    /// The seconds from 1970 to 10000-01-01T00:00:00Z: a timestamp from then on has no four-digit
    /// ISO 8601 year.
    private static let endSeconds: Double = 253_402_300_800

    private static let logger = Logger(label: "HeapEncoding.HeapBatchEncoder")

    private let reader: PropertyReader
    private let limit: BatchLimit
    private let envelope: JSONEnvelope

    /// Why a record was left out of the batch's requests.
    public typealias Failure = HeapEncodingError

    /// An encoder of the events `plan` describes, for the Heap environment `appID`, splitting each
    /// batch to `limit`.
    ///
    /// - Parameters:
    ///   - appID: The environment's ID, from Heap's project settings: public, as Heap's client SDKs
    ///     ship it in every app. Whitespace and newlines around it are trimmed off.
    ///   - plan: The tracking plan of every event the encoder is given: each record's event is
    ///     read through the schema of its name and `Event/schemaVersion` here.
    ///   - limit: The most each request holds; ``batchLimit`` by default.
    /// - Throws: ``HeapSetupError/emptyAppID`` for an app ID that is empty or only whitespace, and
    ///   ``HeapSetupError/malformedAppID`` for one holding a character other than an ASCII digit.
    ///
    /// The encoder logs a notice for each event and property of `plan` named as Heap refuses, or
    /// reserves, as it will skip records of that event (``HeapEncodingError``).
    public init(appID: String, plan: TrackingPlan, limit: BatchLimit = HeapBatchEncoder.batchLimit) throws(HeapSetupError) {
        // Trimmed, as an ID pasted from a configuration file often ends in a newline.
        let appID = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appID.isEmpty else { throw .emptyAppID }
        // A Heap environment's ID is a number (the API reference's examples are "11" and
        // "12343283"), sent as a string. Checking the digits refuses an API key or a URL pasted
        // in its place; a length isn't documented, so none is checked.
        guard appID.utf8.allSatisfy({ (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains($0) }) else {
            throw .malformedAppID
        }
        reader = PropertyReader(plan: plan)
        self.limit = limit
        envelope = JSONEnvelope(["app_id": .string(appID)], arrayMember: "events")
        // Logged once here, where the plan is set up, as records of such an event will be
        // skipped: setup still succeeds, since the plan may hold events the app never sends here.
        for schema in plan.schemas {
            if !schema.name.isHeapEventName {
                Self.logger.notice("Heap refuses the name of event \(schema.name), version \(schema.version): every record of it will be skipped")
            }
            for property in schema.properties where property.name.isReservedByHeap || !property.name.fitsHeapProperty {
                Self.logger.notice("Heap refuses or reserves the name of property \(property.name) of event \(schema.name), version \(schema.version): its records will be skipped")
            }
        }
    }

    /// `batch` as the requests Heap takes, each within the encoder's limit, with the records left
    /// out of them.
    ///
    /// - Parameter batch: Records of tracked events, oldest first.
    /// - Returns: The requests, in order, none when no record can be written, and each record left
    ///   out, with why (``HeapEncodingError``): one it can't encode, one past Heap's rules, and one
    ///   too large for a request of it alone (``HeapEncodingError/oversized(byteCount:)``).
    /// - Complexity: O(*n* log *n*) in the batch's size, for sorting each object's members.
    public func requests(for batch: [EventRecord]) -> BatchRequests<HeapEncodingError> {
        // No deadline: Heap documents no window of timestamps it takes, only that a missing
        // timestamp "defaults to the current time", and the encoder always sends one.
        limit.requests(for: batch, in: envelope) { record throws(HeapEncodingError) in
            try json(of: record)
        } oversized: { byteCount in
            .oversized(byteCount: byteCount)
        }
    }

    private func json(of record: EventRecord) throws(HeapEncodingError) -> JSON {
        let read: [String: JSON]
        do {
            // Never a Sensitive value: Heap is a vendor's store, whatever the record reveals.
            read = try reader.properties(of: record, includingSensitiveValues: false)
        } catch {
            // The event's name is reported before the reader's other reasons, but after an event
            // the plan doesn't describe.
            if case .unknownEvent = error {} else {
                try record.checkHeapName()
            }
            throw HeapEncodingError(error)
        }
        try record.checkHeapName()
        let properties: [String: JSON]
        do {
            // Heap takes only numbers and strings as values. `.`, as the sibling encoders join a
            // path. Rejected: sending an array for Heap to join with `||`, as it does on
            // ingestion, since it cuts the joined string at 1,024 characters without saying so,
            // and an array of objects has no such form.
            properties = try read.flattened(separator: ".").compactMapValues(\.heapValue)
        } catch {
            throw .propertyNameCollision(event: record.name, property: error.key)
        }
        // In order, so of two names that break a rule, the error always names the same one.
        let names = properties.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        if let reserved = names.first(where: \.isReservedByHeap) {
            throw .reservedPropertyName(event: record.name, property: reserved)
        }
        if let long = names.first(where: { !$0.fitsHeapProperty }) {
            throw .propertyNameTooLong(event: record.name, property: long)
        }
        for name in names {
            if case .string(let value) = properties[name], !value.fitsHeapProperty {
                throw .propertyValueTooLong(event: record.name, property: name, length: value.utf16.count)
            }
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
        // D4: the session is the only identifier sent, as `identity`, which Heap makes a user of.
        // A record without one (a recovered record keeps no context) becomes its own user rather
        // than being skipped, which would let the delivery acknowledge it and the store delete it,
        // or sent without an identity, which Heap requires. Rejected: `user_id`, which must be a
        // Heap SDK's numeric user ID, and `session_id`, a session ID of Heap's SDKs, which Heap's
        // help center says a server-side event can't be linked to a client-side session by.
        var event: [String: JSON] = [
            "event": .string(record.name),
            "identity": .string(record.pseudonymousIdentity.uuid.uuidString.lowercased()),
            // Heap stores one event per key, so a record sent again, after a lost answer or a
            // store's redelivery, is stored once.
            "idempotency_key": .string(record.deduplicationID),
            // The record's own time, so a record a store kept offline for days keeps its day;
            // Heap would date an event sent without one when it arrives.
            "timestamp": .string(timestamp),
        ]
        if !properties.isEmpty {
            event["properties"] = .object(properties)
        }
        return .object(event)
    }
}

extension HeapEncodingError {
    /// The reason the property reader gave, as this encoder's.
    fileprivate init(_ error: PropertyReadingError) {
        switch error {
        case .unknownEvent(let name, let version): self = .unknownEvent(name: name, version: version)
        case .notEncodable(let name): self = .notEncodable(name: name)
        case .unrepresentableValue(let event, let property): self = .unrepresentableValue(event: event, property: property)
        }
    }
}

extension EventRecord {
    /// Throws when Heap refuses the event's name, over 1,024 characters.
    fileprivate func checkHeapName() throws(HeapEncodingError) {
        guard name.isHeapEventName else {
            throw .invalidEventName(name: name)
        }
    }
}

extension JSON {
    /// The scalar as a value Heap takes, a number or a string: a boolean as `true` or `false`, and
    /// `nil` for a `null`, which Heap has no value for. Every other scalar as it is.
    fileprivate var heapValue: JSON? {
        switch self {
        case .null: nil
        // Heap's reference lists numbers and strings only, so a boolean is written as a string.
        // Rejected: sending a JSON boolean, which the reference doesn't list as a value, and
        // leaving it out, which would lose it.
        case .boolean(let value): .string(value ? "true" : "false")
        case .string, .integer, .number, .array, .object: self
        }
    }
}
