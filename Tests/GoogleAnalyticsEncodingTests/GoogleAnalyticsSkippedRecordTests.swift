// The module is compiled for macOS and Linux alone (Sources/GoogleAnalyticsEncoding).
#if os(macOS) || os(Linux)
import EventMacros
import Foundation
import GoogleAnalyticsEncoding
import HTTPDestinations
import Instrumentation
import Persistence
import Sessions
import Synchronization
import Testing
import TrackingPlans

@Suite("GoogleAnalyticsBatchEncoder: skipped records")
struct GoogleAnalyticsSkippedRecordTests {
    @Event(name: "checkout_started", version: 2)
    struct CheckoutStarted {
        var cartSize: Int
    }

    @Event(name: "measured")
    struct Measured {
        var value: Double
    }

    @Event(name: "searched")
    struct Searched {
        var query: String
    }

    @Event(name: "video_watched")
    struct VideoWatched {
        var session_id: Int
        var ga_label: String
    }

    @Event(name: "redacted_session")
    struct RedactedSession {
        var session_id: Sensitive<Int>
        var count: Int
    }

    struct Cart: Codable, Hashable {
        var size: Int
    }

    @Event(name: "cart_viewed")
    struct CartViewed {
        var cart: Cart
        var cart_size: Int
    }

    struct HandWritten: Event {
        var plan: String
    }

    /// An event named by its test: a task-local, so tests running in parallel each see their own.
    struct Named: Event, Codable {
        @TaskLocal static var testName = "named"

        static var name: String { testName }

        init() {}
    }

    /// An event of the properties its test gives, by name, which only a hand-written `Encodable`
    /// conformance can write when a name isn't a Swift identifier.
    struct PropertiesNamed: Event, Encodable {
        static let name = "properties_named"

        struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }

            init(stringValue: String) {
                self.stringValue = stringValue
            }

            init?(intValue: Int) {
                nil
            }
        }

        var properties: [String: String]

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            for (name, value) in properties {
                try container.encode(value, forKey: Key(stringValue: name))
            }
        }
    }

    /// Encodes as a bare integer rather than a map of its properties.
    struct NotAMap: Event, Encodable {
        static let name = "not_a_map"

        init() {}

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(1)
        }
    }

    @Test("A record whose event the plan doesn't describe is left out as unknownEvent, and the records around it are sent")
    func unknownEvent() throws {
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        let skipped = EventRecord(event: Measured(value: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil, context: context)
        let batch = [
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context),
            skipped,
            EventRecord(event: CheckoutStarted(cartSize: 3), timestamp: Date(timeIntervalSince1970: 1_795_442_609), sourceLocation: nil, context: context),
        ]
        let expectedBody = try #require(sut.requests(for: [batch[0], batch[2]]).requests.first).body
        let expectedSkipped = [SkippedRecord<GoogleAnalyticsEncodingError>(recordID: skipped.id, eventName: "measured", schemaVersion: 1, reason: .unknownEvent(name: "measured", version: 1))]

        let actual = sut.requests(for: batch)

        #expect(actual.requests.map(\.body) == [expectedBody])
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("A record whose version the plan doesn't describe is left out as unknownEvent with its version, though the plan has its name")
    func unknownVersion() throws {
        let earlier = EventSchema(name: "checkout_started", version: 1, consentCategory: .analytics, properties: [])
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [earlier]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<GoogleAnalyticsEncodingError>(recordID: record.id, eventName: "checkout_started", schemaVersion: 2, reason: .unknownEvent(name: "checkout_started", version: 2))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record whose event isn't Encodable is left out as notEncodable")
    func notEncodable() throws {
        let handWritten = EventSchema(name: "HandWritten", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: "plan", typeName: "String", isOptional: false)])
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [handWritten]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let record = EventRecord(event: HandWritten(plan: "pro"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<GoogleAnalyticsEncodingError>(recordID: record.id, eventName: "HandWritten", schemaVersion: 1, reason: .notEncodable(name: "HandWritten"))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record holding a NaN is left out as unrepresentableValue, naming the property")
    func unrepresentableValue() throws {
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [Measured.schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let record = EventRecord(event: Measured(value: .nan), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<GoogleAnalyticsEncodingError>(recordID: record.id, eventName: "measured", schemaVersion: 1, reason: .unrepresentableValue(event: "measured", property: "value"))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record whose encoding isn't a map is left out as unrepresentableValue with no property")
    func notAMap() throws {
        let schema = EventSchema(name: "not_a_map", version: 1, consentCategory: .analytics, properties: [])
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let record = EventRecord(event: NotAMap(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = GoogleAnalyticsEncodingError.unrepresentableValue(event: "not_a_map", property: "")

        let actual = sut.requests(for: [record])

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords.map(\.reason) == [expected])
    }

    // https://developers.google.com/analytics/devguides/collection/protocol/ga4/sending-events,
    // "Limitations": 40 characters, alphanumerics and underscores, starting with a letter. The
    // validation server counts the 40 in bytes of UTF-8, takes letters of any script and, after
    // the first, numbers of any kind (Nd, Nl and No), and refuses symbols, marks, format
    // characters and punctuation but _ (2026-11-27).
    @Test("An event name of 1 to 40 bytes, starting with a letter, of letters, numbers and _ alone, is sent, and any other is left out as invalidEventName", arguments: [
        (String(repeating: "a", count: 40), false), ("a", false), ("Checkout_Started", false), ("a1_", false), ("café_open", false), ("éclair", false), ("中文", false),
        ("a٣", false), ("a²", false), ("a½", false), ("aⅣ", false), ("aǅ", false), ("aʰ", false), ("a１", false), ("a" + String(repeating: "é", count: 19) + "a", false), (String(repeating: "é", count: 20), false), ("ScreenViewed", false),
        (String(repeating: "a", count: 41), true), ("aa" + String(repeating: "é", count: 19) + "a", true), (String(repeating: "é", count: 21), true),
        ("1abc", true), ("_x", true), ("٣a", true), ("Ⅳa", true), ("²a", true), ("a©", true), ("a·", true), ("a\u{200B}", true), ("a‿", true), ("a\u{903}", true), ("a-b", true), ("a b", true), ("a.b", true), ("a$", true), ("e\u{301}x", true), ("a😀", true),
    ] as [(String, Bool)])
    func invalidEventName(name: String, invalid: Bool) throws {
        try Named.$testName.withValue(name) {
            try check()
        }

        // A nested function rather than the closure's body: AGENTS.md, closures inside #expect
        // inside another closure.
        func check() throws {
            let schema = EventSchema(name: name, version: 1, consentCategory: .analytics, properties: [])
            let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
            let record = EventRecord(event: Named(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
            let expected: [GoogleAnalyticsEncodingError] = invalid ? [.invalidEventName(name: name)] : []
            let expectedRequestCount = invalid ? 0 : 1

            let actual = sut.requests(for: [record])

            #expect(actual.skippedRecords.map(\.reason) == expected)
            #expect(actual.requests.count == expectedRequestCount)
        }
    }

    // https://developers.google.com/analytics/devguides/collection/protocol/ga4/reference,
    // "Reserved event names", and screen_view, ad_impression and in_app_purchase, "only allowed for
    // App streams".
    @Test("A record whose event name Google Analytics keeps, or takes only from an app stream, is left out as reservedEventName, and names that only resemble one are sent", arguments: [
        ("session_start", true), ("first_visit", true), ("first_open", true), ("error", true), ("user_engagement", true), ("app_remove", true),
        ("ad_activeview", true), ("adunit_exposure", true), ("dynamic_link_first_open", true), ("firebase_campaign", true),
        ("firebase_in_app_message_impression", true), ("notification_send", true), ("os_update", true), ("app_store_refund", true),
        ("screen_view", true), ("ad_impression", true), ("in_app_purchase", true),
        ("Session_Start", false), ("session_started", false), ("session_star", false), ("errors", false), ("Error", false), ("page_view", false),
        ("screen_viewed", false), ("ScreenViewed", false), ("SessionStarted", false), ("purchase", false), ("click", false), ("firebase_x", false),
        ("ga_x", false), ("google_x", false),
    ] as [(String, Bool)])
    func reservedEventName(name: String, reserved: Bool) throws {
        try Named.$testName.withValue(name) {
            try check()
        }

        // A nested function rather than the closure's body: AGENTS.md, closures inside #expect
        // inside another closure.
        func check() throws {
            let schema = EventSchema(name: name, version: 1, consentCategory: .analytics, properties: [])
            let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
            let record = EventRecord(event: Named(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
            let expected: [GoogleAnalyticsEncodingError] = reserved ? [.reservedEventName(name: name)] : []
            let expectedRequestCount = reserved ? 0 : 1

            let actual = sut.requests(for: [record])

            #expect(actual.skippedRecords.map(\.reason) == expected)
            #expect(actual.requests.count == expectedRequestCount)
        }
    }

    @Test("A record the plan describes whose name Google Analytics refuses is left out for its name, though it can't be read either")
    func nameBeforeReadError() throws {
        struct SessionStart: Event {
            static let name = "session_start"
        }
        struct Dashed: Event {
            static let name = "a-b"
        }
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [
            EventSchema(name: "session_start", version: 1, consentCategory: .analytics, properties: []),
            EventSchema(name: "a-b", version: 1, consentCategory: .analytics, properties: []),
        ]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let batch = [
            EventRecord(event: SessionStart(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil),
            EventRecord(event: Dashed(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil),
        ]
        let expected: [GoogleAnalyticsEncodingError] = [.reservedEventName(name: "session_start"), .invalidEventName(name: "a-b")]

        let actual = sut.requests(for: batch).skippedRecords.map(\.reason)

        #expect(actual == expected)
    }

    @Test("A record the plan doesn't describe is left out as unknownEvent even when Google Analytics keeps its name")
    func unknownBeforeReserved() throws {
        struct SessionStart: Event, Codable {
            static let name = "session_start"
        }
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: []), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let record = EventRecord(event: SessionStart(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<GoogleAnalyticsEncodingError>(recordID: record.id, eventName: "session_start", schemaVersion: 1, reason: .unknownEvent(name: "session_start", version: 1))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A parameter name of 1 to 40 bytes, starting with a letter, of letters, numbers and _ alone, is sent, and any other is left out as invalidParameterName", arguments: [
        (String(repeating: "p", count: 40), false), ("p", false), ("cartSize", false), ("café", false), (String(repeating: "é", count: 20), false), ("p٣_", false), ("p²", false), ("pⅣ", false),
        (String(repeating: "p", count: 41), true), (String(repeating: "é", count: 21), true), ("", true), ("1p", true), ("_p", true), ("p-q", true), ("p.q", true),
        ("gtag.p", true), ("p q", true), ("e\u{301}", true),
    ] as [(String, Bool)])
    func invalidParameterName(parameter: String, invalid: Bool) throws {
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let record = EventRecord(event: PropertiesNamed(properties: [parameter: "value"]), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [GoogleAnalyticsEncodingError] = invalid ? [.invalidParameterName(event: "properties_named", parameter: parameter)] : []
        let expectedRequestCount = invalid ? 0 : 1

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.count == expectedRequestCount)
    }

    // https://developers.google.com/analytics/devguides/collection/protocol/ga4/reference,
    // "Reserved parameter names"; case-sensitive, as the validation server checks them.
    @Test("A record with a parameter Google Analytics keeps, or the encoder writes, is left out as reservedParameterName, and names that only resemble one are sent", arguments: [
        ("firebase_conversion", true), ("firebase_p", true), ("firebase_", true), ("ga_p", true), ("ga_", true), ("google_p", true), ("google_", true), ("session_id", true),
        ("Firebase_p", false), ("GA_p", false), ("Google_p", false), ("FIREBASE_CONVERSION", false), ("firebase", false), ("ga", false), ("gap", false), ("googlep", false),
        ("session_ids", false), ("sessionID", false), ("Session_id", false), ("my_ga_p", false), ("user_id", false), ("engagement_time_msec", false),
    ] as [(String, Bool)])
    func reservedParameterName(parameter: String, reserved: Bool) throws {
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let record = EventRecord(event: PropertiesNamed(properties: [parameter: "value"]), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [GoogleAnalyticsEncodingError] = reserved ? [.reservedParameterName(event: "properties_named", parameter: parameter)] : []
        let expectedRequestCount = reserved ? 0 : 1

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.count == expectedRequestCount)
    }

    @Test("An @Event with properties named session_id and ga_label is left out, naming the first of them by its bytes, so the encoder's session_id isn't replaced")
    func reservedEventProperties() throws {
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [VideoWatched.schema, CheckoutStarted.schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        let skipped = EventRecord(event: VideoWatched(session_id: 7, ga_label: "x"), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil, context: context)
        let sent = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        let expected = [SkippedRecord<GoogleAnalyticsEncodingError>(recordID: skipped.id, eventName: "video_watched", schemaVersion: 1, reason: .reservedParameterName(event: "video_watched", parameter: "ga_label"))]

        let actual = sut.requests(for: [sent, skipped])

        #expect(actual.skippedRecords == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == [sent.id])
    }

    @Test("Of a parameter name that isn't one and one that is reserved, the invalid one is reported, by its bytes first")
    func invalidBeforeReserved() throws {
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let record = EventRecord(event: PropertiesNamed(properties: ["ga_p": "a", "z-z": "b", "y-y": "c"]), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [GoogleAnalyticsEncodingError] = [.invalidParameterName(event: "properties_named", parameter: "y-y")]

        let actual = sut.requests(for: [record]).skippedRecords.map(\.reason)

        #expect(actual == expected)
    }

    @Test("A Sensitive property named session_id is never sent, so the record is sent with the encoder's session_id")
    func reservedSensitiveProperty() throws {
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [RedactedSession.schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        var record = EventRecord(event: RedactedSession(session_id: Sensitive(424_242), count: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        record.revealsSensitiveValues = true
        let expectedSessionID: Int64 = 1_795_442_600_000

        let actual = sut.requests(for: [record])

        let body = try #require(actual.requests.first).body.body
        let request = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let params = try #require((request["events"] as? [[String: Any]])?.first?["params"] as? [String: Any])
        #expect(actual.skippedRecords.isEmpty)
        #expect((params["session_id"] as? NSNumber)?.int64Value == expectedSessionID)
        #expect(!String(decoding: body, as: UTF8.self).contains("424242"))
    }

    @Test("A record whose values flatten to one parameter's name is left out as parameterNameCollision")
    func parameterNameCollision() throws {
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [CartViewed.schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let record = EventRecord(event: CartViewed(cart: Cart(size: 2), cart_size: 3), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<GoogleAnalyticsEncodingError>(recordID: record.id, eventName: "cart_viewed", schemaVersion: 1, reason: .parameterNameCollision(event: "cart_viewed", parameter: "cart_size"))]

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords == expected)
        #expect(actual.requests.isEmpty)
    }

    // https://developers.google.com/analytics/devguides/collection/protocol/ga4/reference: "Up to
    // 25 parameters can be sent per event".
    @Test("A record of 25 parameters, counting session_id, is sent, and one of 26 is left out as tooManyParameters with its count", arguments: [
        (25, false, false), (26, false, true), (24, true, false), (25, true, true), (0, true, false), (30, false, true),
    ])
    func tooManyParameters(propertyCount: Int, hasSession: Bool, skipped: Bool) throws {
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        var context = ServiceContext.topLevel
        if hasSession {
            context[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        }
        let properties = Dictionary(uniqueKeysWithValues: (0 ..< propertyCount).map { ("p\($0)", "v") })
        let record = EventRecord(event: PropertiesNamed(properties: properties), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        let expected: [GoogleAnalyticsEncodingError] = skipped ? [.tooManyParameters(event: "properties_named", count: propertyCount + (hasSession ? 1 : 0))] : []

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.count == (skipped ? 0 : 1))
    }

    @Test("A nested value counts a parameter for each value it holds")
    func nestedParametersCounted() throws {
        struct Tagged: Event, Codable {
            static let name = "tagged"
            var tags: [String]
        }
        let schema = EventSchema(name: "tagged", version: 1, consentCategory: .analytics, properties: [])
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let sent = EventRecord(event: Tagged(tags: Array(repeating: "t", count: 25)), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let skipped = EventRecord(event: Tagged(tags: Array(repeating: "t", count: 26)), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [GoogleAnalyticsEncodingError] = [.tooManyParameters(event: "tagged", count: 26)]

        let actual = sut.requests(for: [sent, skipped])

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == [sent.id])
    }

    // The validation server counts the 100 in bytes of UTF-8: 50 "é" pass, 51 don't, and nor do
    // 50 "é" and an "a" (2026-11-27).
    @Test("A string of up to 100 bytes is sent, and a longer one is left out as parameterValueTooLong with its bytes", arguments: [
        (String(repeating: "v", count: 100), Int?.none), ("", nil), (String(repeating: "é", count: 50), nil), (String(repeating: "😀", count: 25), nil),
        (String(repeating: "中", count: 33) + "a", nil),
        (String(repeating: "v", count: 101), 101), (String(repeating: "é", count: 51), 102), (String(repeating: "é", count: 50) + "a", 101),
        (String(repeating: "😀", count: 25) + "a", 101), (String(repeating: "中", count: 33) + "aa", 101),
    ] as [(String, Int?)])
    func parameterValueTooLong(value: String, byteCount: Int?) throws {
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [Searched.schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let record = EventRecord(event: Searched(query: value), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [GoogleAnalyticsEncodingError] = byteCount.map { [.parameterValueTooLong(event: "searched", parameter: "query", byteCount: $0)] } ?? []

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.count == (byteCount == nil ? 1 : 0))
    }

    @Test("Of two strings too long, the parameter first by its name's bytes is reported")
    func firstValueTooLong() throws {
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let record = EventRecord(event: PropertiesNamed(properties: ["b": String(repeating: "v", count: 102), "a": String(repeating: "v", count: 101), "c": "short"]), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [GoogleAnalyticsEncodingError] = [.parameterValueTooLong(event: "properties_named", parameter: "a", byteCount: 101)]

        let actual = sut.requests(for: [record]).skippedRecords.map(\.reason)

        #expect(actual == expected)
    }

    // Int64.max microseconds is about 9.223e12 seconds from 1970.
    @Test("A record whose timestamp has no microseconds form is left out as unrepresentableTimestamp", arguments: [
        Double.nan, .infinity, -.infinity, 9.3e12, -9.3e12,
    ])
    func unrepresentableTimestamp(seconds: Double) throws {
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { Date(timeIntervalSince1970: seconds) })
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: seconds), sourceLocation: nil)
        let expected = [SkippedRecord<GoogleAnalyticsEncodingError>(recordID: record.id, eventName: "checkout_started", schemaVersion: 2, reason: .unrepresentableTimestamp)]

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords == expected)
        #expect(actual.requests.isEmpty)
    }

    @Test("A timestamp at the edges of what has a microseconds form is sent when the batch is encoded then", arguments: [9.2e12, -9.2e12, 0])
    func representableTimestamp(seconds: Double) throws {
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { Date(timeIntervalSince1970: seconds) })
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: seconds), sourceLocation: nil)

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.isEmpty)
        #expect(actual.requests.flatMap(\.recordIDs) == [record.id])
    }

    // https://developers.google.com/analytics/devguides/collection/protocol/ga4/sending-events:
    // "Events ... can be backdated up to 72 hours"; the validation server supports "timestamps
    // [15m] into the future" (2026-11-27). The encoder holds the past to 71 hours, an hour short.
    @Test("A record tracked up to 71 hours before, or 15 minutes after, its batch is encoded is sent, and one further out is left out as timestampOutsideWindow", arguments: [
        (0.0, false), (-255_600, false), (900, false), (-255_599.999, false), (899.999, false),
        (-255_600.001, true), (900.001, true), (-259_200, true), (-1_000_000, true), (86_400, true),
    ])
    func timestampWindow(offset: Double, skipped: Bool) throws {
        let encodedAt = Date(timeIntervalSince1970: 1_795_442_607)
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { encodedAt })
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: encodedAt.addingTimeInterval(offset), sourceLocation: nil)
        let expected: [SkippedRecord<GoogleAnalyticsEncodingError>] = skipped
            ? [SkippedRecord(recordID: record.id, eventName: "checkout_started", schemaVersion: 2, reason: .timestampOutsideWindow)]
            : []

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == (skipped ? [] : [record.id]))
    }

    @Test("The time a batch is encoded at is read when it is encoded, so the same record is sent at one time and left out at a later one")
    func windowReadPerBatch() throws {
        let clock = WallClock(Date(timeIntervalSince1970: 1_795_442_607))
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { clock.now })
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expectedLater: [GoogleAnalyticsEncodingError] = [.timestampOutsideWindow]

        let actualNow = sut.requests(for: [record])
        clock.now = Date(timeIntervalSince1970: 1_795_442_607 + 255_601)
        let actualLater = sut.requests(for: [record])

        #expect(actualNow.skippedRecords.isEmpty)
        #expect(actualLater.skippedRecords.map(\.reason) == expectedLater)
    }

    @Test("A batch encoded at a time with no value, as a broken clock gives, keeps the record in its request, for the destination's deadline check to drop")
    func nanEncodingTime() throws {
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { Date(timeIntervalSince1970: .nan) })
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.isEmpty)
        #expect(actual.requests.flatMap(\.recordIDs) == [record.id])
    }

    @Test("A record with a reserved parameter is left out for it, before a timestamp with no microseconds form")
    func reservedParameterBeforeTimestamp() throws {
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [VideoWatched.schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let record = EventRecord(event: VideoWatched(session_id: 1, ga_label: "x"), timestamp: Date(timeIntervalSince1970: .nan), sourceLocation: nil)
        let expected: [GoogleAnalyticsEncodingError] = [.reservedParameterName(event: "video_watched", parameter: "ga_label")]

        let actual = sut.requests(for: [record]).skippedRecords.map(\.reason)

        #expect(actual == expected)
    }

    @Test("A batch whose every record is skipped has no request, and each record's reason is reported, a client's after another's")
    func everyRecordSkipped() throws {
        struct SessionStart: Event, Codable {
            static let name = "session_start"
        }
        let sessionStart = EventSchema(name: "session_start", version: 1, consentCategory: .analytics, properties: [])
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [CheckoutStarted.schema, VideoWatched.schema, sessionStart]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        let batch = [
            EventRecord(event: Measured(value: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context),
            EventRecord(event: SessionStart(), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil, context: context),
            EventRecord(event: VideoWatched(session_id: 1, ga_label: "x"), timestamp: Date(timeIntervalSince1970: 1_795_442_609), sourceLocation: nil, context: context),
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: .nan), sourceLocation: nil, context: context),
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_000_000), sourceLocation: nil, context: context),
        ]
        let expectedSkipped = [
            SkippedRecord<GoogleAnalyticsEncodingError>(recordID: batch[0].id, eventName: "measured", schemaVersion: 1, reason: .unknownEvent(name: "measured", version: 1)),
            SkippedRecord<GoogleAnalyticsEncodingError>(recordID: batch[1].id, eventName: "session_start", schemaVersion: 1, reason: .reservedEventName(name: "session_start")),
            SkippedRecord<GoogleAnalyticsEncodingError>(recordID: batch[2].id, eventName: "video_watched", schemaVersion: 1, reason: .reservedParameterName(event: "video_watched", parameter: "ga_label")),
            SkippedRecord<GoogleAnalyticsEncodingError>(recordID: batch[3].id, eventName: "checkout_started", schemaVersion: 2, reason: .unrepresentableTimestamp),
            SkippedRecord<GoogleAnalyticsEncodingError>(recordID: batch[4].id, eventName: "checkout_started", schemaVersion: 2, reason: .timestampOutsideWindow),
        ]

        let actual = sut.requests(for: batch)

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords == expectedSkipped)
    }
}

/// A wall-clock time a test moves, for an encoder that reads it once a batch.
private final class WallClock: Sendable {
    private let time: Mutex<Date>

    init(_ time: Date) {
        self.time = Mutex(time)
    }

    var now: Date {
        get { time.withLock { $0 } }
        set { time.withLock { $0 = newValue } }
    }
}
#endif
