import Events
import Foundation
import LifecycleTracking
import Synchronization
import Testing
import Trackers

@Suite("trackLifecycle: installs and updates", .timeLimit(.minutes(1)))
struct VersionChangeTests {
    @Test("A first launch, no version saved, tracks an install, then an open, and saves the version")
    func installed() async {
        let versionStore = InMemoryVersionStore()
        let tracker = Tracker()
        let expected = [
            "ApplicationInstalled(version: \"1.2.0\")",
            "ApplicationOpened(fromBackground: false)",
            "ApplicationTerminated()",
        ]

        let sut = tracker.trackLifecycle(version: "1.2.0", versionStore: versionStore, notificationCenter: NotificationCenter())
        await sut.finish()
        await tracker.finish()

        var actual: [String] = []
        for await record in tracker.records {
            actual.append(String(describing: record.event))
        }
        #expect(actual == expected)
        #expect(versionStore.version == "1.2.0")
    }

    @Test("A launch of a version other than the one saved tracks an update from it, then an open, and saves the new version")
    func updated() async {
        let versionStore = InMemoryVersionStore(version: "1.1.0")
        let tracker = Tracker()
        let expected = [
            "ApplicationUpdated(previousVersion: \"1.1.0\", version: \"1.2.0\")",
            "ApplicationOpened(fromBackground: false)",
            "ApplicationTerminated()",
        ]

        let sut = tracker.trackLifecycle(version: "1.2.0", versionStore: versionStore, notificationCenter: NotificationCenter())
        await sut.finish()
        await tracker.finish()

        var actual: [String] = []
        for await record in tracker.records {
            actual.append(String(describing: record.event))
        }
        #expect(actual == expected)
        #expect(versionStore.version == "1.2.0")
    }

    @Test("A launch of the version saved tracks neither an install nor an update, only an open")
    func unchanged() async {
        let versionStore = InMemoryVersionStore(version: "1.2.0")
        let tracker = Tracker()
        let expected = [
            "ApplicationOpened(fromBackground: false)",
            "ApplicationTerminated()",
        ]

        let sut = tracker.trackLifecycle(version: "1.2.0", versionStore: versionStore, notificationCenter: NotificationCenter())
        await sut.finish()
        await tracker.finish()

        var actual: [String] = []
        for await record in tracker.records {
            actual.append(String(describing: record.event))
        }
        #expect(actual == expected)
        #expect(versionStore.version == "1.2.0")
    }

    @Test("A downgrade is an update too: from the version saved to the one running")
    func downgraded() async {
        let versionStore = InMemoryVersionStore(version: "2.0.0")
        let tracker = Tracker()
        let expected = "ApplicationUpdated(previousVersion: \"2.0.0\", version: \"1.9.0\")"

        let sut = tracker.trackLifecycle(kinds: [.updated], version: "1.9.0", versionStore: versionStore, notificationCenter: NotificationCenter())
        await sut.finish()
        await tracker.finish()

        var actual: [String] = []
        for await record in tracker.records {
            actual.append(String(describing: record.event))
        }
        #expect(actual == [expected])
        #expect(versionStore.version == "1.9.0")
    }

    @Test("Without a version, neither an install nor an update is tracked, and nothing is saved")
    func noVersion() async {
        let versionStore = InMemoryVersionStore()
        let tracker = Tracker()
        let expected = ["ApplicationOpened(fromBackground: false)"]

        let sut = tracker.trackLifecycle(kinds: [.installed, .updated, .opened], version: nil, versionStore: versionStore, notificationCenter: NotificationCenter())
        await sut.finish()
        await tracker.finish()

        var actual: [String] = []
        for await record in tracker.records {
            actual.append(String(describing: record.event))
        }
        #expect(actual == expected)
        #expect(versionStore.version == nil)
    }

    @Test("Installs turned off track no install, but the version is still saved, so turning them on later reports none")
    func installedOff() async {
        let versionStore = InMemoryVersionStore()
        let tracker = Tracker()
        let expected = ["ApplicationOpened(fromBackground: false)"]

        let sut = tracker.trackLifecycle(kinds: [.updated, .opened], version: "1.2.0", versionStore: versionStore, notificationCenter: NotificationCenter())
        await sut.finish()
        await tracker.finish()

        var actual: [String] = []
        for await record in tracker.records {
            actual.append(String(describing: record.event))
        }
        #expect(actual == expected)
        #expect(versionStore.version == "1.2.0")
    }

    @Test("Updates turned off track no update, but the new version is still saved")
    func updatedOff() async {
        let versionStore = InMemoryVersionStore(version: "1.1.0")
        let tracker = Tracker()
        let expected = ["ApplicationOpened(fromBackground: false)"]

        let sut = tracker.trackLifecycle(kinds: [.installed, .opened], version: "1.2.0", versionStore: versionStore, notificationCenter: NotificationCenter())
        await sut.finish()
        await tracker.finish()

        var actual: [String] = []
        for await record in tracker.records {
            actual.append(String(describing: record.event))
        }
        #expect(actual == expected)
        #expect(versionStore.version == "1.2.0")
    }

    @Test("A version store that can't be read tracks neither an install nor an update, and saves nothing")
    func loadFails() async {
        struct Unreadable: Error {}
        final class FailingVersionStore: VersionStore {
            let saves = Mutex(0)
            func load() throws -> String? { throw Unreadable() }
            func save(_ version: String) throws { saves.withLock { $0 += 1 } }
        }
        let versionStore = FailingVersionStore()
        let tracker = Tracker()
        let expected = ["ApplicationOpened(fromBackground: false)"]

        let sut = tracker.trackLifecycle(kinds: [.installed, .updated, .opened], version: "1.2.0", versionStore: versionStore, notificationCenter: NotificationCenter())
        await sut.finish()
        await tracker.finish()

        var actual: [String] = []
        for await record in tracker.records {
            actual.append(String(describing: record.event))
        }
        #expect(actual == expected)
        #expect(versionStore.saves.withLock { $0 } == 0)
    }

    @Test("A version store that can't be written tracks no install, so the next launch doesn't report it twice")
    func saveFails() async {
        struct Unwritable: Error {}
        struct FailingVersionStore: VersionStore {
            func load() throws -> String? { nil }
            func save(_ version: String) throws { throw Unwritable() }
        }
        let tracker = Tracker()
        let expected = ["ApplicationOpened(fromBackground: false)"]

        let sut = tracker.trackLifecycle(kinds: [.installed, .updated, .opened], version: "1.2.0", versionStore: FailingVersionStore(), notificationCenter: NotificationCenter())
        await sut.finish()
        await tracker.finish()

        var actual: [String] = []
        for await record in tracker.records {
            actual.append(String(describing: record.event))
        }
        #expect(actual == expected)
    }

    @Test("A launch of the version saved doesn't write it again")
    func unchangedNotWritten() async {
        final class CountingVersionStore: VersionStore {
            let saves = Mutex(0)
            func load() -> String? { "1.2.0" }
            func save(_ version: String) { saves.withLock { $0 += 1 } }
        }
        let versionStore = CountingVersionStore()
        let tracker = Tracker()

        let sut = tracker.trackLifecycle(version: "1.2.0", versionStore: versionStore, notificationCenter: NotificationCenter())
        await sut.finish()
        await tracker.finish()

        #expect(versionStore.saves.withLock { $0 } == 0)
    }
}
