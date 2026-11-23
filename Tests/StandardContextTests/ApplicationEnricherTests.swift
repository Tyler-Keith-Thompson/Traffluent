import Events
import Foundation
import StandardContext
import Testing
import Trackers

@Suite("StandardContext: the application", .timeLimit(.minutes(1)))
struct ApplicationEnricherTests {
    struct Tapped: Event {
        var number: Int
    }

    @Test("The application enricher sets ApplicationKey to the value it was made with, on every record")
    func setsTheGivenValue() async throws {
        let expected = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: "418")
        let sut = Tracker(enrichers: [.application(expected)])

        sut.track(Tapped(number: 1))
        sut.track(Tapped(number: 2))
        await sut.finish()

        var actual: [ApplicationKey.Value?] = []
        for await record in sut.records {
            actual.append(record.context[ApplicationKey.self])
        }
        #expect(actual == [expected, expected])
    }

    @Test("The running app is the main bundle's identifier, short version and build")
    func currentIsTheMainBundle() {
        let expected = ApplicationKey.Value(
            bundleIdentifier: Bundle.main.bundleIdentifier,
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        )

        let actual = ApplicationKey.Value.current

        #expect(actual == expected)
    }

    #if canImport(Darwin)
    @Test("A bundle's values are its CFBundleIdentifier, its CFBundleShortVersionString as the version and its CFBundleVersion as the build")
    func readsTheBundle() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "StandardContext-\(UUID().uuidString).bundle")
        defer { try? FileManager.default.removeItem(at: directory) }
        let contents = directory.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: String] = [
            "CFBundleIdentifier": "com.example.shop",
            "CFBundleShortVersionString": "2.4.1",
            "CFBundleVersion": "418",
            "CFBundlePackageType": "BNDL",
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appending(path: "Info.plist"))
        let bundle = try #require(Bundle(url: directory))
        let expected = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: "418")

        let actual = ApplicationKey.Value(bundle: bundle)

        #expect(actual == expected)
    }

    @Test("A bundle with no Info.plist values gives nil for each")
    func emptyBundle() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "StandardContext-\(UUID().uuidString).bundle")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bundle = try #require(Bundle(url: directory))
        let expected = ApplicationKey.Value(bundleIdentifier: nil, version: nil, build: nil)

        let actual = ApplicationKey.Value(bundle: bundle)

        #expect(actual == expected)
    }
    #endif
}
