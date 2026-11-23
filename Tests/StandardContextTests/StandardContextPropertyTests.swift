import Events
import Foundation
import PropertyBased
import StandardContext
import Testing
import Trackers
import TraffluentTestSupport

@Suite("StandardContext: against a naive model", .timeLimit(.minutes(1)))
struct StandardContextPropertyTests {
    struct Tapped: Event {
        var number: Int
    }

    @Test("Any list of standard enrichers, in any order and repeated, sets exactly the keys of the enrichers in it, each to its own value", .tags(.randomized))
    func setsExactlyTheirKeys() async {
        await propertyCheck(count: 100, input: Gen.int(in: 0 ... 5).array(of: 0 ... 12)) { choices in
            let application = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: "418")
            let device = DeviceKey.Value(model: "iPad16,3", formFactor: .pad)
            let operatingSystem = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
            let locale = Locale(identifier: "fr_CA")
            let vendorIdentifier = UUID(uuid: (0x6F, 0x1C, 0x2A, 0x7E, 0x3B, 0x9D, 0x4C, 0x55, 0x9E, 0x21, 0x0A, 0x4B, 0x7C, 0x8D, 0x9E, 0x10))
            let enrichers: [Enricher] = choices.map { choice in
                switch choice {
                case 0: .application(application)
                case 1: .device(device)
                case 2: .operatingSystem(operatingSystem)
                case 3: .locale(locale)
                case 4: .network { .cellular }
                default: .vendorIdentifier(vendorIdentifier)
                }
            }

            // The model: the keys of the enrichers chosen, each with its value.
            let chosen = Set(choices)
            let expected = [
                chosen.contains(0) ? "application \(application)" : nil,
                chosen.contains(1) ? "device \(device)" : nil,
                chosen.contains(2) ? "operatingSystem \(operatingSystem)" : nil,
                chosen.contains(3) ? "locale \(locale.identifier)" : nil,
                chosen.contains(4) ? "network \(NetworkKey.Value.cellular)" : nil,
                chosen.contains(5) ? "vendorIdentifier \(vendorIdentifier)" : nil,
            ].compactMap { $0 }

            let sut = Tracker(enrichers: enrichers)
            sut.track(Tapped(number: 1))
            await sut.finish()

            var records = sut.records.makeAsyncIterator()
            let record = try #require(await records.next())
            let context = record.context
            let actual = [
                context[ApplicationKey.self].map { "application \($0)" },
                context[DeviceKey.self].map { "device \($0)" },
                context[OperatingSystemKey.self].map { "operatingSystem \($0)" },
                context[LocaleKey.self].map { "locale \($0.identifier)" },
                context[NetworkKey.self].map { "network \($0)" },
                context[VendorIdentifierKey.self].flatMap(record.reveal).map { "vendorIdentifier \($0)" },
            ].compactMap { $0 }
            #expect(actual == expected)
        }
    }
}
