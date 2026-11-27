public import Events
import Foundation
public import HTTPDestinations
import JSONValues
import Logging
public import PropertyJSON
public import TrackingPlans

/// The ``/HTTPDestinations/BatchEncoder`` of Snowplow's tracker protocol, so an `HTTPDestination`
/// can send events to a Snowplow collector's `POST /com.snowplowanalytics.snowplow/tp2`, as
/// self-describing events whose schemas are the tracking plan's.
///
/// Make the destination with
/// ``HTTPDestinations/HTTPDestination/snowplow(collector:vendor:appID:plan:backoff:clock:)``, which
/// fills in the endpoint, the header field that keeps the collector from setting a cookie or
/// recording the request's address, this encoder and its limits:
///
/// ```swift
/// let snowplow = try HTTPDestination.snowplow(
///     collector: collector,  // https://collector.example.com
///     vendor: "com.example",  // your schemas' Iglu vendor
///     appID: "shop-ios",
///     plan: plan)
/// ```
///
/// The body is a self-describing JSON object of content type `application/json`, of the schema
/// `iglu:com.snowplowanalytics.snowplow/payload_data/jsonschema/1-0-4`, whose `data` is an array of
/// events, one per record, oldest first. Every member of an event is a string, as the tracker
/// protocol has them:
///
/// | Member | Holds |
/// |---|---|
/// | `aid` | The app ID the encoder is made with |
/// | `co` | The standard context's entities (below), as the text of a self-describing JSON array of `contexts`; left out when there are none |
/// | `dtm`, `ttm` | When the event was tracked, in epoch milliseconds |
/// | `e` | `ue`, a self-describing event |
/// | `eid` | The record's `EventRecord/id`, as a lowercase UUID; a redelivered record keeps it |
/// | `ip` | `0.0.0.0` |
/// | `p` | The platform: `mob` for a phone, pad, watch or Vision Pro, `tv` for an Apple TV, `pc` for a Mac, and `app` when the record has no device in its context |
/// | `sid` | The record's session, its `SessionKey`, as a lowercase UUID; left out when its context has no session |
/// | `tv` | `traffluent`, the tracker |
/// | `ue_pr` | The event, as the text of a self-describing JSON `unstruct_event` holding the event's own self-describing JSON: its schema, `iglu:<vendor>/<name>/jsonschema/<version>-0-0`, and its data, its stored properties by name |
///
/// The session is the only identifier sent: there is no `duid`, `uid`, `nuid` or `tnuid`, no
/// `client_session` entity, whose `userId` lasts across sessions, and no `appleIdfv`, `appleIdfa`
/// or other device identifier. Snowplow's `domain_sessionid` is the session; a record with no
/// session (one tracked by a tracker without `Enricher.sessions()`, or one a store recovered after
/// a relaunch, which keeps no context) is sent without one, linked to nothing. The record's vendor
/// identifier and trace context, and any other context value, aren't sent.
///
/// Each event's `ttm`, its true timestamp, is the record's timestamp, as is `dtm`, so Snowplow's
/// `derived_tstamp` is when the event was tracked, uncorrected for the device's clock. No `stm`
/// is sent: a retried request sends the same body again, so a sent time would be the first
/// attempt's, and Snowplow would move the event later by however long the retries took.
///
/// The event's schema is named after its `Event/name` and `Event/schemaVersion`: version N is
/// SchemaVer `N-0-0`. Each version of an event is a breaking change, a SchemaVer MODEL. A
/// compatible change at the same version is an ADDITION, which the tracking plan's Iglu export
/// (`TrackingPlan/writeIgluRegistry(to:vendor:registry:)`) writes for Iglu Server as `N-0-1` and
/// on, each superseding the ones before, so an event naming `N-0-0` is validated against the
/// newest of them. A static repository doesn't supersede: there an event naming `N-0-0` is
/// validated against `N-0-0` alone, so the export refuses an addition for one, and a change to an
/// event needs a new version.
///
/// Properties are read through the event's schema in `plan`, as `PropertyReader` reads them. A
/// ``/Events/Sensitive`` value is never sent, whatever the record reveals: the property is left
/// out, an element of an array is `null`, and one inside a type the plan can't map is `null`. The
/// data then validates against the event's exported schema, which never requires a `Sensitive`
/// property.
///
/// `co` holds these entities, for the keys the record's context has values for:
///
/// | Entity | Keys | Holds |
/// |---|---|---|
/// | `iglu:com.snowplowanalytics.snowplow/mobile_context/jsonschema/1-0-3` | `DeviceKey` and `OperatingSystemKey`, both; `NetworkKey` and `LocaleKey` if present | `osType` (`ios`, `tvos`, `watchos`, `visionos`, `osx`), `osVersion`, `deviceManufacturer` (`Apple Inc.`), `deviceModel`; `networkType` (`wifi`, `mobile`, `offline`; left out for a wired or other connection); `language`, the locale's language code |
/// | `iglu:com.snowplowanalytics.mobile/application/jsonschema/1-0-0` | `ApplicationKey`, with both a version and a build | `version` and `build` |
///
/// A record the encoder can't write is left out of the request, and the batch's other records are
/// sent: one whose event and version `plan` doesn't describe, one whose event name Iglu doesn't
/// take, one whose event isn't `Encodable`, one that holds a value JSON can't, one whose timestamp
/// is outside the years 0 to 9999, and one whose JSON is over 150,000 bytes
/// (``SnowplowEncodingError``).
/// ``requests(for:)`` returns them as `SkippedRecord`s, which `HTTPDestination` logs and reports
/// on its `dropReports`.
///
/// ``requests(for:)`` splits a batch into requests within the encoder's limit, ``batchLimit`` by
/// default, and makes none for a batch with no record it can write, so `HTTPDestination` sends
/// nothing for it. The collector answers 200 to every request it can read, and Snowplow validates
/// the events afterwards: an event whose data its schema rejects, or whose schema the pipeline's
/// Iglu resolver can't find, becomes a failed event, kept apart from the warehouse, though the
/// destination counts it as delivered. The bytes are the same for the same records on every run
/// and platform: no whitespace, object members in the order of their names' UTF-8 bytes.
public struct SnowplowBatchEncoder: BatchEncoder {
    /// No status beyond the 408, 429 and 5xx that `HTTPDestination` retries for every encoder.
    public static let transientStatuses: Set<TransientStatus> = []

    // From Snowplow's docs, read on 2026-11-27:
    // - Example HTTP requests, https://docs.snowplow.io/docs/events/http-requests/ (the tp2 path,
    //   the payload_data 1-0-4 wrapper, the unstruct_event wrapper and contexts).
    // - Atomic event properties, https://docs.snowplow.io/docs/fundamentals/canonical-event/
    //   (e, eid, aid, p, tv required; aid at most 255 characters; timestamps in epoch ms;
    //   platform values).
    // - Schemas, https://docs.snowplow.io/docs/fundamentals/schemas/ (ue_pr and co carry JSON,
    //   ue_px and cx base64).
    // - Mobile trackers, https://docs.snowplow.io/docs/sources/mobile-trackers/configuring-how-events-are-sent/
    //   (emitRange, 25 events a request by default), and snowplow-ios-tracker 6.5.0's
    //   EmitterDefaults (byteLimitPost 40000) and Emitter (an event over byteLimitPost is sent in
    //   a request of its own: "Oversize event -> separate requests").
    // - Collector configuration, https://docs.snowplow.io/docs/api-reference/stream-collector/configure/
    //   (a body over dropPayloadSize, 2 MB, answered 413; a record over a sink's maxBytes, 192 kB
    //   for SQS and 1 MB for Kinesis by default, a size-violation failed event).
    // And from Snowplow's sources: payload_data 1-0-4 on Iglu Central (every member a string,
    // tv, p and e required, no other member allowed); Enrich 6.15.0's EventEnrichments
    // (derived_tstamp is ttm when set, otherwise the collector's time less stm minus dtm, or the
    // collector's time alone without stm; a timestamp outside years 0 to 9999 fails the event).
    /// Snowplow's trackers' limits on one request, 25 events and 40,000 bytes of body, and an event
    /// of up to 150,000 bytes in a request of its own.
    ///
    /// Snowplow's mobile trackers send at most 25 events and 40,000 bytes in a request by default,
    /// and an event larger than that in a request of its own. A collector refuses a body over 2 MB
    /// with 413, and a request larger than its stream takes (192,000 bytes on SQS, 1 MB on
    /// Kinesis, by default) becomes a failed event though the collector answers 200. So an event
    /// of up to 150,000 bytes of JSON is sent alone, within the smallest of those, and a larger one
    /// is left out as ``SnowplowEncodingError/oversized(byteCount:)``.
    public static let batchLimit = (try? BatchLimit(maximumRecordCount: 25, maximumByteCount: 40_000, maximumRecordByteCount: 150_000, sendsLargeRecordsAlone: true)) ?? .unlimited

    /// The seconds from 1970 to 0000-01-01T00:00:00Z: Snowplow's enrichment fails an event
    /// timestamped earlier.
    private static let earliestSeconds: Double = -62_167_219_200

    /// The seconds from 1970 to 10000-01-01T00:00:00Z: Snowplow's enrichment fails an event
    /// timestamped from then on.
    private static let endSeconds: Double = 253_402_300_800

    private static let envelope = JSONEnvelope(["schema": .string("iglu:com.snowplowanalytics.snowplow/payload_data/jsonschema/1-0-4")], arrayMember: "data")

    private static let logger = Logger(label: "SnowplowEncoding.SnowplowBatchEncoder")

    private let reader: PropertyReader
    private let limit: BatchLimit
    private let appID: String
    /// Each event's schema URI, by its name and version, for the plan's events Iglu can name.
    private let schemaURIs: [SchemaKey: String]

    /// Why a record was left out of the batch's requests.
    public typealias Failure = SnowplowEncodingError

    /// An encoder of the events `plan` describes, whose schemas are under `vendor`, sent as the
    /// app `appID`, splitting each batch to `limit`.
    ///
    /// - Parameters:
    ///   - vendor: The Iglu vendor of the events' schemas, in reverse domain notation
    ///     (`com.acme`): the one the tracking plan's Iglu export is given.
    ///   - appID: The app's ID, each event's `aid`, which tells apart the apps and sites that send
    ///     to one pipeline.
    ///   - plan: The tracking plan of every event the encoder is given: each record's event is
    ///     read through the schema of its name and `Event/schemaVersion` here.
    ///   - limit: The most each request holds; ``batchLimit``, Snowplow's trackers', by default.
    /// - Throws: ``SnowplowSetupError/invalidVendor`` for a vendor Iglu doesn't take, and
    ///   ``SnowplowSetupError/invalidAppID`` for an empty app ID or one longer than 255 UTF-16
    ///   code units.
    ///
    /// The encoder logs a notice for each event of `plan` Iglu can't name, as it will skip every
    /// record of it (``SnowplowEncodingError/invalidSchemaKey(name:version:)``).
    public init(vendor: String, appID: String, plan: TrackingPlan, limit: BatchLimit = SnowplowBatchEncoder.batchLimit) throws(SnowplowSetupError) {
        guard vendor.isIgluVendor else { throw .invalidVendor }
        // Snowplow's app_id holds 255 characters of a JVM string, which counts UTF-16 code units.
        guard !appID.isEmpty, appID.utf16.count <= 255 else { throw .invalidAppID }
        reader = PropertyReader(plan: plan)
        self.limit = limit
        self.appID = appID
        var schemaURIs: [SchemaKey: String] = [:]
        for schema in plan.schemas {
            if schema.name.hasIgluSchemaKey(version: schema.version) {
                schemaURIs[SchemaKey(name: schema.name, version: schema.version)] = schema.name.igluSchemaURI(vendor: vendor, version: schema.version)
            } else {
                // Logged once here, where the plan is set up, as every record of such an event
                // will be skipped: setup still succeeds, since the plan may hold events the app
                // never sends here.
                Self.logger.notice("Event \(schema.name), version \(schema.version), has no Iglu schema name: every record of it will be skipped")
            }
        }
        self.schemaURIs = schemaURIs
    }

    /// `batch` as the tracker protocol's requests, each within the encoder's limit, with the
    /// records left out of them.
    ///
    /// - Parameter batch: Records of tracked events, oldest first.
    /// - Returns: The requests, in order, none when no record can be written, and each record left
    ///   out, with why (``SnowplowEncodingError``): one it can't encode, and one whose event is over
    ///   the limit's bytes for one event, or for a request of it alone
    ///   (``SnowplowEncodingError/oversized(byteCount:)``).
    /// - Complexity: O(*n* log *n*) in the batch's size, for sorting each object's members.
    public func requests(for batch: [EventRecord]) -> BatchRequests<SnowplowEncodingError> {
        limit.requests(for: batch, in: Self.envelope) { record throws(SnowplowEncodingError) in
            try json(of: record)
        } oversized: { byteCount in
            .oversized(byteCount: byteCount)
        }
    }

    private func json(of record: EventRecord) throws(SnowplowEncodingError) -> JSON {
        let version = type(of: record.event).schemaVersion
        let schemaURI = schemaURIs[SchemaKey(name: record.name, version: version)]
        let properties: [String: JSON]
        do {
            // Never a Sensitive value: Snowplow's warehouse is a store of its own, whatever the
            // record reveals.
            properties = try reader.properties(of: record, includingSensitiveValues: false)
        } catch {
            // An event Iglu can't name is reported before the reader's other reasons, but after an
            // event the plan doesn't describe.
            if case .unknownEvent = error {} else if schemaURI == nil {
                throw .invalidSchemaKey(name: record.name, version: version)
            }
            throw SnowplowEncodingError(error)
        }
        guard let schemaURI else {
            throw .invalidSchemaKey(name: record.name, version: version)
        }
        let seconds = record.timestamp.timeIntervalSince1970
        // A comparison that is false for NaN, so NaN and both infinities fall outside too.
        guard seconds >= Self.earliestSeconds, seconds < Self.endSeconds else {
            throw .unrepresentableTimestamp
        }
        let milliseconds: Int64
        do {
            milliseconds = try record.timestamp.millisecondsSince1970()
        } catch {
            // Unreached: every time from year 0 to 9999 has a millisecond count in Int64. The
            // catch keeps the reason the guard gives, should the two ranges ever part.
            throw .unrepresentableTimestamp
        }
        let event = JSON.selfDescribing(
            "iglu:com.snowplowanalytics.snowplow/unstruct_event/jsonschema/1-0-0",
            data: .selfDescribing(schemaURI, data: .object(properties)))
        var payload: [String: JSON] = [
            "aid": .string(appID),
            "dtm": .string(String(milliseconds)),
            "e": .string("ue"),
            "eid": .string(record.deduplicationID),
            // The collector records no address for a request with SP-Anonymous, which the
            // factory sends; 0.0.0.0, which Snowplow takes in place of the request's, covers a
            // proxy that drops the header field.
            "ip": .string("0.0.0.0"),
            "p": .string(record.snowplowPlatform),
            // The true timestamp, so derived_tstamp is when the event was tracked: Snowplow would
            // otherwise take the collector's time, hours late for a record a store kept offline.
            "ttm": .string(String(milliseconds)),
            "tv": .string("traffluent"),
            // ue_pr and co, JSON as text, rather than ue_px and cx, base64, which adds a third: more
            // events fit in a request, and the body stays readable. Base64's URL safety, which
            // Snowplow's docs recommend it for, matters only to GET.
            "ue_pr": .string(event.minified),
        ]
        // D4: the session is the only identifier sent. A record without one is sent without a
        // sid, rather than under an identifier made up for it: Snowplow needs none.
        if case .session(let session) = record.pseudonymousIdentity {
            payload["sid"] = .string(session.uuidString.lowercased())
        }
        let entities = record.snowplowEntities
        if !entities.isEmpty {
            payload["co"] = .string(JSON.selfDescribing("iglu:com.snowplowanalytics.snowplow/contexts/jsonschema/1-0-1", data: .array(entities)).minified)
        }
        return .object(payload)
    }
}

/// An event's name and version, which the plan holds one schema of.
private struct SchemaKey: Hashable {
    let name: String
    let version: Int
}

extension SnowplowEncodingError {
    /// The reason the property reader gave, as this encoder's.
    fileprivate init(_ error: PropertyReadingError) {
        switch error {
        case .unknownEvent(let name, let version): self = .unknownEvent(name: name, version: version)
        case .notEncodable(let name): self = .notEncodable(name: name)
        case .unrepresentableValue(let event, let property): self = .unrepresentableValue(event: event, property: property)
        }
    }
}
