import Foundation
import Events
import StoreAnalytics
import Testing
import Trackers

@Suite("ConsentPreferences")
struct ConsentPreferencesTests {
    @Test("Decisions saved on one launch are restored on the next")
    func restored() throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ConsentPreferencesTests-\(UUID().uuidString)/consent.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let firstLaunch = ConsentPreferences(file: file)
        firstLaunch.grant(.analytics)
        firstLaunch.deny(.advertising)
        let expected: [ConsentStatus] = [.granted, .undecided, .denied]

        let sut = ConsentPreferences(file: file)

        let actual = ConsentPreferences.categories.map { sut.status(of: $0) }
        #expect(actual == expected)
        #expect(sut.consent.status(of: .advertising) == .denied)
    }

    @Test("Without a saved file every category is undecided, so the preferences aren't complete")
    func noFile() {
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ConsentPreferencesTests-\(UUID().uuidString)/consent.json")
        let expected: [ConsentStatus] = [.undecided, .undecided, .undecided]

        let sut = ConsentPreferences(file: file)

        let actual = ConsentPreferences.categories.map { sut.status(of: $0) }
        #expect(actual == expected)
        #expect(!sut.isComplete)
    }

    @Test("A file that isn't saved decisions restores none")
    func unreadableFile() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ConsentPreferencesTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("consent.json")
        try Data("not json".utf8).write(to: file)
        let expected = ConsentStatus.undecided

        let sut = ConsentPreferences(file: file)

        #expect(sut.status(of: .analytics) == expected)
    }

    @Test("The preferences are complete once every category is granted or denied")
    func complete() {
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ConsentPreferencesTests-\(UUID().uuidString)/consent.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let sut = ConsentPreferences(file: file)

        sut.grant(.analytics)
        sut.grant(.functional)
        let beforeLast = sut.isComplete
        sut.deny(.advertising)

        #expect(!beforeLast)
        #expect(sut.isComplete)
    }
}
