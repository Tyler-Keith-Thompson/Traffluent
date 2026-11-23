import Events
import Foundation
import StandardContext
import Testing
import Trackers

@Suite("StandardContext: the operating system", .timeLimit(.minutes(1)))
struct OperatingSystemEnricherTests {
    struct Tapped: Event {
        var number: Int
    }

    @Test("The operating system enricher sets OperatingSystemKey to the value it was made with, on every record")
    func setsTheGivenValue() async throws {
        let expected = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
        let sut = Tracker(enrichers: [.operatingSystem(expected)])

        sut.track(Tapped(number: 1))
        sut.track(Tapped(number: 2))
        await sut.finish()

        var actual: [OperatingSystemKey.Value?] = []
        for await record in sut.records {
            actual.append(record.context[OperatingSystemKey.self])
        }
        #expect(actual == [expected, expected])
    }

    @Test("The running system is named for the platform, at ProcessInfo's major, minor and patch version")
    func currentSystem() {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #if os(macOS)
        let expectedName = "macOS"
        #else
        let expectedName = "Linux"
        #endif
        let expected = OperatingSystemKey.Value(
            name: expectedName,
            version: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        )

        let actual = OperatingSystemKey.Value.current

        #expect(actual == expected)
    }
}
