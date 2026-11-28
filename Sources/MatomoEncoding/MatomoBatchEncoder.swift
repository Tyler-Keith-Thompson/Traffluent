public import Events
public import Foundation
public import HTTPDestinations
import JSONValues
import Logging
public import PropertyJSON
import StandardContext
public import TrackingPlans

/// The ``/HTTPDestinations/BatchEncoder`` of Matomo's bulk tracking API, so an `HTTPDestination` can
/// send events to a Matomo installation's `POST /matomo.php`.
///
/// Make the destination with
/// ``HTTPDestinations/HTTPDestination/matomo(url:siteID:dimensions:category:plan:backoff:clock:now:)``,
/// which fills in the endpoint, this encoder and its limits:
///
/// ```swift
/// let matomo = try HTTPDestination.matomo(
///     url: url,  // where Matomo is installed: https://analytics.example.com
///     siteID: 3,  // the app's site in Matomo
///     dimensions: ["plan": 1, "seats": 2],  // custom dimensions made in Matomo
///     category: "Shop",  // each event's category
///     plan: plan)
/// ```
///
/// The body is a JSON object of content type `application/json`, `{"requests":[…]}`, whose
/// `requests` are one tracking request per record, oldest first, as Matomo asks for them: each a
/// string, `?` and the request's query, every value percent-encoded but for RFC 3986's unreserved
/// characters. Each request is a Matomo event, with these parameters in this order:
///
/// | Parameter | Holds |
/// |---|---|
/// | `idsite` | The site ID the encoder is made with |
/// | `rec` | `1`, without which Matomo records nothing |
/// | `apiv` | `1`, the Tracking API's version |
/// | `_id` | The visitor: the last 64 bits of the record's session, its `SessionKey`, as 16 lowercase hexadecimal digits; of the record's own `EventRecord/id` the same way when its context has no session |
/// | `cdt` | When the event was tracked, in whole seconds since 1970, rounded down |
/// | `ca` | `1`: the request is an event, not a page view, should Matomo's Events plugin be turned off |
/// | `e_c` | The category the encoder is made with |
/// | `e_a` | The event's `Event/name`, as it is |
/// | `lang` | The record's locale's BCP 47 identifier, `en-US`, when its context has a `LocaleKey` |
/// | `dimension<ID>` | Each mapped property's value, by the dimension's ID, from lowest to highest |
///
/// The session is the only identifier sent. Matomo counts a visitor per `_id`, so its visitors are
/// sessions, each a new visitor of one visit. A record with no session (one tracked by a tracker
/// without `Enricher.sessions()`) is its own visitor, linked to nothing. A record a store recovers
/// after a relaunch keeps its session, so it goes out under the `_id` of its first send. No `uid`, `cid`, `token_auth`, `cip` or device
/// identifier is sent, and nothing of the record's context but its locale, nor its trace context.
///
/// A property reaches Matomo only as the custom dimension `dimensions` maps it to, read through
/// the event's schema in `plan`, as `PropertyReader` reads it: a string as it is, a number as JSON
/// writes it, a Boolean as `true` or `false`, and an array or object as its JSON. A `nil` is left
/// out. A ``/Events/Sensitive`` value is never sent, whatever the record reveals: the property is
/// left out, and an element of an array is `null`. Every other property is left out, and the
/// encoder logs a notice once, when it is made, for each event of the plan with properties no
/// dimension is mapped to (``MatomoDimensions/unmappedProperties(in:)``).
///
/// A record the encoder can't write, or that Matomo would refuse or store other than it is, is
/// left out of the request, and the batch's other records are sent: one whose event and version
/// `plan` doesn't describe, one whose event name Matomo would empty or cut short, one whose event
/// isn't `Encodable`, one that holds a value JSON can't, one whose timestamp has no whole seconds
/// of `Int64` or is more than 23 hours before or after the batch is encoded, one with a dimension's
/// value longer than Matomo keeps, and one whose request is over 1,000,000 bytes
/// (``MatomoEncodingError``). ``requests(for:)`` returns them as `SkippedRecord`s, which
/// `HTTPDestination` logs and reports on its `dropReports`.
///
/// Each request's `EncodedRequest/deadline` is 23 hours after its oldest record was tracked, so
/// `HTTPDestination` drops a request still being retried by then, every record of it, the younger
/// ones included, and reports it as `HTTPDropReport.deadlineExceeded(deadline:recordIDs:)`, rather
/// than send it to a Matomo that would answer 200 and store nothing.
///
/// ``requests(for:)`` splits a batch into requests within the encoder's limit, ``batchLimit`` by
/// default, and makes none for a batch with no record it can write, so `HTTPDestination` sends
/// nothing for it. Matomo answers 200 to a bulk request it reads, counting the tracking requests
/// it refuses as `invalid` in its answer without storing them; 400 to a body it can't read, which
/// `HTTPDestination` drops and reports with every record of the request; and 500 when its database
/// fails, which `HTTPDestination` retries. A 200 that says Matomo tracked none of the request's
/// tracking requests is rejected (``outcome(of:for:)``), so `HTTPDestination` drops and reports it
/// too; one that refused only some isn't, as its answer doesn't say which. It doesn't remove duplicates, so a record sent again is
/// counted again. The bytes are the same for the same records, time and configuration on every run
/// and platform.
public struct MatomoBatchEncoder: BatchEncoder {
    /// No status beyond the 408, 429 and 5xx that `HTTPDestination` retries for every encoder.
    public static let transientStatuses: Set<TransientStatus> = []

    // From Matomo 6.0.0's source, read on 2026-11-27: plugins/BulkTracking/Tracker/Response.php
    // answers {"status":"success","tracked":n,"invalid":m}, where tracked counts the tracking
    // requests core/Tracker.php trackRequest logged and invalid those that threw
    // UnexpectedWebsiteFoundException (a site ID of no site) or InvalidRequestParameterException
    // (a cdt outside the window, say). Handler.php skips, uncounted, a tracking request that hit
    // a database lock wait timeout, and Tracker.php logs none when record_statistics is 0, so a
    // count short of the request's can't tell a passing lock from tracking turned off: it is sent
    // again, which the request's 23-hour deadline bounds. Not verified: the QueuedTracking plugin
    // queues tracking requests rather than logging them, and its queued ones may not count as
    // tracked, which would send every request again until its deadline on such an installation.
    /// What Matomo's 2xx answer to `request` means: transient when Matomo counted fewer of its
    /// tracking requests than were sent, rejected when it refused every one it counted, and
    /// delivered otherwise.
    ///
    /// Matomo answers a bulk request it reads with 200 and `{"status": "success", "tracked": n,
    /// "invalid": m}`. When `tracked` and `invalid` add up to fewer than the request's tracking
    /// requests, or are both 0, Matomo skipped some without saying so, as it does after a database
    /// lock wait timeout, and the answer is ``/HTTPDestinations/ResponseOutcome/transient(reason:)``:
    /// `HTTPDestination` sends the request again until its deadline, 23 hours after its oldest
    /// record, and Matomo, which removes no duplicates, counts the ones it tracked again. When it
    /// tracked none and refused some, as for a site ID of no site, the answer is
    /// ``/HTTPDestinations/ResponseOutcome/rejected(reason:)``, so `HTTPDestination` drops the
    /// request and reports it. When it tracked some and refused others, the answer says how many
    /// but not which, so the request is delivered, with a notice logged. A body that isn't such an
    /// answer, an empty one or one with a negative count included, is delivered.
    ///
    /// - Parameters:
    ///   - response: The 2xx answer.
    ///   - request: The request it answers, a tracking request for each of its records.
    /// - Returns: Whether Matomo stored the request's tracking requests, as far as its answer says.
    public static func outcome(of response: HTTPTransportResponse, for request: EncodedRequest) -> ResponseOutcome {
        guard let answer = try? JSONDecoder().decode(BulkAnswer.self, from: response.body), answer.tracked >= 0, answer.invalid >= 0 else {
            return .delivered
        }
        let sent = request.recordIDs.count
        // Written as comparisons of counts that are never negative, so no sum overflows.
        let skippedSome = answer.tracked < sent && answer.invalid < sent - answer.tracked
        if skippedSome || (answer.tracked == 0 && answer.invalid == 0) {
            return .transient(reason: "Matomo counted \(answer.tracked) tracked and \(answer.invalid) invalid of the request's \(sent) tracking requests, and skipped the rest")
        }
        guard answer.tracked > 0 else {
            return .rejected(reason: "Matomo refused all \(answer.invalid) of the request's tracking requests as invalid, as it does for a site ID of no site")
        }
        if answer.invalid > 0 {
            logger.notice("Matomo tracked \(answer.tracked) of a bulk request's tracking requests and refused \(answer.invalid), without saying which")
        }
        return .delivered
    }

    // From Matomo's Tracking HTTP API reference, https://developer.matomo.org/api-reference/tracking-api
    // (the Matomo 6.x docs), read on 2026-11-27: idsite and rec=1 required; _id "must be a 16
    // characters hexadecimal string"; apiv=1; e_c and e_a "Must not be empty", e_n and e_v
    // optional, whitespace trimmed; dimension[0-999]; ca=1 "together with an event tracking
    // request"; "If you set cdt to a datetime older than 24 hours then token_auth must be set";
    // bulk tracking is "an HTTP POST ... with a JSON object" whose "requests" are "the query string
    // you'd send if you were going to track that action individually", oldest first; token_auth
    // optional, "only needed if you use any of the parameters that require token_auth".
    // And from Matomo's source, matomo-org/matomo 6.0.0, the same day (5.14.3 agrees but where
    // noted):
    // - core/Tracker/Request.php getCustomTimestamp: a numeric cdt is Unix seconds; one at least
    //   tracking_requests_require_authentication_when_custom_timestamp_newer_than (86400 by
    //   default, config/global.ini.php) seconds old throws InvalidRequestParameterException
    //   without token_auth; one more than 86400 seconds ahead throws too (6.0; 5.14.3 records it
    //   at the time it arrives), and one less ahead is recorded at the time it arrives.
    // - plugins/BulkTracking/Tracker/Handler.php and Response.php: a tracking request that throws
    //   UnexpectedWebsiteFoundException or InvalidRequestParameterException is counted as invalid
    //   and the bulk request answered {"status":"success","tracked":n,"invalid":m}, its
    //   invalid_indices only with a token_auth; Requests.php reads each string with parse_url and
    //   parse_str, so + is a space; a body that isn't an object with a requests array is a 400
    //   (6.0). No limit on the number of requests.
    // - core/Tracker/Request.php getVisitorId: uid, then cid, then _id when 16 hex digits or more,
    //   unless the privacy setting forceCookielessTracking ignores _id.
    /// The limits of one request: 20 tracking requests and 1,000,000 bytes of body, a tracking
    /// request's included.
    ///
    /// The 20 records are what Matomo's iOS SDK sends in a bulk request. Matomo documents no limit
    /// on a bulk request; the 1,000,000 bytes stay under the 1 MiB that nginx, in front of many
    /// Matomo installations, takes in a body by default. A larger record is left out as
    /// ``MatomoEncodingError/oversized(byteCount:)``.
    public static let batchLimit = (try? BatchLimit(maximumRecordCount: 20, maximumByteCount: 1_000_000, maximumRecordByteCount: 1_000_000)) ?? .unlimited

    /// How long before or after a batch is encoded, or before its request is sent, a record may
    /// have been tracked, in seconds: 23 hours. Matomo takes a time up to a day old without a `token_auth`; the
    /// hour to spare is for a queue on the server and clocks that disagree.
    private static let windowSeconds: TimeInterval = 23 * 60 * 60

    /// ``windowSeconds`` as the maximum age of a request's oldest record.
    private static let window: Duration = .seconds(windowSeconds)

    /// The most characters Matomo stores of an event's category or action: its `log_action.name`
    /// column's 4,096.
    static let actionLength = 4096

    /// The most characters Matomo keeps of a custom dimension's value.
    private static let dimensionValueLength = 250

    private static let logger = Logger(label: "MatomoEncoding.MatomoBatchEncoder")

    private let reader: PropertyReader
    private let limit: BatchLimit
    private let now: @Sendable () -> Date
    private let siteID: String
    private let category: String
    private let dimensions: [String: Int]

    /// Why a record was left out of the batch's requests.
    public typealias Failure = MatomoEncodingError

    /// An encoder of the events `plan` describes, for the Matomo site `siteID`, sending each event
    /// in `category` and each property `dimensions` maps as its custom dimension, splitting each
    /// batch to `limit`, and leaving out the records tracked too long before, or after, the time
    /// `now` gives.
    ///
    /// - Parameters:
    ///   - siteID: The site's ID in Matomo, from its Websites settings.
    ///   - dimensions: The custom dimension each property is sent as, by the property's name.
    ///   - category: Every event's category, `e_c`, such as the app's name.
    ///   - plan: The tracking plan of every event the encoder is given: each record's event is
    ///     read through the schema of its name and `Event/schemaVersion` here.
    ///   - limit: The most each request holds; ``batchLimit`` by default.
    ///   - now: The wall-clock time a batch is encoded at, read once a batch; the system's clock by
    ///     default. When it reads NaN or infinite, every record of the batch is left out as
    ///     ``MatomoEncodingError/timestampOutsideWindow``.
    /// - Throws: ``MatomoSetupError/invalidSiteID`` for a site ID below 1,
    ///   ``MatomoSetupError/invalidCategory`` for a category Matomo would empty or cut short, and
    ///   ``MatomoSetupError/invalidDimension(property:dimension:)``,
    ///   ``MatomoSetupError/duplicateProperty(_:)``, ``MatomoSetupError/unknownProperty(_:)``,
    ///   ``MatomoSetupError/sensitiveProperty(event:version:property:)`` or
    ///   ``MatomoSetupError/sharedDimension(event:version:dimension:)`` for a mapping that breaks a
    ///   rule against `plan`.
    ///
    /// The encoder logs a notice for each event of `plan` with properties no dimension is mapped
    /// to, as Matomo never receives them, and for each event whose name Matomo would empty or cut
    /// short, as it will skip every record of it (``MatomoEncodingError/invalidEventName(name:)``).
    public init(siteID: Int, dimensions: MatomoDimensions, category: String, plan: TrackingPlan, limit: BatchLimit = MatomoBatchEncoder.batchLimit, now: @escaping @Sendable () -> Date = { Date.now }) throws(MatomoSetupError) {
        guard siteID >= 1 else { throw .invalidSiteID }
        guard category.isMatomoAction else { throw .invalidCategory }
        self.dimensions = try dimensions.dimensions(checkedAgainst: plan)
        reader = PropertyReader(plan: plan)
        self.limit = limit
        self.now = now
        self.siteID = String(siteID)
        self.category = category
        // Logged once here, where the plan is set up, rather than as a SkippedRecord per record: a
        // record is still sent without its unmapped properties, and a report would drop it.
        var unmapped: [String: [MatomoUnmappedProperty]] = [:]
        for property in dimensions.unmappedProperties(in: plan) {
            unmapped["\(property.event), version \(property.version)", default: []].append(property)
        }
        for (event, properties) in unmapped.sorted(by: { $0.key < $1.key }) {
            Self.logger.notice("Matomo never receives the properties \(properties.map(\.property).joined(separator: ", ")) of event \(event): no custom dimension is mapped to them")
        }
        for schema in plan.schemas where !schema.name.isMatomoAction {
            Self.logger.notice("Matomo would empty or cut short the name of event \(schema.name), version \(schema.version): every record of it will be skipped")
        }
    }

    /// `batch` as the bulk requests Matomo takes, each within the encoder's limit, with the records
    /// left out of them.
    ///
    /// - Parameter batch: Records of tracked events, oldest first.
    /// - Returns: The requests, in order, none when no record can be written, and each record left
    ///   out, with why (``MatomoEncodingError``): one it can't encode, one past Matomo's rules or
    ///   its window of time, and one whose tracking request is over the limit's bytes for one
    ///   record, or for a request of it alone (``MatomoEncodingError/oversized(byteCount:)``).
    /// - Complexity: O(*n*) in the length of the batch's values, besides reading its properties.
    public func requests(for batch: [EventRecord]) -> BatchRequests<MatomoEncodingError> {
        let encodedAt = now()
        // Each request's deadline is its oldest record's 23 hours. Only the past side: Matomo
        // checks cdt against when the request arrives, and a retry only ever arrives later, so it
        // can carry a record past a day old but never further ahead than it was when encoded.
        let encoding = { (record: EventRecord) throws(MatomoEncodingError) -> JSON in
            try json(of: record, encodedAt: encodedAt)
        }
        let oversized = { (byteCount: Int) -> MatomoEncodingError in
            .oversized(byteCount: byteCount)
        }
        do {
            return try limit.requests(for: batch, in: Self.envelope, maximumAge: Self.window, encoding: encoding, oversized: oversized)
        } catch {
            // Never reached: the window is a positive constant, and only a negative age throws.
            // Requests without a deadline rather than a trap (D10).
            return limit.requests(for: batch, in: Self.envelope, encoding: encoding, oversized: oversized)
        }
    }

    /// `{"requests":[…]}`, with no token_auth: a bulk request of tracking requests any client may
    /// send.
    private static let envelope = JSONEnvelope([:], arrayMember: "requests")

    private func json(of record: EventRecord, encodedAt: Date) throws(MatomoEncodingError) -> JSON {
        let properties: [String: JSON]
        do {
            // Never a Sensitive value: Matomo is a store the app doesn't control, whatever the
            // record reveals.
            properties = try reader.properties(of: record, includingSensitiveValues: false)
        } catch {
            // The event's name is reported before the reader's other reasons, but after an event
            // the plan doesn't describe.
            if case .unknownEvent = error {} else {
                try record.checkMatomoName()
            }
            throw MatomoEncodingError(error)
        }
        try record.checkMatomoName()
        // Int64(exactly:) of the rounded-down seconds: nil for NaN, an infinity and anything
        // outside Int64's range.
        guard let seconds = Int64(exactly: record.timestamp.timeIntervalSince1970.rounded(.down)) else {
            throw .unrepresentableTimestamp
        }
        // Measured from when the batch is encoded: Matomo answers 200 for a request it refuses for
        // its time, so a record past the window would be acknowledged and deleted without being
        // stored. Written as the window's inside, so a NaN offset, from a `now` that is NaN or
        // infinite, is outside it and every record is reported (D10). Rejected: leaving such a
        // clock to Matomo, which would drop the records it refuses without a report.
        let offset = record.timestamp.timeIntervalSince(encodedAt)
        guard offset >= -Self.windowSeconds, offset <= Self.windowSeconds else {
            throw .timestampOutsideWindow
        }
        // D4: the session is the only identifier sent. A record without one (its tracker has no
        // sessions enricher) becomes its own visitor rather than being skipped, which would let the
        // delivery acknowledge it and the store delete it.
        var parameters: [(name: String, value: String)] = [
            ("idsite", siteID),
            ("rec", "1"),
            ("apiv", "1"),
            ("_id", record.pseudonymousIdentity.uuid.matomoVisitorID),
            ("cdt", String(seconds)),
            ("ca", "1"),
            ("e_c", category),
            ("e_a", record.name),
        ]
        if let locale = record.context[LocaleKey.self] {
            parameters.append(("lang", locale.identifier(.bcp47)))
        }
        // By dimension, so the request, and which of two values too long is reported, is the
        // same on every run.
        let values = properties.compactMap { name, value in
            dimensions[name].flatMap { dimension in value.matomoDimensionValue.map { (dimension: dimension, property: name, value: $0) } }
        }
        for value in values.sorted(by: { $0.dimension < $1.dimension }) {
            let length = value.value.matomoStoredLength
            guard length <= Self.dimensionValueLength else {
                throw .dimensionValueTooLong(event: record.name, property: value.property, dimension: value.dimension, length: length)
            }
            parameters.append(("dimension\(value.dimension)", value.value))
        }
        return .string("?" + parameters.map { $0.name + "=" + $0.value.percentEncodedForQuery }.joined(separator: "&"))
    }
}

extension MatomoEncodingError {
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
    /// Throws when Matomo would empty or cut short the event's name as an event's action.
    fileprivate func checkMatomoName() throws(MatomoEncodingError) {
        guard name.isMatomoAction else {
            throw .invalidEventName(name: name)
        }
    }
}

extension String {
    /// Whether Matomo stores this as an event's category or action as it is sent: not empty once
    /// Matomo removes its line breaks and trims it, and no longer than the 4,096 characters it
    /// stores of one.
    var isMatomoAction: Bool {
        let length = matomoStoredLength
        return length >= 1 && length <= MatomoBatchEncoder.actionLength
    }
}

extension JSON {
    /// The value as a custom dimension's text: a string as it is, a number as JSON writes it, a
    /// Boolean as `true` or `false`, and an array or object as its JSON; `nil` for `null`, which
    /// sends no value.
    fileprivate var matomoDimensionValue: String? {
        switch self {
        case .null: nil
        case .string(let text): text
        case .integer, .number, .boolean, .array, .object: minified
        }
    }
}

/// Matomo's answer to a bulk tracking request it read.
private struct BulkAnswer: Decodable {
    /// How many of the request's tracking requests Matomo stored.
    let tracked: Int
    /// How many it refused.
    let invalid: Int
}
