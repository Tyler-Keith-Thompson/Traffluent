import EventMacros
import Foundation
import Instrumentation
import MixpanelEncoding
import Persistence
import Sessions
import StandardContext
import Testing
import Trackers
import TrackingPlans

@Suite("MixpanelBatchEncoder: context")
struct MixpanelContextTests {
    @Event(name: "opened")
    struct Opened {
        var count: Int
    }

    @Event(name: "upgraded")
    struct Upgraded {
        var os: String
        var model: String
    }

    @Test("The standard context is Mixpanel's default properties: $app_version_string, $app_build_number, $model, $wifi, $os and $os_version")
    func properties() throws {
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [Opened.schema]))
        var context = ServiceContext.topLevel
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: "418")
        context[DeviceKey.self] = DeviceKey.Value(model: "Mac16,1", formFactor: .mac)
        context[LocaleKey.self] = Locale(identifier: "pt_BR")
        context[NetworkKey.self] = .wifi
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "macOS", version: "26.1.0")
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: Opened(count: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        let expected = #"[{"event":"opened","properties":{"$app_build_number":"418","$app_version_string":"2.4.1","$insert_id":"00000000-0000-4000-8000-000000000001","$model":"Mac16,1","$os":"macOS","$os_version":"26.1.0","$wifi":true,"count":1,"distinct_id":"00000000-0000-4000-8000-000000000001","ip":"0","time":1795442607000,"token":"testprojecttoken"}}]"#

        let actual = try #require(sut.requests(for: [record]).requests.first).body

        #expect(String(decoding: actual.body, as: UTF8.self) == expected)
    }

    @Test("$wifi is true on Wi-Fi alone, and false on any other connection", arguments: [
        (NetworkKey.Value.wifi, true), (.cellular, false), (.wiredEthernet, false), (.other, false), (.offline, false),
    ])
    func wifi(network: NetworkKey.Value, expected: Bool) throws {
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [Opened.schema]))
        var context = ServiceContext.topLevel
        context[NetworkKey.self] = network
        let record = EventRecord(event: Opened(count: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)

        let body = try #require(sut.requests(for: [record]).requests.first).body.body
        let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        let actual = (event["properties"] as? [String: Any])?["$wifi"] as? Bool

        #expect(actual == expected)
    }

    @Test("An application with no version or build sends neither, and one with a build alone sends $app_build_number")
    func partialApplication() throws {
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [Opened.schema]))
        var noneContext = ServiceContext.topLevel
        noneContext[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: nil, build: nil)
        var buildContext = ServiceContext.topLevel
        buildContext[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: nil, version: nil, build: "418")
        let none = EventRecord(event: Opened(count: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: noneContext)
        let build = EventRecord(event: Opened(count: 2), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: buildContext)
        let expectedNone = ["$insert_id", "count", "distinct_id", "ip", "time", "token"]
        let expectedBuild = ["$app_build_number", "$insert_id", "count", "distinct_id", "ip", "time", "token"]

        let body = try #require(sut.requests(for: [none, build]).requests.first).body.body
        let events = try #require(try JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        let actual = events.map { ($0["properties"] as? [String: Any])?.keys.sorted() ?? [] }

        #expect(actual == [expectedNone, expectedBuild])
    }

    @Test("The bundle identifier, form factor and locale have no Mixpanel property and aren't sent, in any form", arguments: [
        DeviceKey.Value.FormFactor.phone, .pad, .mac, .tv, .watch, .vision,
    ])
    func unmappedLeftOut(formFactor: DeviceKey.Value.FormFactor) throws {
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [Opened.schema]))
        var context = ServiceContext.topLevel
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: nil, build: nil)
        context[DeviceKey.self] = DeviceKey.Value(model: "Model1,1", formFactor: formFactor)
        context[LocaleKey.self] = Locale(identifier: "pt_BR")
        // A fixed identifier, so the search below can't match a random UUID.
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: Opened(count: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        let expectedKeys = ["$insert_id", "$model", "count", "distinct_id", "ip", "time", "token"]

        let body = try #require(sut.requests(for: [record]).requests.first).body.body
        let text = String(decoding: body, as: UTF8.self)
        let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        let actual = try #require(event["properties"] as? [String: Any]).keys.sorted()

        #expect(actual == expectedKeys)
        #expect(!text.contains("com.example.shop"))
        #expect(!text.contains("pt-BR"))
        #expect(!text.contains("pt_BR"))
        #expect(!text.contains("\(formFactor)"))
    }

    @Test("A context with only a session adds only the session; the sample rate isn't sent")
    func sessionOnly() throws {
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [Opened.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
        context[SampleRateKey.self] = try SampleRate(0.5)
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: Opened(count: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        let expected = ["$device_id", "$insert_id", "count", "distinct_id", "ip", "time", "token"]

        let body = try #require(sut.requests(for: [record]).requests.first).body.body
        let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        let actual = try #require(event["properties"] as? [String: Any]).keys.sorted()

        #expect(actual == expected)
        #expect(!String(decoding: body, as: UTF8.self).contains("0.5"))
    }

    @Test("An event's own properties named as a default property without its $ stay as they are, beside the context's")
    func propertyNamedAsADefault() throws {
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [Upgraded.schema]))
        var context = ServiceContext.topLevel
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
        context[DeviceKey.self] = DeviceKey.Value(model: "iPhone17,1", formFactor: .phone)
        let record = EventRecord(event: Upgraded(os: "web", model: "pro"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        let expected: [String: String] = ["$model": "iPhone17,1", "$os": "iOS", "model": "pro", "os": "web"]

        let body = try #require(sut.requests(for: [record]).requests.first).body.body
        let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        let properties = try #require(event["properties"] as? [String: Any])
        let actual = properties.compactMapValues { $0 as? String }.filter { expected.keys.contains($0.key) }

        #expect(actual == expected)
    }
}
