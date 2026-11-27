// Compiled for macOS and Linux alone, as the factory is (HTTPDestination+GoogleAnalytics.swift), so
// nothing in this module can write a Measurement Protocol request in an app for iOS, iPadOS, tvOS,
// watchOS, visionOS or Mac Catalyst.
#if os(macOS) || os(Linux)
public import Events
public import Foundation
public import HTTPDestinations
import JSONValues
import Logging
public import PropertyJSON
public import TrackingPlans

/// The ``/HTTPDestinations/BatchEncoder`` of Google Analytics 4's Measurement Protocol, so an
/// `HTTPDestination` on a server can send events to a web or data stream's `POST /mp/collect`.
///
/// On macOS and Linux, make the destination with
/// ``HTTPDestinations/HTTPDestination/googleAnalytics(measurementID:apiSecret:region:plan:backoff:clock:now:)``,
/// which fills in the endpoint, the stream's API secret, this encoder and the Measurement
/// Protocol's limits:
///
/// ```swift
/// let googleAnalytics = try HTTPDestination.googleAnalytics(
///     measurementID: measurementID,  // the web or data stream's, G-…
///     apiSecret: apiSecret,  // from the server's configuration, never an app's
///     region: .global,  // or .eu, to have Google collect the data in the EU
///     plan: plan)
/// ```
///
/// The encoder is for a server, and is compiled for macOS and Linux alone, as the Measurement
/// Protocol takes none of its requests without the stream's API secret, which must stay on the
/// server: anyone holding it can send events to the property. A server forwarding an app's events
/// remakes each `EventRecord` with the app's identifier, timestamp and `SessionKey`, and hands
/// them to the destination; tracking them again through a tracker with `.sessions()` would send
/// every user as one `client_id`.
///
/// Each request's body is a JSON object of content type `application/json` holding one client's
/// events, oldest first, as the Measurement Protocol takes one `client_id` a request. A batch of
/// records from several sessions makes a request for each, in the order of each session's first
/// record. The members are:
///
/// | Member | Holds |
/// |---|---|
/// | `client_id` | The records' session, its `SessionKey`, as the first and last 64 bits of the UUID in decimal, joined by a period; the record's own `EventRecord/id` the same way when its context has no session, so each such record is a request of its own |
/// | `consent` | `ad_user_data` and `ad_personalization`, both `DENIED`, so Google uses none of the events for advertising |
/// | `events` | One object per record: `name`, the event's `Event/name` as it is; `params`, the event's stored properties by name; and `timestamp_micros`, when it was tracked, in whole microseconds since 1970 |
///
/// `params` also holds `session_id`, the session's start in Unix milliseconds, the first 48 bits of
/// its version 7 `SessionKey`, so Google Analytics groups the session's events; it is left out for a
/// record with no session, or a session key of another version.
///
/// The session is the only identifier sent: there is no `user_id`, no user properties, and no
/// `user_location`, `ip_override`, `device` or `user_agent`, so Google Analytics records no
/// location or device for the events. The record's vendor identifier and trace context, the
/// standard context, and any other context value, aren't sent. Google Analytics counts a user per
/// `client_id`, so its users are sessions. No `engagement_time_msec` is sent, as Traffluent doesn't
/// measure engagement, so the events don't count toward Google Analytics' engagement time or
/// engaged sessions, and its Realtime and Users reports can show no users while events arrive:
/// check the event counts instead.
///
/// Properties are read through the event's schema in `plan`, as `PropertyReader` reads them. A
/// ``/Events/Sensitive`` value is never sent, whatever the record reveals: the property is left
/// out. Google Analytics takes only strings, numbers and booleans as parameters, so an object or
/// array is spread into a parameter for each value it holds, named after its path joined by `_`
/// (`cart_size`, `tags_0`), and a `null`, such as an optional without a value or a redacted
/// element of an array, is left out.
///
/// A record the encoder can't write is left out of the request, and the batch's other records are
/// sent: one whose event and version `plan` doesn't describe, one whose event or parameter name
/// breaks Google Analytics' naming rules or is one it keeps for itself, one of more than 25
/// parameters, one with a string over 100 bytes, one whose event isn't `Encodable`, one that holds
/// a value JSON can't, one whose timestamp is more than 72 hours before or 15 minutes after the
/// batch is encoded, or has no microseconds form, and one too large for a request
/// (``GoogleAnalyticsEncodingError``). ``requests(for:)`` returns them as `SkippedRecord`s, which
/// `HTTPDestination` logs and reports on its `dropReports`. Google Analytics would answer 2xx to
/// such an event and, under its default, relaxed validation, store it without the parameter that
/// breaks a rule, or under a name it never checked. A Google Analytics 360 property takes values of
/// up to 500 characters, but the encoder holds every property to the standard 100 bytes.
///
/// The Measurement Protocol has no field that identifies an event, so Google Analytics counts each
/// one it receives: a record sent again, by a retry after Google stored it, by a delivery that
/// sends a cancelled batch again, or by a store's redelivery after a relaunch, is counted twice.
///
/// ``requests(for:)`` splits each client's records into requests within the encoder's limit,
/// ``batchLimit`` by default, and makes none for a batch with no record it can write, so
/// `HTTPDestination` sends nothing for it. The Measurement Protocol answers 2xx to every request it
/// receives, a malformed one or one whose events it doesn't store included, so a record the
/// encoder sends is counted as delivered whatever Google Analytics makes of it, and a wrong
/// measurement ID or API secret is answered 2xx with nothing stored: check the property's
/// Realtime event counts after setting the destination up. The bytes are the same for the same records,
/// and the same time, on every run and platform: no whitespace, object members in the order of
/// their names' UTF-8 bytes.
public struct GoogleAnalyticsBatchEncoder: BatchEncoder {
    // From Google's Measurement Protocol docs, read on 2026-11-27:
    // https://developers.google.com/analytics/devguides/collection/protocol/ga4/reference ("events[]
    // ... Up to 25 events can be sent per request", "Up to 25 parameters can be sent per event",
    // "Parameter values must be 100 characters or fewer for a standard Google Analytics property",
    // "The size of the JSON POST body must be less than 130kB", 2xx for every request received) and
    // https://developers.google.com/analytics/devguides/collection/protocol/ga4/sending-events
    // ("Limitations", and "Events and user properties can be backdated up to 72 hours"). The
    // validation server, /debug/mp/collect, the same day: a string's 100 is bytes of UTF-8 (50 "é"
    // pass, 51 don't); a body of 128,150 bytes passes and one of 128,151 doesn't, under the 130 kB
    // the reference gives, so it doesn't count the body's bytes alone; "Measurement protocol only
    // supports timestamps [72h] into the past" and "[15m] into the future"; a null, an array and an
    // object are each "unsupported" as a parameter's value; 26 events pass, but the reference's 25
    // is kept.
    /// The Measurement Protocol's limits on one request: 25 events and 100,000 bytes of body, an
    /// event's included.
    ///
    /// The Measurement Protocol takes up to 25 events in one request, and a body smaller than
    /// 130 kB. Its validation server refuses a body of about 128 kB, without saying how it counts,
    /// so a request of 100,000 bytes stays well under it. 25 events within the limits on
    /// parameters, names and values fit in it unless their strings are mostly characters JSON
    /// escapes.
    public static let batchLimit = (try? BatchLimit(maximumRecordCount: 25, maximumByteCount: 100_000, maximumRecordByteCount: 100_000)) ?? .unlimited

    /// Google Analytics takes no event of more parameters.
    private static let parameterLimit = 25

    /// Google Analytics takes no parameter whose string is longer, in bytes of UTF-8.
    private static let valueByteLimit = 100

    /// How long before a batch is encoded a record may have been tracked: 72 hours.
    private static let earliestOffset: TimeInterval = -72 * 60 * 60

    /// How long after a batch is encoded a record may say it was tracked: 15 minutes.
    private static let latestOffset: TimeInterval = 15 * 60

    /// Ad consent denied for every request: the encoder sends no user data, and Google is to use
    /// none of the events for advertising.
    private static let consent = JSON.object(["ad_personalization": .string("DENIED"), "ad_user_data": .string("DENIED")])

    private static let logger = Logger(label: "GoogleAnalyticsEncoding.GoogleAnalyticsBatchEncoder")

    private let reader: PropertyReader
    private let limit: BatchLimit
    private let now: @Sendable () -> Date

    /// Why a record was left out of the batch's requests.
    public typealias Failure = GoogleAnalyticsEncodingError

    /// An encoder of the events `plan` describes, splitting each batch to `limit`, and leaving out
    /// the records tracked too long before, or too far after, the time `now` gives.
    ///
    /// - Parameters:
    ///   - plan: The tracking plan of every event the encoder is given: each record's event is
    ///     read through the schema of its name and `Event/schemaVersion` here.
    ///   - limit: The most each request holds; ``batchLimit``, the Measurement Protocol's, by
    ///     default.
    ///   - now: The wall-clock time a batch is encoded at, read once a batch; the system's clock by
    ///     default.
    ///
    /// The encoder logs a notice for each event and property of `plan` named as Google Analytics
    /// refuses, or keeps for itself, as it will skip every record of that event
    /// (``GoogleAnalyticsEncodingError``).
    public init(plan: TrackingPlan, limit: BatchLimit = GoogleAnalyticsBatchEncoder.batchLimit, now: @escaping @Sendable () -> Date = { Date.now }) {
        reader = PropertyReader(plan: plan)
        self.limit = limit
        self.now = now
        // Logged once here, where the plan is set up, as every record of such an event will be
        // skipped: setup still succeeds, since the plan may hold events the app never sends here.
        for schema in plan.schemas {
            if !schema.name.isMeasurementProtocolName || schema.name.isReservedMeasurementProtocolEventName {
                Self.logger.notice("Google Analytics refuses the name of event \(schema.name), version \(schema.version): every record of it will be skipped")
            }
            for property in schema.properties where !property.name.isMeasurementProtocolName || property.name.isReservedMeasurementProtocolParameterName {
                Self.logger.notice("Google Analytics refuses the name of property \(property.name) of event \(schema.name), version \(schema.version): every record of it will be skipped")
            }
        }
    }

    /// `batch` as the requests the Measurement Protocol takes, a client's records in each, within
    /// the encoder's limit, with the records left out of them.
    ///
    /// - Parameter batch: Records of tracked events, oldest first.
    /// - Returns: The requests, a client's after another's in the order of each client's first
    ///   record, none when no record can be written, and each record left out, with why
    ///   (``GoogleAnalyticsEncodingError``), a client's after another's in the same order: one it
    ///   can't encode, one past Google Analytics' rules or its window of time, and one whose event
    ///   is over the limit's bytes for one event, or for a request of it alone
    ///   (``GoogleAnalyticsEncodingError/oversized(byteCount:)``).
    /// - Complexity: O(*n* log *n*) in the batch's size, for sorting each object's members.
    public func requests(for batch: [EventRecord]) -> BatchRequests<GoogleAnalyticsEncodingError> {
        let encodedAt = now()
        var clients: [(id: String, records: [EventRecord])] = []
        var offsets: [String: Int] = [:]
        for record in batch {
            let clientID = record.pseudonymousIdentity.uuid.measurementProtocolClientID
            if let offset = offsets[clientID] {
                clients[offset].records.append(record)
            } else {
                offsets[clientID] = clients.count
                clients.append((clientID, [record]))
            }
        }
        var requests: [EncodedRequest] = []
        var skippedRecords: [SkippedRecord<GoogleAnalyticsEncodingError>] = []
        for client in clients {
            let envelope = JSONEnvelope(["client_id": .string(client.id), "consent": Self.consent], arrayMember: "events")
            let clientRequests = limit.requests(for: client.records, in: envelope) { record throws(GoogleAnalyticsEncodingError) in
                try json(of: record, encodedAt: encodedAt)
            } oversized: { byteCount in
                .oversized(byteCount: byteCount)
            }
            requests += clientRequests.requests
            skippedRecords += clientRequests.skippedRecords
        }
        return BatchRequests(requests: requests, skippedRecords: skippedRecords)
    }

    private func json(of record: EventRecord, encodedAt: Date) throws(GoogleAnalyticsEncodingError) -> JSON {
        let properties: [String: JSON]
        do {
            // Never a Sensitive value: Google Analytics is a vendor's store, whatever the record
            // reveals.
            properties = try reader.properties(of: record, includingSensitiveValues: false)
        } catch {
            // The event's name is reported before the reader's other reasons, but after an event
            // the plan doesn't describe.
            if case .unknownEvent = error {} else {
                try record.checkName()
            }
            throw GoogleAnalyticsEncodingError(error)
        }
        try record.checkName()
        var parameters: [String: JSON]
        do {
            // `_`, as a parameter's name may hold no `.`.
            parameters = try properties.flattened(separator: "_").filter { $0.value != .null }
        } catch {
            throw .parameterNameCollision(event: record.name, parameter: error.key)
        }
        // In order, so of two names that break a rule, the error always names the same one.
        let names = parameters.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        if let invalid = names.first(where: { !$0.isMeasurementProtocolName }) {
            throw .invalidParameterName(event: record.name, parameter: invalid)
        }
        if let reserved = names.first(where: \.isReservedMeasurementProtocolParameterName) {
            throw .reservedParameterName(event: record.name, parameter: reserved)
        }
        for name in names {
            if case .string(let text) = parameters[name], text.utf8.count > Self.valueByteLimit {
                throw .parameterValueTooLong(event: record.name, parameter: name, byteCount: text.utf8.count)
            }
        }
        // D4: the session is the only identifier sent, as the request's client_id; its start
        // groups the session's events.
        if case .session(let session) = record.pseudonymousIdentity, let start = session.version7Milliseconds {
            parameters["session_id"] = .integer(start)
        }
        // Checked on the event as sent, so the count includes session_id: the Measurement Protocol
        // answers 2xx for a request whose events it drops, so a record past its limit would be
        // acknowledged and deleted without being stored.
        guard parameters.count <= Self.parameterLimit else {
            throw .tooManyParameters(event: record.name, count: parameters.count)
        }
        guard let microseconds = record.timestamp.microsecondsSince1970 else {
            throw .unrepresentableTimestamp
        }
        // Measured from when the batch is encoded: a request retried for long can still arrive
        // after its records' 72 hours. A NaN `now` compares false both ways, so a broken clock
        // leaves the window to Google.
        let offset = record.timestamp.timeIntervalSince(encodedAt)
        if offset < Self.earliestOffset || offset > Self.latestOffset {
            throw .timestampOutsideWindow
        }
        return .object([
            "name": .string(record.name),
            "params": .object(parameters),
            "timestamp_micros": .integer(microseconds),
        ])
    }
}

extension GoogleAnalyticsEncodingError {
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
    /// Throws when Google Analytics refuses the event's name, or keeps it for its own events.
    fileprivate func checkName() throws(GoogleAnalyticsEncodingError) {
        guard name.isMeasurementProtocolName else {
            throw .invalidEventName(name: name)
        }
        guard !name.isReservedMeasurementProtocolEventName else {
            throw .reservedEventName(name: name)
        }
    }
}

extension Date {
    /// The whole microseconds from 1970-01-01T00:00:00Z to the date, rounded down; `nil` when the
    /// date isn't finite, or is more than `Int64.max` microseconds from 1970 either way.
    fileprivate var microsecondsSince1970: Int64? {
        // Int64(exactly:) of the rounded-down value: nil for NaN, an infinity and anything outside
        // Int64's range, where Int64(_:) would trap.
        Int64(exactly: (timeIntervalSince1970 * 1_000_000).rounded(.down))
    }
}
#endif
