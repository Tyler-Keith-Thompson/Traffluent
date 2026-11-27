import AmplitudeEncoding
import EventMacros
import Foundation
import Instrumentation
import Persistence
import Sessions
import StandardContext
import Testing
import Trackers
import TrackingPlans

@Suite("AmplitudeBatchEncoder: context")
struct AmplitudeContextTests {
    @Event(name: "opened")
    struct Opened {
        var count: Int
    }

    @Event(name: "upgraded")
    struct Upgraded {
        var platform: String
    }

    @Test("The standard context is Amplitude's top-level fields: app_version, device_model, language, platform, os_name and os_version")
    func fields() throws {
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [Opened.schema]))
        var context = ServiceContext.topLevel
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: "418")
        context[DeviceKey.self] = DeviceKey.Value(model: "Mac16,1", formFactor: .mac)
        context[LocaleKey.self] = Locale(identifier: "pt_BR")
        context[NetworkKey.self] = .cellular
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "macOS", version: "26.1.0")
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: Opened(count: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expected = #"{"api_key":"test-api-key","events":[{"app_version":"2.4.1","device_id":"00000000-0000-4000-8000-000000000001","device_model":"Mac16,1","event_properties":{"count":1},"event_type":"opened","insert_id":"00000000-0000-4000-8000-000000000001","language":"pt-BR","os_name":"macOS","os_version":"26.1.0","platform":"macOS","time":0}]}"#

        let actual = try #require(sut.requests(for: [record]).requests.first).body

        #expect(String(decoding: actual.body, as: UTF8.self) == expected)
    }

    @Test("The bundle identifier, build, form factor and network have no Amplitude field and aren't sent, in any form", arguments: [
        DeviceKey.Value.FormFactor.phone, .pad, .mac, .tv, .watch, .vision,
    ])
    func unmappedLeftOut(formFactor: DeviceKey.Value.FormFactor) throws {
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [Opened.schema]))
        var context = ServiceContext.topLevel
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: nil, build: "418")
        context[DeviceKey.self] = DeviceKey.Value(model: "Model1,1", formFactor: formFactor)
        context[NetworkKey.self] = .wifi
        // A fixed identifier: a random UUID can contain "418" and fail the search below.
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: Opened(count: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expectedKeys = ["device_id", "device_model", "event_properties", "event_type", "insert_id", "time"]

        let body = try #require(sut.requests(for: [record]).requests.first).body.body
        let text = String(decoding: body, as: UTF8.self)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let event = try #require((object["events"] as? [[String: Any]])?.first)
        let actual = event.keys.sorted()

        #expect(actual == expectedKeys)
        #expect(!text.contains("com.example.shop"))
        #expect(!text.contains("418"))
        #expect(!text.contains("wifi"))
    }

    @Test("A context with only a session adds only device_id's session; the sample rate isn't sent")
    func sessionOnly() throws {
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [Opened.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
        context[SampleRateKey.self] = try SampleRate(0.5)
        let record = EventRecord(event: Opened(count: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expected = ["device_id", "event_properties", "event_type", "insert_id", "time"]

        let body = try #require(sut.requests(for: [record]).requests.first).body.body
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let event = try #require((object["events"] as? [[String: Any]])?.first)
        let actual = event.keys.sorted()

        #expect(actual == expected)
        #expect(!String(decoding: body, as: UTF8.self).contains("0.5"))
    }

    @Test("A locale is its BCP 47 identifier", arguments: [("en_US", "en-US"), ("pt_BR", "pt-BR"), ("en_GB", "en-GB")])
    func locale(identifier: String, expected: String) throws {
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [Opened.schema]))
        var context = ServiceContext.topLevel
        context[LocaleKey.self] = Locale(identifier: identifier)
        let record = EventRecord(event: Opened(count: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)

        let body = try #require(sut.requests(for: [record]).requests.first).body.body
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let event = try #require((object["events"] as? [[String: Any]])?.first)
        let actual = event["language"] as? String

        #expect(actual == expected)
    }

    @Test("An event's own property named as an Amplitude field stays in event_properties, and the context's field is sent beside it")
    func propertyNamedAsAField() throws {
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [Upgraded.schema]))
        var context = ServiceContext.topLevel
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
        let record = EventRecord(event: Upgraded(platform: "web"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expectedField = "iOS"
        let expectedProperty = "web"

        let body = try #require(sut.requests(for: [record]).requests.first).body.body
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let event = try #require((object["events"] as? [[String: Any]])?.first)
        let actualField = event["platform"] as? String
        let actualProperty = (event["event_properties"] as? [String: Any])?["platform"] as? String

        #expect(actualField == expectedField)
        #expect(actualProperty == expectedProperty)
    }
}
