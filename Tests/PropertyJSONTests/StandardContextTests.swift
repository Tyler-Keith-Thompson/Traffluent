import EventMacros
import Foundation
import Instrumentation
import JSONValues
import PropertyJSON
import Sessions
import StandardContext
import Testing

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("EventRecord.standardContext")
private struct StandardContextTests {
    @Event(name: "opened")
    struct Opened {}

    @Test("A hand-worked context is the standard keys as JSON, and other keys aren't in it")
    func handWorked() throws {
        var context = ServiceContext.topLevel
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: "418")
        context[DeviceKey.self] = DeviceKey.Value(model: "iPhone17,1", formFactor: .phone)
        context[LocaleKey.self] = Locale(identifier: "en_US")
        context[NetworkKey.self] = .wifi
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
        context[SessionKey.self] = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
        let sut = EventRecord(event: Opened(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expected: [String: JSON] = [
            "application": .object(["bundleIdentifier": .string("com.example.shop"), "version": .string("2.4.1"), "build": .string("418")]),
            "device": .object(["model": .string("iPhone17,1"), "formFactor": .string("phone")]),
            "locale": .string("en-US"),
            "network": .string("wifi"),
            "operatingSystem": .object(["name": .string("iOS"), "version": .string("26.1.0")]),
        ]

        let actual = sut.standardContext

        #expect(actual == expected)
    }

    @Test("A context with no standard keys is empty")
    func empty() {
        let sut = EventRecord(event: Opened(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected: [String: JSON] = [:]

        let actual = sut.standardContext

        #expect(actual == expected)
    }

    @Test("An application whose values are all nil is an empty object, each missing value left out")
    func applicationWithoutValues() {
        var context = ServiceContext.topLevel
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: nil, version: "1.0", build: nil)
        let sut = EventRecord(event: Opened(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expected: [String: JSON] = ["application": .object(["version": .string("1.0")])]

        let actual = sut.standardContext

        #expect(actual == expected)
    }

    @Test("Every form factor is spelled out by name", arguments: [
        (DeviceKey.Value.FormFactor.phone, "phone"), (.pad, "pad"), (.mac, "mac"), (.tv, "tv"), (.watch, "watch"), (.vision, "vision"),
    ])
    func formFactors(formFactor: DeviceKey.Value.FormFactor, expected: String) {
        var context = ServiceContext.topLevel
        context[DeviceKey.self] = DeviceKey.Value(model: "m", formFactor: formFactor)
        let sut = EventRecord(event: Opened(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)

        let actual = sut.standardContext["device"]

        #expect(actual == .object(["model": .string("m"), "formFactor": .string(expected)]))
    }

    @Test("Every network is spelled out by name", arguments: [
        (NetworkKey.Value.wifi, "wifi"), (.cellular, "cellular"), (.wiredEthernet, "wiredEthernet"), (.other, "other"), (.offline, "offline"),
    ])
    func networks(network: NetworkKey.Value, expected: String) {
        var context = ServiceContext.topLevel
        context[NetworkKey.self] = network
        let sut = EventRecord(event: Opened(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)

        let actual = sut.standardContext["network"]

        #expect(actual == .string(expected))
    }

    @Test("Flattened, the standard context is one level of dotted keys, as a vendor of scalars takes it")
    func flattened() throws {
        var context = ServiceContext.topLevel
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
        context[NetworkKey.self] = .cellular
        let sut = EventRecord(event: Opened(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expected: [String: JSON] = ["operatingSystem.name": .string("iOS"), "operatingSystem.version": .string("26.1.0"), "network": .string("cellular")]

        let actual = try sut.standardContext.flattened()

        #expect(actual == expected)
    }
}
