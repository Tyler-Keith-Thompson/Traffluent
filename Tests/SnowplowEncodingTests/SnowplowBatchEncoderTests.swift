import EventMacros
import Foundation
import HTTPDestinations
import Instrumentation
import Persistence
import Sessions
import SnowplowEncoding
import StandardContext
import Testing
import TrackingPlans

@Suite("SnowplowBatchEncoder: payload_data events")
struct SnowplowBatchEncoderTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
        var email: Sensitive<String>
        var seats: Int
    }

    @Event(name: "checkout_started", version: 2)
    struct CheckoutStarted {
        var cartSize: Int
        var coupon: String?
    }

    @Test("A body is payload_data 1-0-4 of one event per record, oldest first")
    func envelope() throws {
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let batch = [
            EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil),
            EventRecord(event: CheckoutStarted(cartSize: 2, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil),
        ]
        let expectedSchema = "iglu:com.snowplowanalytics.snowplow/payload_data/jsonschema/1-0-4"
        let expectedIDs = batch.map { $0.id.uuidString.lowercased() }

        let actual = sut.requests(for: batch)

        let request = try #require(actual.requests.first)
        #expect(actual.requests.count == 1)
        #expect(request.body.contentType == "application/json")
        let body = try #require(try JSONSerialization.jsonObject(with: request.body.body) as? [String: Any])
        #expect(Set(body.keys) == ["data", "schema"])
        #expect(body["schema"] as? String == expectedSchema)
        let events = try #require(body["data"] as? [[String: Any]])
        #expect(events.map { $0["eid"] as? String } == expectedIDs)
    }

    @Test("Each event is a self-describing event of its Iglu schema, version N as N-0-0, every member a string, with the record's time as dtm and ttm and no stm")
    func eventMembers() throws {
        let sut = try SnowplowBatchEncoder(vendor: "com.example.shop", appID: "shop-ios", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let record = EventRecord(
            id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!,
            event: CheckoutStarted(cartSize: 3, coupon: "SPRING"),
            timestamp: Date(timeIntervalSince1970: 1_795_442_607.5),
            sourceLocation: nil)
        let expected: [String: String] = [
            "aid": "shop-ios",
            "dtm": "1795442607500",
            "e": "ue",
            "eid": "6f9619ff-8b86-d011-b42d-00c04fc964ff",
            "ip": "0.0.0.0",
            "p": "app",
            "ttm": "1795442607500",
            "tv": "traffluent",
            "ue_pr": #"{"data":{"data":{"cartSize":3,"coupon":"SPRING"},"schema":"iglu:com.example.shop/checkout_started/jsonschema/2-0-0"},"schema":"iglu:com.snowplowanalytics.snowplow/unstruct_event/jsonschema/1-0-0"}"#,
        ]

        let request = try #require(sut.requests(for: [record]).requests.first)

        let body = try #require(try JSONSerialization.jsonObject(with: request.body.body) as? [String: Any])
        let actual = try #require((body["data"] as? [[String: Any]])?.first as? [String: String])
        #expect(actual == expected)
    }

    @Test("Only sid, the record's session, identifies it: no duid, uid, nuid, tnuid or device identifier is sent")
    func onlySession() throws {
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let session = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        var context = ServiceContext.topLevel
        context[SessionKey.self] = session
        context[VendorIdentifierKey.self] = Sensitive(UUID(uuidString: "00000000-0000-4000-8000-0000000000AA")!)
        context[DeviceKey.self] = DeviceKey.Value(model: "iPhone17,1", formFactor: .phone)
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
        var record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        record.revealsSensitiveValues = true
        let expectedSession = "01a208b7-e840-7a3e-8b4d-5c6e7f801234"
        let forbidden = ["duid", "uid", "nuid", "tnuid", "vid", "fp", "mac", "ad_uid"]

        let request = try #require(sut.requests(for: [record]).requests.first)

        let body = try #require(try JSONSerialization.jsonObject(with: request.body.body) as? [String: Any])
        let actual = try #require((body["data"] as? [[String: Any]])?.first)
        #expect(actual["sid"] as? String == expectedSession)
        #expect(forbidden.allSatisfy { actual[$0] == nil })
        let text = String(decoding: request.body.body, as: UTF8.self)
        #expect(!text.contains("00000000-0000-4000-8000-0000000000aa"))
        #expect(!text.lowercased().contains("idfv"))
        #expect(!text.lowercased().contains("idfa"))
        #expect(!text.contains("client_session"))
    }

    @Test("A record with no session is sent without a sid, rather than under an identifier made up for it")
    func noSession() throws {
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expectedKeys: Set<String> = ["aid", "dtm", "e", "eid", "ip", "p", "ttm", "tv", "ue_pr"]

        let request = try #require(sut.requests(for: [record]).requests.first)

        let body = try #require(try JSONSerialization.jsonObject(with: request.body.body) as? [String: Any])
        let actual = try #require((body["data"] as? [[String: Any]])?.first)
        #expect(Set(actual.keys) == expectedKeys)
    }

    @Test("A Sensitive value is never sent, even by a record that reveals it")
    func sensitiveNeverSent() throws {
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [SignedUp.schema]))
        var record = EventRecord(event: SignedUp(plan: "pro", email: Sensitive("ada@example.com"), seats: 3), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        record.revealsSensitiveValues = true
        let expectedData = #"{"plan":"pro","seats":3}"#

        let request = try #require(sut.requests(for: [record]).requests.first)

        let text = String(decoding: request.body.body, as: UTF8.self)
        #expect(!text.contains("ada@example.com"))
        let body = try #require(try JSONSerialization.jsonObject(with: request.body.body) as? [String: Any])
        let event = try #require((body["data"] as? [[String: Any]])?.first?["ue_pr"] as? String)
        #expect(event.contains(expectedData))
    }

    @Test("The platform follows the device's form factor, as Snowplow's iOS tracker names it, and is app without a device", arguments: [
        (DeviceKey.Value.FormFactor?.some(.phone), "mob"), (.pad, "mob"), (.watch, "mob"), (.vision, "mob"), (.tv, "tv"), (.mac, "pc"), (nil, "app"),
    ])
    func platform(formFactor: DeviceKey.Value.FormFactor?, expected: String) throws {
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        if let formFactor {
            context[DeviceKey.self] = DeviceKey.Value(model: "Model1,1", formFactor: formFactor)
        }
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)

        let request = try #require(sut.requests(for: [record]).requests.first)

        let body = try #require(try JSONSerialization.jsonObject(with: request.body.body) as? [String: Any])
        let actual = (body["data"] as? [[String: Any]])?.first?["p"] as? String
        #expect(actual == expected)
    }

    @Test("The standard context is sent as mobile_context and application entities in co, without device identifiers")
    func entities() throws {
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: "418")
        context[DeviceKey.self] = DeviceKey.Value(model: "iPhone17,1", formFactor: .phone)
        context[LocaleKey.self] = Locale(identifier: "en_US")
        context[NetworkKey.self] = .cellular
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        let expected = #"{"data":[{"data":{"deviceManufacturer":"Apple Inc.","deviceModel":"iPhone17,1","language":"en","networkType":"mobile","osType":"ios","osVersion":"26.1.0"},"schema":"iglu:com.snowplowanalytics.snowplow/mobile_context/jsonschema/1-0-3"},{"data":{"build":"418","version":"2.4.1"},"schema":"iglu:com.snowplowanalytics.mobile/application/jsonschema/1-0-0"}],"schema":"iglu:com.snowplowanalytics.snowplow/contexts/jsonschema/1-0-1"}"#

        let request = try #require(sut.requests(for: [record]).requests.first)

        let body = try #require(try JSONSerialization.jsonObject(with: request.body.body) as? [String: Any])
        let actual = (body["data"] as? [[String: Any]])?.first?["co"] as? String
        #expect(actual == expected)
    }

    @Test("mobile_context's osType names each Apple system as Snowplow's iOS tracker does, and networkType only Wi-Fi, cellular and offline", arguments: [
        ("iOS", NetworkKey.Value.wifi, "ios", String?.some("wifi")), ("tvOS", .offline, "tvos", "offline"), ("watchOS", .wiredEthernet, "watchos", nil),
        ("visionOS", .other, "visionos", nil), ("macOS", .cellular, "osx", "mobile"), ("Linux", .wifi, "linux", "wifi"),
    ])
    func mobileContextNames(system: String, network: NetworkKey.Value, expectedOSType: String, expectedNetworkType: String?) throws {
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        context[DeviceKey.self] = DeviceKey.Value(model: "Model1,1", formFactor: .phone)
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: system, version: "1.0.0")
        context[NetworkKey.self] = network
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)

        let request = try #require(sut.requests(for: [record]).requests.first)

        let object = try #require(try JSONSerialization.jsonObject(with: request.body.body) as? [String: Any])
        let co = try #require((object["data"] as? [[String: Any]])?.first?["co"] as? String)
        let contexts = try #require(try JSONSerialization.jsonObject(with: Data(co.utf8)) as? [String: Any])
        let mobile = try #require((contexts["data"] as? [[String: Any]])?.first?["data"] as? [String: Any])
        #expect(mobile["osType"] as? String == expectedOSType)
        #expect(mobile["networkType"] as? String == expectedNetworkType)
    }

    @Test("mobile_context needs both a device and an operating system, and application both a version and a build of at most 255 UTF-16 code units")
    func partialContext() throws {
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        func co(_ context: ServiceContext) throws -> String? {
            let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
            let request = try #require(sut.requests(for: [record]).requests.first)
            let body = try #require(try JSONSerialization.jsonObject(with: request.body.body) as? [String: Any])
            return (body["data"] as? [[String: Any]])?.first?["co"] as? String
        }
        var deviceOnly = ServiceContext.topLevel
        deviceOnly[DeviceKey.self] = DeviceKey.Value(model: "iPhone17,1", formFactor: .phone)
        var systemOnly = ServiceContext.topLevel
        systemOnly[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
        var versionOnly = ServiceContext.topLevel
        versionOnly[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: nil)
        var longest = ServiceContext.topLevel
        longest[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: nil, version: String(repeating: "1", count: 255), build: "1")
        var tooLong = ServiceContext.topLevel
        tooLong[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: nil, version: "1", build: String(repeating: "1", count: 256))
        var versionTooLong = ServiceContext.topLevel
        versionTooLong[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: nil, version: String(repeating: "1", count: 256), build: "1")

        #expect(try co(deviceOnly) == nil)
        #expect(try co(systemOnly) == nil)
        #expect(try co(versionOnly) == nil)
        #expect(try co(longest)?.contains("application") == true)
        #expect(try co(tooLong) == nil)
        #expect(try co(versionTooLong) == nil)
    }

    @Test("mobile_context's language is the locale's language code, and is left out past the schema's 8 characters", arguments: [
        ("pt_BR", String?.some("pt")), ("abcdefgh", "abcdefgh"), ("abcdefghi_US", nil),
    ])
    func language(identifier: String, expected: String?) throws {
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        context[DeviceKey.self] = DeviceKey.Value(model: "iPad16,3", formFactor: .pad)
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
        context[LocaleKey.self] = Locale(identifier: identifier)
        let record = EventRecord(event: CheckoutStarted(cartSize: 1, coupon: nil), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)

        let request = try #require(sut.requests(for: [record]).requests.first)

        let object = try #require(try JSONSerialization.jsonObject(with: request.body.body) as? [String: Any])
        let co = try #require((object["data"] as? [[String: Any]])?.first?["co"] as? String)
        let contexts = try #require(try JSONSerialization.jsonObject(with: Data(co.utf8)) as? [String: Any])
        let mobile = try #require((contexts["data"] as? [[String: Any]])?.first?["data"] as? [String: Any])
        #expect(mobile["language"] as? String == expected)
    }
}
