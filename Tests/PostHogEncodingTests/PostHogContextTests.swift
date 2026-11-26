import EventMacros
import Foundation
import Instrumentation
import Persistence
import PostHogEncoding
import Sessions
import StandardContext
import Testing
import Trackers
import TrackingPlans

@Suite("PostHogBatchEncoder: context")
struct PostHogContextTests {
    @Event(name: "opened")
    struct Opened {
        var count: Int
    }

    /// Writes a property named as one of PostHog's own, which no `@Event` property can be.
    struct ClaimsTheOperatingSystem: Event, BinaryCodable {
        static let name = "claims_the_operating_system"

        init() {}

        func encode(to encoder: inout BinaryEncoder) {
            encoder.encodeMap { map in
                map.encode("Event's own", forKey: "$os_name")
            }
        }

        init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {}
    }

    @Test("Each form factor is PostHog's $device_type, and a watch has none", arguments: [
        (DeviceKey.Value.FormFactor.phone, "Mobile" as String?),
        (.pad, "Tablet"),
        (.mac, "Desktop"),
        (.tv, "TV"),
        (.vision, "Vision"),
        (.watch, nil),
    ])
    func deviceType(formFactor: DeviceKey.Value.FormFactor, expected: String?) throws {
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: TrackingPlan(schemas: [Opened.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        context[DeviceKey.self] = DeviceKey.Value(model: "Model1,1", formFactor: formFactor)
        let record = EventRecord(event: Opened(count: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expectedModel = "Model1,1"

        let body = try sut.encode([record]).body
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let properties = try #require((object["batch"] as? [[String: Any]])?.first?["properties"] as? [String: Any])
        let actual = properties["$device_type"] as? String

        #expect(actual == expected)
        #expect(properties.keys.contains("$device_type") == (expected != nil))
        #expect(properties["$device_model"] as? String == expectedModel)
    }

    @Test("Each network is PostHog's $network_wifi and $network_cellular", arguments: [
        (NetworkKey.Value.wifi, true, false),
        (.cellular, false, true),
        (.wiredEthernet, false, false),
        (.other, false, false),
        (.offline, false, false),
    ])
    func network(network: NetworkKey.Value, expectedWifi: Bool, expectedCellular: Bool) throws {
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: TrackingPlan(schemas: [Opened.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        context[NetworkKey.self] = network
        let record = EventRecord(event: Opened(count: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)

        let body = try sut.encode([record]).body
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let properties = try #require((object["batch"] as? [[String: Any]])?.first?["properties"] as? [String: Any])
        let actualWifi = properties["$network_wifi"] as? Bool
        let actualCellular = properties["$network_cellular"] as? Bool

        #expect(actualWifi == expectedWifi)
        #expect(actualCellular == expectedCellular)
    }

    @Test("An application's nil bundle identifier, version or build is left out")
    func applicationNilsLeftOut() throws {
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: TrackingPlan(schemas: [Opened.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: nil, version: "1.0", build: nil)
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: Opened(count: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expected = #"{"api_key":"phc_test","batch":[{"distinct_id":"00000000-0000-4000-8000-00000000000a","event":"opened","properties":{"$app_version":"1.0","$geoip_disable":true,"$process_person_profile":false,"count":1},"timestamp":"1970-01-01T00:00:00.000Z","uuid":"00000000-0000-4000-8000-000000000001"}]}"#

        let actual = try sut.encode([record])

        #expect(String(decoding: actual.body, as: UTF8.self) == expected)
    }

    @Test("A context with only a session adds only $geoip_disable and $process_person_profile; the sample rate isn't sent")
    func sessionOnly() throws {
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: TrackingPlan(schemas: [Opened.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        context[SampleRateKey.self] = 0.5
        let record = EventRecord(event: Opened(count: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expected = ["$geoip_disable", "$process_person_profile", "count"]

        let body = try sut.encode([record]).body
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let properties = try #require((object["batch"] as? [[String: Any]])?.first?["properties"] as? [String: Any])
        let actual = properties.keys.sorted()

        #expect(actual == expected)
    }

    @Test("An event's own $os_name is left out, and the context's is sent")
    func contextWins() throws {
        let schema = EventSchema(name: "claims_the_operating_system", version: 1, consentCategory: .analytics, properties: [])
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: TrackingPlan(schemas: [schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
        let record = EventRecord(event: ClaimsTheOperatingSystem(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expected = "iOS"

        let body = try sut.encode([record]).body
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let properties = try #require((object["batch"] as? [[String: Any]])?.first?["properties"] as? [String: Any])
        let actual = properties["$os_name"] as? String

        #expect(actual == expected)
    }

    @Test("A locale is its BCP 47 identifier")
    func locale() throws {
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: TrackingPlan(schemas: [Opened.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        context[LocaleKey.self] = Locale(identifier: "pt_BR")
        let record = EventRecord(event: Opened(count: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expected = "pt-BR"

        let body = try sut.encode([record]).body
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let properties = try #require((object["batch"] as? [[String: Any]])?.first?["properties"] as? [String: Any])
        let actual = properties["$locale"] as? String

        #expect(actual == expected)
    }
}
