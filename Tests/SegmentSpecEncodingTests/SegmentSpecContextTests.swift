import EventMacros
import Foundation
import Instrumentation
import Persistence
import SegmentSpecEncoding
import Sessions
import StandardContext
import Testing
import Trackers
import TrackingPlans

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("SegmentSpecBatchEncoder: context")
private struct SegmentSpecContextTests {
    @Event(name: "opened")
    struct Opened {
        var count: Int
    }

    @Event(name: "upgraded")
    struct Upgraded {
        var os: String
        var app: String
        var ip: String
    }

    // https://segment.com/docs/connections/spec/common/#context
    @Test("The standard context is the spec's context fields: app, device, locale, network and os, with ip 0.0.0.0")
    func fields() throws {
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [Opened.schema]))
        var context = ServiceContext.topLevel
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: "418")
        context[DeviceKey.self] = DeviceKey.Value(model: "Mac16,1", formFactor: .mac)
        context[LocaleKey.self] = Locale(identifier: "pt_BR")
        context[NetworkKey.self] = .wifi
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "macOS", version: "26.1.0")
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: Opened(count: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        let expected = #"{"batch":[{"anonymousId":"00000000-0000-4000-8000-000000000001","context":{"app":{"build":"418","namespace":"com.example.shop","version":"2.4.1"},"device":{"model":"Mac16,1","type":"macos"},"ip":"0.0.0.0","locale":"pt-BR","network":{"cellular":false,"wifi":true},"os":{"name":"macOS","version":"26.1.0"}},"event":"opened","messageId":"00000000-0000-4000-8000-000000000001","properties":{"count":1},"timestamp":"2026-11-23T14:03:27.000Z","type":"track"}]}"#

        let actual = try #require(sut.requests(for: [record]).requests.first).body

        #expect(String(decoding: actual.body, as: UTF8.self) == expected)
    }

    // analytics-swift's device.type: ios (an iPad's too), tvos, visionos, macos, watchos.
    @Test("device.type is the platform as Segment's Swift library writes it", arguments: [
        (DeviceKey.Value.FormFactor.phone, "ios"), (.pad, "ios"), (.mac, "macos"), (.tv, "tvos"), (.watch, "watchos"), (.vision, "visionos"),
    ])
    func deviceType(formFactor: DeviceKey.Value.FormFactor, expected: String) throws {
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [Opened.schema]))
        var context = ServiceContext.topLevel
        context[DeviceKey.self] = DeviceKey.Value(model: "Model1,1", formFactor: formFactor)
        let record = EventRecord(event: Opened(count: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        let expectedModel = "Model1,1"

        let body = try #require(sut.requests(for: [record]).requests.first).body.body
        let call = try #require(((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["batch"] as? [[String: Any]])?.first)
        let device = try #require((call["context"] as? [String: Any])?["device"] as? [String: Any])

        #expect(device["type"] as? String == expected)
        #expect(device["model"] as? String == expectedModel)
        #expect(device.keys.sorted() == ["model", "type"])
    }

    @Test("network.wifi and network.cellular are each true on their own connection alone, and both false on any other", arguments: [
        (NetworkKey.Value.wifi, true, false), (.cellular, false, true), (.wiredEthernet, false, false), (.other, false, false), (.offline, false, false),
    ])
    func network(network: NetworkKey.Value, expectedWifi: Bool, expectedCellular: Bool) throws {
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [Opened.schema]))
        var context = ServiceContext.topLevel
        context[NetworkKey.self] = network
        let record = EventRecord(event: Opened(count: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)

        let body = try #require(sut.requests(for: [record]).requests.first).body.body
        let call = try #require(((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["batch"] as? [[String: Any]])?.first)
        let actual = try #require((call["context"] as? [String: Any])?["network"] as? [String: Any])

        #expect(actual["wifi"] as? Bool == expectedWifi)
        #expect(actual["cellular"] as? Bool == expectedCellular)
        #expect(actual.keys.sorted() == ["cellular", "wifi"])
    }

    @Test("An application with nothing known sends no app, and one with a build alone sends app.build alone")
    func partialApplication() throws {
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [Opened.schema]))
        var noneContext = ServiceContext.topLevel
        noneContext[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: nil, version: nil, build: nil)
        var buildContext = ServiceContext.topLevel
        buildContext[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: nil, version: nil, build: "418")
        var namespaceContext = ServiceContext.topLevel
        namespaceContext[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: nil, build: nil)
        let batch = [noneContext, buildContext, namespaceContext].map { context in
            EventRecord(event: Opened(count: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        }
        let expected: [[String: String]?] = [nil, ["build": "418"], ["namespace": "com.example.shop"]]

        let body = try #require(sut.requests(for: batch).requests.first).body.body
        let calls = try #require((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["batch"] as? [[String: Any]])
        let actual = calls.map { ($0["context"] as? [String: Any])?["app"] as? [String: String] }

        #expect(actual == expected)
    }

    @Test("A context with only a session sends only ip in context; the sample rate isn't sent")
    func sessionOnly() throws {
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [Opened.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
        context[SampleRateKey.self] = try SampleRate(0.5)
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: Opened(count: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        let expected = ["ip"]

        let body = try #require(sut.requests(for: [record]).requests.first).body.body
        let call = try #require(((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["batch"] as? [[String: Any]])?.first)
        let actual = try #require(call["context"] as? [String: Any]).keys.sorted()

        #expect(actual == expected)
        #expect(!String(decoding: body, as: UTF8.self).contains("0.5"))
    }

    @Test("An event's own properties named as context fields stay in properties, apart from the context")
    func propertyNamedAsAContextField() throws {
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [Upgraded.schema]))
        var context = ServiceContext.topLevel
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
        let record = EventRecord(event: Upgraded(os: "web", app: "pro", ip: "x"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        let expectedProperties: [String: String] = ["app": "pro", "ip": "x", "os": "web"]
        let expectedIP = "0.0.0.0"

        let body = try #require(sut.requests(for: [record]).requests.first).body.body
        let call = try #require(((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["batch"] as? [[String: Any]])?.first)
        let properties = try #require(call["properties"] as? [String: String])
        let callContext = try #require(call["context"] as? [String: Any])

        #expect(properties == expectedProperties)
        #expect(callContext["ip"] as? String == expectedIP)
        #expect((callContext["os"] as? [String: String])?["name"] == "iOS")
    }
}
