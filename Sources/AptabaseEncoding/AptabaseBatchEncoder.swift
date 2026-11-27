public import Events
public import Foundation
public import HTTPDestinations
import JSONValues
import Logging
import Synchronization
public import PropertyJSON
public import TrackingPlans

/// The ``/HTTPDestinations/BatchEncoder`` of Aptabase's events API, so an `HTTPDestination` can
/// send events to an Aptabase app's `POST /api/v0/events`.
///
/// Make the destination with ``HTTPDestinations/HTTPDestination/aptabase(appKey:host:isDebug:plan:backoff:clock:now:)``,
/// which fills in the endpoint, the app key's header field, this encoder and its limits:
///
/// ```swift
/// let aptabase = try HTTPDestination.aptabase(
///     appKey: appKey,  // from the app's Instructions page: A-EU-…, A-US-… or A-SH-…
///     isDebug: false,  // true for builds whose events only Debug mode should show
///     plan: plan)
/// ```
///
/// The body is a JSON array, of content type `application/json`, of one event per record, oldest
/// first. Each event is an object of these members:
///
/// | Member | Holds |
/// |---|---|
/// | `eventName` | The event's `Event/name`, as it is |
/// | `sessionId` | The record's session, its `SessionKey`, as a lowercase UUID string; the record's own `EventRecord/id` the same way when its context has no session |
/// | `props` | The event's stored properties, flattened; left out when there are none |
/// | `systemProps` | The standard context, `isDebug` and `sdkVersion` |
/// | `timestamp` | When the event was tracked, in ISO 8601, in UTC with milliseconds |
///
/// `systemProps` holds `osName` and `osVersion` from `OperatingSystemKey`, `appVersion` and
/// `appBuildNumber` from `ApplicationKey`, `deviceModel` from `DeviceKey`, and `locale`, the
/// `LocaleKey`'s language and region (`en-US`), each left out when the context has no value for it;
/// `isDebug`, as the encoder is made with; and `sdkVersion`, which Aptabase requires, always
/// `Traffluent`. A member longer than Aptabase takes (30 characters of the system's name, 100 of
/// its version, 50 of the app's version, 20 of its build and 100 of the device's model, counted
/// in UTF-16) is left out and the event is sent without it, as Aptabase refuses the whole request
/// holding one. The encoder logs a notice the first time it leaves out each member.
///
/// The session is the only identifier sent: Aptabase has no member for a user or a device. A
/// record with no session (one tracked by a tracker without `Enricher.sessions()`, or one a store
/// recovered after a relaunch, which keeps no context) is a session of its own: Aptabase takes no
/// event without a session. The record's vendor identifier, trace context and other context
/// values aren't sent. Aptabase counts users itself, from a hash of each request's IP address and
/// `User-Agent` header field with a salt it changes every day.
///
/// Properties are read through the event's schema in `plan`, as `PropertyReader` reads them. A
/// ``/Events/Sensitive`` value is never sent, whatever the record reveals: the property is left
/// out, and so is an element of an array. Aptabase stores a string, a number or a boolean as a
/// property's value, and only a placeholder for an object or array, so an object or array is
/// spread into a property per value it holds, named after its path, joined by `.` (`cart.size`,
/// `tags.0`), and a `null` is left out.
///
/// A record the encoder can't write is left out of the request, and the batch's other records are
/// sent: one whose event and version `plan` doesn't describe; one whose event name is only
/// whitespace or over 60 characters; one with a property whose name, once flattened, is empty, only
/// whitespace or over 40 characters, whose string value is over 180 characters, or whose number is
/// too large for Aptabase; one whose values flatten to one name; one whose event isn't
/// `Encodable`; one that holds a value
/// JSON can't; one whose timestamp is outside the years 1 to 9999, or more than 23 hours before
/// the batch is encoded; and one too large for a request (``AptabaseEncodingError``).
/// ``requests(for:)`` returns them as `SkippedRecord`s, which `HTTPDestination` logs and reports
/// on its `dropReports`.
///
/// ``requests(for:)`` splits a batch into requests within the encoder's limit, ``batchLimit`` by
/// default, gives each a deadline 23 hours after its oldest record was tracked, and makes none for
/// a batch with no record it can write, so `HTTPDestination` sends nothing for it. Aptabase
/// doesn't remove duplicates, so a record sent again, after a retry whose answer was lost or a
/// store's redelivery, is counted twice. The bytes are the same for the same records on every run
/// and platform: no whitespace, object members in the order of their names' UTF-8 bytes.
public struct AptabaseBatchEncoder: BatchEncoder {
    // From Aptabase's server, github.com/aptabase/aptabase at 89d36185, read on 2026-11-27:
    // - src/Features/Ingestion/EventsController.cs: POST /api/v0/events takes a JSON array of
    //   EventBody, answers 400 for more than 25, drops each event IsValid refuses with a log and
    //   answers 200 for the rest; [ApiController] model validation answers 400 for the whole
    //   request when one event breaks an attribute; a number property is read with GetDecimal,
    //   which throws past a decimal's range, a 500 from ExceptionMiddleware.
    // - src/Features/Ingestion/EventBody.cs: EventName [Required, StringLength(60)]; SessionId
    //   [Required], at most 36 characters unless it parses as a ulong (then checked as the SDKs'
    //   epoch-seconds form, within 7 days); Timestamp clamped to the server's now, and IsValid
    //   drops one older than DateTime.UtcNow.AddDays(-1); props an object, keys not
    //   IsNullOrWhiteSpace and at most 40 characters; SplitProps stores numbers as numeric props,
    //   strings cut to 180, true and false as strings, an array as "[Array]", an object as
    //   "{Object}" and null as "".
    // - src/Features/Ingestion/ResolveAppKeyAttribute.cs: a missing, unknown or locked key is
    //   answered 200 with the events dropped. src/Program.cs: 20 requests a second per client IP,
    //   429 past it; Kestrel's default body limit, 30,000,000 bytes, unchanged.
    // - src/Features/Privacy/DailyUserHasher.cs: the user ID is a SipHash of the client IP and
    //   User-Agent with a salt per app and day. Its tests (tests/IntegrationTests/IngestionTests.cs)
    //   ingest UUID session IDs.
    // The wiki's "How to build your own SDK" (github.com/aptabase/aptabase/wiki) says the batch
    // limit is 25 and that a session ID "must be" epoch seconds and 8 random digits; the server
    // takes any string of up to 36 characters, as its own tests send UUIDs.
    /// Aptabase's limits on one request: 25 events, and 1,000,000 bytes of body and of one event.
    ///
    /// Aptabase's events API refuses a request of more than 25 events. Its server takes a body of
    /// up to 30,000,000 bytes; the 1,000,000 bytes stay under the 1 MiB that nginx, in front of
    /// many self-hosted servers, takes in a body by default. An event's strings are each at most
    /// 180 characters, so only an event of many properties comes near it.
    public static let batchLimit = (try? BatchLimit(maximumRecordCount: 25, maximumByteCount: 1_000_000, maximumRecordByteCount: 1_000_000)) ?? .unlimited

    // src/Extensions/ExceptionMiddleware.cs (89d36185, read 2026-11-27) answers 418 for Kestrel's
    // BadHttpRequestException, which src/Program.cs's MinRequestBodyDataRate raises for a body
    // slower than 60 bytes a second after a 10-second grace period, and for a request the client
    // aborted: a slow link, which a later attempt may not have.
    /// The status Aptabase answers that `HTTPDestination` retries, beside 408, 429 and every 5xx:
    /// 418, which Aptabase answers when a request's body arrives slower than 60 bytes a second
    /// after a 10-second grace period, as over a poor connection.
    ///
    /// A request answered with it is sent again on the destination's backoff, until it is taken
    /// or its deadline passes.
    public static let transientStatuses: Set<TransientStatus> = {
        // 418 is a client error, which TransientStatus always takes, so the set always holds it;
        // a test pins it. Rejected: a non-throwing TransientStatus spelling for literals, which
        // would trap on a literal outside 400 through 599.
        guard let slowUpload = try? TransientStatus(418) else { return [] }
        return [slowUpload]
    }()

    /// What every event's `systemProps.sdkVersion` says, which Aptabase requires and keeps with
    /// each event: the library's name, as no constant holds its version.
    static let sdkVersion = "Traffluent"

    /// How long before a batch is encoded, or before its request is sent, a record may have been
    /// tracked, in seconds: 23 hours. Aptabase takes an event up to a day old; the hour to spare is
    /// for a queue on the server and clocks that disagree.
    private static let windowSeconds: TimeInterval = 23 * 60 * 60

    /// ``windowSeconds`` as the maximum age of a request's oldest record.
    private static let window: Duration = .seconds(windowSeconds)

    /// The seconds from 1970 to 0001-01-01T00:00:00Z: an earlier timestamp is no .NET `DateTime`.
    private static let earliestSeconds: Double = -62_135_596_800

    /// The seconds from 1970 to 10000-01-01T00:00:00Z: a timestamp from then on is no .NET
    /// `DateTime`.
    private static let endSeconds: Double = 253_402_300_800

    /// 2⁹⁶: a number of this magnitude or more is past a .NET `decimal`, whose largest value is
    /// 2⁹⁶ − 1. Every `Double` below it is within one.
    private static let decimalBound: Double = 79_228_162_514_264_337_593_543_950_336

    /// The most characters Aptabase takes of each system property the context gives, by name.
    /// The locale always fits, as the encoder writes it.
    private static let systemPropertyLengths: [String: Int] = ["osName": 30, "osVersion": 100, "appVersion": 50, "appBuildNumber": 20, "deviceModel": 100]

    private static let logger = Logger(label: "AptabaseEncoding.AptabaseBatchEncoder")

    /// The system properties this encoder has logged a notice for leaving out.
    private let noticedSystemProperties = NoticedSystemProperties()

    private let reader: PropertyReader
    private let limit: BatchLimit
    private let now: @Sendable () -> Date
    private let isDebug: Bool

    /// Why a record was left out of the batch's requests.
    public typealias Failure = AptabaseEncodingError

    /// An encoder of the events `plan` describes, marking every event as a debug event or not as
    /// `isDebug` says, splitting each batch to `limit`, leaving out records more than 23 hours
    /// older than `now` gives.
    ///
    /// - Parameters:
    ///   - isDebug: Whether every event is a debug event, which Aptabase's dashboard shows only in
    ///     its Debug mode, apart from the app's users' events: `true` for a development or internal
    ///     build, `false` for one users run.
    ///   - plan: The tracking plan of every event the encoder is given: each record's event is
    ///     read through the schema of its name and `Event/schemaVersion` here.
    ///   - limit: The most each request holds; ``batchLimit`` by default.
    ///   - now: The wall-clock time a batch is encoded at, read once a batch; the system's clock by
    ///     default. When it reads NaN or infinite, every record is left out.
    ///
    /// The encoder logs a notice for each event and property of `plan` named as Aptabase refuses,
    /// as it will skip records of that event (``AptabaseEncodingError``).
    public init(isDebug: Bool, plan: TrackingPlan, limit: BatchLimit = AptabaseBatchEncoder.batchLimit, now: @escaping @Sendable () -> Date = { Date.now }) {
        reader = PropertyReader(plan: plan)
        self.limit = limit
        self.now = now
        self.isDebug = isDebug
        // Logged once here, where the plan is set up, as records of such an event will be
        // skipped: setup still succeeds, since the plan may hold events the app never sends here.
        for schema in plan.schemas {
            if !schema.name.isAptabaseEventName {
                Self.logger.notice("Aptabase refuses the name of event \(schema.name), version \(schema.version): every record of it will be skipped")
            }
            for property in schema.properties where !property.name.fitsAptabasePropertyName {
                Self.logger.notice("Aptabase refuses the name of property \(property.name) of event \(schema.name), version \(schema.version): its records will be skipped")
            }
        }
    }

    /// `batch` as the requests Aptabase takes, each within the encoder's limit and with a deadline
    /// 23 hours after its oldest record was tracked, with the records left out of them.
    ///
    /// - Parameter batch: Records of tracked events, oldest first.
    /// - Returns: The requests, in order, none when no record can be written, and each record left
    ///   out, with why (``AptabaseEncodingError``): one it can't encode, one past Aptabase's rules
    ///   or its window of time, and one too large for a request of it alone
    ///   (``AptabaseEncodingError/oversized(byteCount:)``).
    /// - Complexity: O(*n* log *n*) in the batch's size, for sorting each object's members.
    public func requests(for batch: [EventRecord]) -> BatchRequests<AptabaseEncodingError> {
        let encodedAt = now()
        let encoding = { (record: EventRecord) throws(AptabaseEncodingError) -> JSON in
            try json(of: record, encodedAt: encodedAt)
        }
        let oversized = { (byteCount: Int) -> AptabaseEncodingError in
            .oversized(byteCount: byteCount)
        }
        do {
            // Each request's deadline is its oldest record's 23 hours, as Aptabase checks an
            // event's age when the request arrives, and a retry only ever arrives later.
            return try limit.requests(for: batch, in: .array, maximumAge: Self.window, encoding: encoding, oversized: oversized)
        } catch {
            // Never reached: the window is a positive constant, and only a negative age throws.
            // Requests without a deadline rather than a trap (D10).
            return limit.requests(for: batch, in: .array, encoding: encoding, oversized: oversized)
        }
    }

    private func json(of record: EventRecord, encodedAt: Date) throws(AptabaseEncodingError) -> JSON {
        let read: [String: JSON]
        do {
            // Never a Sensitive value: Aptabase is a store the app doesn't control, whatever the
            // record reveals.
            read = try reader.properties(of: record, includingSensitiveValues: false)
        } catch {
            // The event's name is reported before the reader's other reasons, but after an event
            // the plan doesn't describe.
            if case .unknownEvent = error {} else {
                try record.checkAptabaseName()
            }
            throw AptabaseEncodingError(error)
        }
        try record.checkAptabaseName()
        let properties: [String: JSON]
        do {
            // `.`, as the sibling encoders join a path. Aptabase stores an array as "[Array]" and
            // an object as "{Object}", losing what they hold, and a null as an empty string.
            properties = try read.flattened(separator: ".").filter { $0.value != .null }
        } catch {
            throw .propertyNameCollision(event: record.name, property: error.key)
        }
        // In order, so of two names that break a rule, the error always names the same one.
        let names = properties.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        if let empty = names.first(where: \.isBlank) {
            throw .emptyPropertyName(event: record.name, property: empty)
        }
        if let long = names.first(where: { !$0.fitsAptabasePropertyName }) {
            throw .propertyNameTooLong(event: record.name, property: long)
        }
        for name in names {
            switch properties[name] {
            case .string(let value) where !value.fitsAptabasePropertyValue:
                throw .propertyValueTooLong(event: record.name, property: name, length: value.utf16.count)
            // A comparison that is false for NaN, though the reader never gives one.
            case .number(let value) where !(value.magnitude < Self.decimalBound):
                throw .numberOutOfRange(event: record.name, property: name)
            default:
                break
            }
        }
        // A member too long is left out rather than the record: the standard context is the
        // install's, so a build number past 20 characters would skip every event the build sends,
        // and Aptabase takes an event without any of them. Rejected: skipping the record.
        let system = record.aptabaseSystemProperties.filter { name, value in
            guard let maximum = Self.systemPropertyLengths[name], value.utf16.count > maximum else { return true }
            if noticedSystemProperties.insert(name) {
                Self.logger.notice("Aptabase takes at most \(maximum) characters of the system property \(name), and the context gives \(value.utf16.count): it is left out of every event")
            }
            return false
        }
        let seconds = record.timestamp.timeIntervalSince1970
        // A comparison that is false for NaN, so NaN and both infinities fall outside too.
        guard seconds >= Self.earliestSeconds, seconds < Self.endSeconds else {
            throw .unrepresentableTimestamp
        }
        // Measured from when the batch is encoded: Aptabase answers 200 for a request whose event
        // it drops for its age, so a record past the window would be acknowledged and deleted
        // without being stored. Only the past side: Aptabase stores an event from the future at
        // the time it arrives. The timestamp is finite here, so the offset is NaN or infinite
        // only for a `now` that is, and every record is then reported (D10). Rejected: leaving
        // such a clock to Aptabase, which would drop the records it refuses without a report.
        let offset = record.timestamp.timeIntervalSince(encodedAt)
        guard offset >= -Self.windowSeconds, offset.isFinite else {
            throw .timestampOutsideWindow
        }
        let timestamp: String
        do {
            timestamp = try record.timestamp.iso8601Timestamp
        } catch {
            // Unreached: every four-digit year has a millisecond count in Int64. The catch keeps
            // the reason the guard gives, should the two ranges ever part.
            throw .unrepresentableTimestamp
        }
        var systemProperties = system.mapValues(JSON.string)
        systemProperties["isDebug"] = .boolean(isDebug)
        systemProperties["sdkVersion"] = .string(Self.sdkVersion)
        // D4: the session is the only identifier sent. A record without one (a recovered record
        // keeps no context) becomes its own session rather than being skipped, which would let
        // the delivery acknowledge it and the store delete it, or sent without a sessionId, which
        // Aptabase refuses with the whole request. Its lowercase UUID, 36 characters, the most
        // Aptabase takes of a session ID that isn't a number. Rejected: the SDKs' numeric form
        // (epoch seconds and 8 random digits), which Aptabase checks to be within 7 days, so a
        // session open longer would lose its events without a report, and which a record's own
        // random ID has no time for.
        var event: [String: JSON] = [
            "eventName": .string(record.name),
            "sessionId": .string(record.pseudonymousIdentity.uuid.uuidString.lowercased()),
            "systemProps": .object(systemProperties),
            // The record's own time, so a record a store kept offline for hours keeps its hour.
            "timestamp": .string(timestamp),
        ]
        if !properties.isEmpty {
            event["props"] = .object(properties)
        }
        return .object(event)
    }
}

extension AptabaseEncodingError {
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
    /// Throws when Aptabase refuses the event's name: only whitespace, or over 60 characters.
    fileprivate func checkAptabaseName() throws(AptabaseEncodingError) {
        guard name.isAptabaseEventName else {
            throw .invalidEventName(name: name)
        }
    }
}

/// The system properties an encoder has logged a notice for leaving out. Its copies share one, so
/// a build whose context holds a member too long logs it once rather than on every record.
///
/// A `Mutex` rather than an actor: `AptabaseBatchEncoder.requests(for:)` is synchronous, and the
/// lock is taken only for a member too long.
private final class NoticedSystemProperties: Sendable {
    private let names = Mutex<Set<String>>([])

    /// Records `name`, returning whether it wasn't recorded before.
    func insert(_ name: String) -> Bool {
        names.withLock { $0.insert(name).inserted }
    }
}
