import Crypto
public import Events
import Foundation
public import HTTPDestinations
import JSONValues
import Logging
public import PropertyJSON
public import TrackingPlans

/// The ``/HTTPDestinations/BatchEncoder`` of TelemetryDeck's Ingest API v3, so an `HTTPDestination`
/// can send events to an organization's `POST /v3/<namespace>/`.
///
/// Make the destination with
/// ``HTTPDestinations/HTTPDestination/telemetryDeck(appID:namespace:testMode:plan:backoff:clock:)``,
/// which fills in the endpoint, this encoder and its limits:
///
/// ```swift
/// let telemetryDeck = try HTTPDestination.telemetryDeck(
///     appID: appID,  // from the app's settings in the TelemetryDeck dashboard
///     namespace: "com.example",  // your organization's namespace
///     testMode: false,  // true for builds whose signals only Test Mode should show
///     plan: plan)
/// ```
///
/// The body is a JSON array of content type `application/json`, one event per record, oldest
/// first. Each event is a flat object of these members:
///
/// | Member | Holds |
/// |---|---|
/// | `appID` | The app ID the encoder is made with, without leading or trailing whitespace |
/// | `clientUser` | The SHA256 of the record's session, its `SessionKey` as a lowercase UUID string, as 64 lowercase hexadecimal digits; of the record's own `EventRecord/id` the same way when its context has no session |
/// | `isTestMode` | `"true"` or `"false"`, as the encoder is made with |
/// | `receivedAt` | When the event was tracked, in ISO 8601, in UTC with milliseconds |
/// | `sessionID` | The record's session, its `SessionKey`, as a lowercase UUID string; left out when its context has no session |
/// | `type` | The event's `Event/name`, as it is |
/// | `TelemetryDeck.SDK.name` | `Traffluent` |
/// | Each of the event's stored properties | Its value, read through the event's schema in the plan; a nested value spread into one member per scalar it holds, named after its path, joined by `.` (`cart.size`, `tags.0`) |
///
/// The session is the only identifier sent, hashed as TelemetryDeck's SDKs hash a user's
/// identifier with their default, empty salt; TelemetryDeck salts and hashes it again before
/// storing it. No salt of the app's own is taken: `sessionID` sends the same session in the
/// clear, so a salt would hide nothing. TelemetryDeck counts a user per `clientUser`, so its users
/// are sessions. A record with no session (one tracked by a tracker without `Enricher.sessions()`,
/// or one a store recovered after a relaunch, which keeps no context) is its own user of one event, with no `sessionID`, linked to nothing: TelemetryDeck
/// refuses an event without a `clientUser`. The record's vendor identifier and trace context, and
/// any other context value, aren't sent. Nor is a `floatValue`: a number among the properties
/// keeps its JSON type in Ingest API v3.
///
/// Properties are read through the event's schema in `plan`, as `PropertyReader` reads them. A
/// ``/Events/Sensitive`` value is never sent, whatever the record reveals: the property is left
/// out, and so is an element of an array. A `null` is left out too, as TelemetryDeck stores no
/// value for it. TelemetryDeck stores a nested object without indexing it and leaves arrays
/// undefined, so the encoder spreads both into members of their own.
///
/// Each event also holds these of TelemetryDeck's built-in parameters, for each of the keys the
/// record's context has a value for:
///
/// | Parameter | Key | Holds |
/// |---|---|---|
/// | `TelemetryDeck.AppInfo.version`, `TelemetryDeck.AppInfo.buildNumber` | `ApplicationKey` | The version and the build, each left out when `nil` |
/// | `TelemetryDeck.AppInfo.versionAndBuildNumber` | `ApplicationKey`, with both a version and a build | `2.4.1 (build 418)` |
/// | `TelemetryDeck.Device.modelName` | `DeviceKey` | The model |
/// | `TelemetryDeck.Device.operatingSystem`, `TelemetryDeck.Device.platform` | `OperatingSystemKey` | The operating system's name, `iOS` |
/// | `TelemetryDeck.Device.systemVersion`, `TelemetryDeck.Device.systemMajorVersion`, `TelemetryDeck.Device.systemMajorMinorVersion` | `OperatingSystemKey`, with a version | The name and the version, its first component and its first two: `iOS 26.1.0`, `iOS 26`, `iOS 26.1` |
/// | `TelemetryDeck.RunContext.locale` | `LocaleKey` | The locale's identifier, `en_US` |
/// | `TelemetryDeck.RunContext.language` | `LocaleKey`, with a language | The language's code, `en` |
/// | `TelemetryDeck.UserPreference.region` | `LocaleKey`, with a region | The region's code, `US` |
///
/// A record the encoder can't write is left out of the request, and the batch's other records are
/// sent: one whose event and version `plan` doesn't describe, one whose event name or parameter
/// name TelemetryDeck refuses or keeps for itself, one whose values flatten to one name, one whose
/// event isn't `Encodable`, one that holds a value JSON can't, one whose timestamp is outside the
/// years 1 to 9999, and one whose JSON is over 333,333 bytes (``TelemetryDeckEncodingError``).
/// ``requests(for:)`` returns them as `SkippedRecord`s, which `HTTPDestination` logs and reports
/// on its `dropReports`.
///
/// ``requests(for:)`` splits a batch into requests within the encoder's limit, ``batchLimit`` by
/// default, and makes none for a batch with no record it can write, so `HTTPDestination` sends
/// nothing for it. TelemetryDeck answers a request it takes with 200, and checks every event of a
/// request before storing any: it answers 422 when one breaks a rule, which `HTTPDestination`
/// drops and reports with every record of the request. It answers 503 when its queue is full,
/// which `HTTPDestination` retries. It doesn't remove duplicates, so a record sent again is
/// counted again. The bytes are the same for the same records on every run and platform: no
/// whitespace, object members in the order of their names' UTF-8 bytes.
public struct TelemetryDeckBatchEncoder: BatchEncoder {
    /// No status beyond the 408, 429 and 5xx that `HTTPDestination` retries for every encoder.
    public static let transientStatuses: Set<TransientStatus> = []

    // From TelemetryDeck's docs, read on 2026-11-27 (their source, github.com/TelemetryDeck/docs at
    // 1389edf3):
    // - Ingest API v3, https://telemetrydeck.com/docs/ingest/v3/ (POST /v3/{namespace}/, an array
    //   of flat events; appID, clientUser and receivedAt required strings; isTestMode a string;
    //   values keep their JSON type; nested objects not indexed and arrays undefined; "Each event
    //   may be at most 1,000,000 bytes when serialized as JSON. A larger event rejects the whole
    //   batch"; 200 with the count, 422 for any invalid event, nothing stored; 503 with
    //   Retry-After: 5; clientUser "Replaced by the salted SHA256 hash of the value you sent").
    // - Ingest API v2, https://telemetrydeck.com/docs/ingest/v2/ ("we're officially recommending
    //   our customers to use the v3 API"; v2 moves a receivedAt more than 24 hours old to 24
    //   hours ago, turns booleans into strings and renames keys it can't store).
    // - Default parameters, https://telemetrydeck.com/docs/ingest/default-parameters/, and
    //   User Identification, https://telemetrydeck.com/docs/sdk/official-sdk/swift/swift-user-identification/
    //   ("The hash input is identifier + salt ... a 64-character lowercase hex string").
    // And from TelemetryDeck's SwiftSDK, github.com/TelemetryDeck/SwiftSDK 2.14.2 and
    // 3.0.0-beta.7: CryptoHashing.sha256(string:salt:), SHA256 of (identifier + salt) in UTF-8,
    // the salt empty by default, in lowercase hex; SignalCache pops 100 signals a request. The endpoint, the same day, parsed
    // `2026-11-27T10:00:00.123Z` and `0001-01-01T00:00:00.000Z` as a receivedAt and refused
    // `0000-12-31T23:59:59.999Z`, and took a 5 MB body as far as its checks.
    /// TelemetryDeck's limits on one request: 100 events and 1,000,000 bytes of body, and 333,333
    /// bytes of one event.
    ///
    /// The 100 events are what TelemetryDeck's SwiftSDK sends in a request. The 333,333 bytes of an
    /// event are a third of Ingest API v3's limit: TelemetryDeck refuses a whole request when one
    /// event's JSON is over 1,000,000 bytes as its server writes it, which may be larger than the
    /// encoder's, and a third leaves room for the escapes a re-encoder commonly adds, such as `\u`
    /// and four hex digits for a character outside ASCII, and a space after each `:` and `,`. A
    /// larger event is left out as ``TelemetryDeckEncodingError/oversized(byteCount:)``.
    /// TelemetryDeck documents no limit on a request; its 1,000,000 bytes are the encoder's own
    /// bound, the most one event may be, which keeps a request to a size a retry can send again.
    public static let batchLimit = (try? BatchLimit(maximumRecordCount: 100, maximumByteCount: 1_000_000, maximumRecordByteCount: 333_333)) ?? .unlimited

    /// The seconds from 1970 to 0001-01-01T00:00:00Z: TelemetryDeck refuses an earlier
    /// `receivedAt`.
    private static let earliestSeconds: Double = -62_135_596_800

    /// The seconds from 1970 to 10000-01-01T00:00:00Z: a timestamp from then on has no four-digit
    /// ISO 8601 year, which TelemetryDeck's parser needs.
    private static let endSeconds: Double = 253_402_300_800

    private static let logger = Logger(label: "TelemetryDeckEncoding.TelemetryDeckBatchEncoder")

    private let reader: PropertyReader
    private let limit: BatchLimit
    private let appID: String
    private let isTestMode: String

    /// Why a record was left out of the batch's requests.
    public typealias Failure = TelemetryDeckEncodingError

    /// An encoder of the events `plan` describes, for the TelemetryDeck app `appID`, marking every
    /// event as a test event or not as `testMode` says,
    /// and splitting each batch to `limit`.
    ///
    /// - Parameters:
    ///   - appID: The app's ID, from its settings in the TelemetryDeck dashboard: public, as every
    ///     TelemetryDeck client sends it.
    ///   - testMode: Whether every event is a test event, which TelemetryDeck's dashboard shows only
    ///     in Test Mode, apart from the app's users' events: `true` for a development or internal
    ///     build, `false` for one users run.
    ///   - plan: The tracking plan of every event the encoder is given: each record's event is
    ///     read through the schema of its name and `Event/schemaVersion` here.
    ///   - limit: The most each request holds; ``batchLimit`` by default.
    /// - Throws: ``TelemetryDeckSetupError/emptyAppID`` for an app ID that is empty or only
    ///   whitespace.
    ///
    /// The encoder logs a notice for each event and property of `plan` named as TelemetryDeck
    /// refuses, or keeps for itself, as it will skip records of that event
    /// (``TelemetryDeckEncodingError``).
    public init(appID: String, testMode: Bool, plan: TrackingPlan, limit: BatchLimit = TelemetryDeckBatchEncoder.batchLimit) throws(TelemetryDeckSetupError) {
        // Trimmed, as an ID pasted from a configuration file often ends in a newline, which
        // TelemetryDeck would store as part of the ID, under no app.
        let appID = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appID.isEmpty else { throw .emptyAppID }
        reader = PropertyReader(plan: plan)
        self.limit = limit
        self.appID = appID
        isTestMode = testMode ? "true" : "false"
        // Logged once here, where the plan is set up, as records of such an event will be
        // skipped: setup still succeeds, since the plan may hold events the app never sends here.
        for schema in plan.schemas {
            if !schema.name.isTelemetryDeckName || schema.name.isInTelemetryDeckScope {
                Self.logger.notice("TelemetryDeck refuses or reserves the name of event \(schema.name), version \(schema.version): every record of it will be skipped")
            }
            for property in schema.properties where !property.name.isTelemetryDeckName || property.name.isReservedByTelemetryDeck {
                Self.logger.notice("TelemetryDeck refuses or reserves the name of property \(property.name) of event \(schema.name), version \(schema.version): its records will be skipped")
            }
        }
    }

    /// `batch` as the requests TelemetryDeck takes, each within the encoder's limit, with the
    /// records left out of them.
    ///
    /// - Parameter batch: Records of tracked events, oldest first.
    /// - Returns: The requests, in order, none when no record can be written, and each record left
    ///   out, with why (``TelemetryDeckEncodingError``): one it can't encode, one past
    ///   TelemetryDeck's rules, and one whose event is over the limit's bytes for one event, or for
    ///   a request of it alone (``TelemetryDeckEncodingError/oversized(byteCount:)``).
    /// - Complexity: O(*n* log *n*) in the batch's size, for sorting each object's members.
    public func requests(for batch: [EventRecord]) -> BatchRequests<TelemetryDeckEncodingError> {
        limit.requests(for: batch, in: .array) { record throws(TelemetryDeckEncodingError) in
            try json(of: record)
        } oversized: { byteCount in
            .oversized(byteCount: byteCount)
        }
    }

    private func json(of record: EventRecord) throws(TelemetryDeckEncodingError) -> JSON {
        let properties: [String: JSON]
        do {
            // Never a Sensitive value: TelemetryDeck is a vendor's store, whatever the record
            // reveals.
            properties = try reader.properties(of: record, includingSensitiveValues: false)
        } catch {
            // The event's name is reported before the reader's other reasons, but after an event
            // the plan doesn't describe.
            if case .unknownEvent = error {} else {
                try record.checkTelemetryDeckName()
            }
            throw TelemetryDeckEncodingError(error)
        }
        try record.checkTelemetryDeckName()
        var event: [String: JSON]
        do {
            // `.`, the separator of TelemetryDeck's own scopes (`TelemetryDeck.Device.modelName`).
            // A null carries nothing TelemetryDeck stores, and v3 leaves arrays undefined.
            event = try properties.flattened(separator: ".").filter { $0.value != .null }
        } catch {
            throw .parameterNameCollision(event: record.name, parameter: error.key)
        }
        // In order, so of two names that break a rule, the error always names the same one.
        // Checked before the encoder's own members are added, which are all reserved names.
        let names = event.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        if let invalid = names.first(where: { !$0.isTelemetryDeckName }) {
            throw .invalidParameterName(event: record.name, parameter: invalid)
        }
        if let reserved = names.first(where: \.isReservedByTelemetryDeck) {
            throw .reservedParameterName(event: record.name, parameter: reserved)
        }
        let seconds = record.timestamp.timeIntervalSince1970
        // A comparison that is false for NaN, so NaN and both infinities fall outside too.
        guard seconds >= Self.earliestSeconds, seconds < Self.endSeconds else {
            throw .unrepresentableTimestamp
        }
        let receivedAt: String
        do {
            receivedAt = try record.timestamp.iso8601Timestamp
        } catch {
            // Unreached: every four-digit year has a millisecond count in Int64. The catch keeps
            // the reason the guard gives, should the two ranges ever part.
            throw .unrepresentableTimestamp
        }
        for (name, value) in record.telemetryDeckContext {
            event[name] = value
        }
        // D4: the session is the only identifier sent. A record without one (a recovered record
        // keeps no context) becomes its own user rather than being skipped, which would let the
        // delivery acknowledge it and the store delete it, or sent without a clientUser, which
        // TelemetryDeck refuses with the whole request. It gets no sessionID: Ingest API v3
        // stores none it isn't sent, where a made-up one would count a session that never was.
        let identity = record.pseudonymousIdentity
        let identifier = identity.uuid.uuidString.lowercased()
        if case .session = identity {
            event["sessionID"] = .string(identifier)
        }
        event["appID"] = .string(appID)
        event["clientUser"] = .string(identifier.sha256Hex)
        event["isTestMode"] = .string(isTestMode)
        // Required by Ingest API v3, which stores it as sent: the record's own time, so a record
        // a store kept offline for days keeps its day.
        event["receivedAt"] = .string(receivedAt)
        event["type"] = .string(record.name)
        event["TelemetryDeck.SDK.name"] = .string("Traffluent")
        return .object(event)
    }
}

extension TelemetryDeckEncodingError {
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
    /// Throws when TelemetryDeck refuses the event's name as a `type`, or keeps it for itself.
    fileprivate func checkTelemetryDeckName() throws(TelemetryDeckEncodingError) {
        guard name.isTelemetryDeckName else {
            throw .invalidEventName(name: name)
        }
        guard !name.isInTelemetryDeckScope else {
            throw .reservedEventName(name: name)
        }
    }
}

extension String {
    /// The SHA256 of the string's UTF-8, as 64 lowercase hexadecimal digits: how TelemetryDeck's
    /// SDKs write a hashed user identifier.
    fileprivate var sha256Hex: String {
        let digits = Array("0123456789abcdef".utf8)
        var text: [UInt8] = []
        text.reserveCapacity(64)
        for byte in SHA256.hash(data: Data(utf8)) {
            text.append(digits[Int(byte >> 4)])
            text.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: text, as: UTF8.self)
    }
}
