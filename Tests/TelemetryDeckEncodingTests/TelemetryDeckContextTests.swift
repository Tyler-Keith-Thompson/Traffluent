import EventMacros
import Foundation
import Instrumentation
import StandardContext
import TelemetryDeckEncoding
import Testing
import TrackingPlans

// The parameters are TelemetryDeck's built-in ones
// (https://telemetrydeck.com/docs/ingest/default-parameters/, read 2026-11-27), in the forms its
// SwiftSDK 2.14.2 writes them (DefaultSignalPayload): "<version> (build <build>)", and each system
// version after the platform ("iOS 26.1.0", "iOS 26", "iOS 26.1").
@Suite("TelemetryDeckBatchEncoder: the standard context")
struct TelemetryDeckContextTests {
    @Event(name: "checkout_started")
    struct CheckoutStarted {
        var cartSize: Int
    }

    @Test("Each standard context key becomes TelemetryDeck's built-in parameters, and the bundle identifier, form factor and network are left out")
    func everyKey() throws {
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: "418")
        context[DeviceKey.self] = DeviceKey.Value(model: "iPad16,3", formFactor: .pad)
        context[LocaleKey.self] = Locale(identifier: "de_CH")
        context[NetworkKey.self] = .wifi
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        let expected: [String: String] = [
            "TelemetryDeck.AppInfo.buildNumber": "418",
            "TelemetryDeck.AppInfo.version": "2.4.1",
            "TelemetryDeck.AppInfo.versionAndBuildNumber": "2.4.1 (build 418)",
            "TelemetryDeck.Device.modelName": "iPad16,3",
            "TelemetryDeck.Device.operatingSystem": "iOS",
            "TelemetryDeck.Device.platform": "iOS",
            "TelemetryDeck.Device.systemMajorMinorVersion": "iOS 26.1",
            "TelemetryDeck.Device.systemMajorVersion": "iOS 26",
            "TelemetryDeck.Device.systemVersion": "iOS 26.1.0",
            "TelemetryDeck.RunContext.language": "de",
            "TelemetryDeck.RunContext.locale": "de_CH",
            "TelemetryDeck.SDK.name": "Traffluent",
            "TelemetryDeck.UserPreference.region": "CH",
        ]

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        let actual = event.filter { $0.key.hasPrefix("TelemetryDeck.") }.compactMapValues { $0 as? String }
        #expect(actual == expected)
        #expect(!String(decoding: body, as: UTF8.self).contains("com.example.shop"))
    }

    @Test("A record with no standard context has only the SDK's name among TelemetryDeck's parameters")
    func noContext() throws {
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: Set<String> = ["TelemetryDeck.SDK.name"]

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        #expect(Set(event.keys.filter { $0.hasPrefix("TelemetryDeck.") }) == expected)
    }

    @Test("An app's version without a build, or a build without a version, is sent alone, with no versionAndBuildNumber", arguments: [
        (String?("2.4.1"), String?.none, ["TelemetryDeck.AppInfo.version": "2.4.1"]),
        (String?.none, String?("418"), ["TelemetryDeck.AppInfo.buildNumber": "418"]),
        (String?.none, String?.none, [:]),
    ])
    func partialApplication(version: String?, build: String?, expected: [String: String]) throws {
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: version, build: build)
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        let actual = event.filter { $0.key.hasPrefix("TelemetryDeck.AppInfo.") }.compactMapValues { $0 as? String }
        #expect(actual == expected)
    }

    @Test("The system's versions are its first component and its first two, however many it has; an empty version sends the system's name alone", arguments: [
        ("macOS", "26", ["macOS 26", "macOS 26", "macOS 26"]),
        ("visionOS", "3.0", ["visionOS 3.0", "visionOS 3", "visionOS 3.0"]),
        ("Linux", "6.8.0.45", ["Linux 6.8.0.45", "Linux 6", "Linux 6.8"]),
        ("watchOS", "", []),
    ])
    func systemVersions(name: String, version: String, expected: [String]) throws {
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: name, version: version)
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        let names = ["TelemetryDeck.Device.systemVersion", "TelemetryDeck.Device.systemMajorVersion", "TelemetryDeck.Device.systemMajorMinorVersion"]

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        #expect(names.compactMap { event[$0] as? String } == expected)
        #expect(event["TelemetryDeck.Device.operatingSystem"] as? String == name)
        #expect(event["TelemetryDeck.Device.platform"] as? String == name)
    }

    @Test("A locale with no region sends no region, and one with no language no language", arguments: [
        ("en", ["TelemetryDeck.RunContext.language": "en", "TelemetryDeck.RunContext.locale": "en"]),
        ("", ["TelemetryDeck.RunContext.locale": ""]),
    ])
    func partialLocale(identifier: String, expected: [String: String]) throws {
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        context[LocaleKey.self] = Locale(identifier: identifier)
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        let actual = event.filter { $0.key.hasPrefix("TelemetryDeck.RunContext.") || $0.key.hasPrefix("TelemetryDeck.UserPreference.") }.compactMapValues { $0 as? String }
        #expect(actual == expected)
    }
}
