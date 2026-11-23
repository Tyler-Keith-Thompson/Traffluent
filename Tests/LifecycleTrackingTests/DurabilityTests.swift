#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif
import Destinations
import DestinationTesting
import Events
import Foundation
import LifecycleTracking
import Persistence
import Synchronization
import SystemPackage
import Testing
import Trackers

@Suite("trackLifecycle: durability", .timeLimit(.minutes(1)))
struct DurabilityTests {
    struct Tapped: Event, BinaryCodable, Equatable {
        var number: Int

        init(number: Int) {
            self.number = number
        }

        func encode(to encoder: inout BinaryEncoder) {
            encoder.encode(number)
        }

        init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
            number = try decoder.decode()
        }
    }

    /// A store that keeps nothing, noting each append and synchronize in order.
    final class RecordingStore: RecordStore {
        let calls = Mutex<[String]>([])
        let synchronizations: AsyncStream<Void>
        private let synchronized: AsyncStream<Void>.Continuation

        init() {
            (synchronizations, synchronized) = AsyncStream.makeStream(of: Void.self)
        }

        func append(_ record: EventRecord) -> EventRecord {
            calls.withLock { $0.append("append \(type(of: record.event).name)") }
            return record
        }

        func takeRecoveredRecords() -> [EventRecord] { [] }

        func synchronize() {
            calls.withLock { $0.append("synchronize") }
            synchronized.yield()
        }
    }

    @Test("Finishing the lifecycle writes every record tracked before it to the store, then synchronizes the store")
    func finishSynchronizes() async {
        let store = RecordingStore()
        let tracker = Tracker(store: store)
        let expected = ["append Tapped", "append ApplicationTerminated", "synchronize"]
        tracker.track(Tapped(number: 1))

        let sut = tracker.trackLifecycle(kinds: [.terminated], version: nil, versionStore: InMemoryVersionStore(), notificationCenter: NotificationCenter())
        await sut.finish()

        let actual = store.calls.withLock { $0 }
        #expect(actual == expected)
        await tracker.finish()
    }

    @Test("A tracker without a store finishes its lifecycle without synchronizing anything")
    func finishWithoutStore() async {
        let tracker = Tracker()
        let expected = ["ApplicationTerminated()"]

        let sut = tracker.trackLifecycle(kinds: [.terminated], version: nil, versionStore: InMemoryVersionStore(), notificationCenter: NotificationCenter())
        await sut.finish()
        await tracker.finish()

        var actual: [String] = []
        for await record in tracker.records {
            actual.append(String(describing: record.event))
        }
        #expect(actual == expected)
    }

    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
    @Test("Moving to the background writes every record tracked before it to the store, then synchronizes the store")
    func backgroundSynchronizes() async {
        let center = NotificationCenter()
        let store = RecordingStore()
        let tracker = Tracker(store: store)
        let expected = ["append Tapped", "append Tapped", "append ApplicationBackgrounded", "synchronize"]
        tracker.track(Tapped(number: 1))
        tracker.track(Tapped(number: 2))
        let sut = tracker.trackLifecycle(kinds: [.backgrounded], version: nil, versionStore: InMemoryVersionStore(), notificationCenter: center)
        var synchronizations = store.synchronizations.makeAsyncIterator()

        center.post(name: NSApplication.didResignActiveNotification, object: nil)

        await synchronizations.next()
        let actual = store.calls.withLock { $0 }
        #expect(actual == expected)
        sut.cancel()
        await tracker.finish()
    }

    @Test("Moving to the background with backgrounding turned off still synchronizes the store")
    func backgroundOffSynchronizes() async {
        let center = NotificationCenter()
        let store = RecordingStore()
        let tracker = Tracker(store: store)
        let expected = ["append Tapped", "synchronize"]
        tracker.track(Tapped(number: 1))
        let sut = tracker.trackLifecycle(kinds: [], version: nil, versionStore: InMemoryVersionStore(), notificationCenter: center)
        var synchronizations = store.synchronizations.makeAsyncIterator()

        center.post(name: NSApplication.didResignActiveNotification, object: nil)

        await synchronizations.next()
        let actual = store.calls.withLock { $0 }
        #expect(actual == expected)
        sut.cancel()
        await tracker.finish()
    }

    @Test("Termination writes every record tracked before it to the store, then synchronizes the store")
    func terminationSynchronizes() async {
        let center = NotificationCenter()
        let store = RecordingStore()
        let tracker = Tracker(store: store)
        let expected = ["append Tapped", "append ApplicationTerminated", "synchronize"]
        tracker.track(Tapped(number: 1))
        let sut = tracker.trackLifecycle(kinds: [.terminated], version: nil, versionStore: InMemoryVersionStore(), notificationCenter: center)
        var synchronizations = store.synchronizations.makeAsyncIterator()

        center.post(name: NSApplication.willTerminateNotification, object: nil)

        await synchronizations.next()
        let actual = store.calls.withLock { $0 }
        #expect(actual == expected)
        sut.cancel()
        await tracker.finish()
    }

    @Test("A delivery batched by the lifecycle strategy sends what is pending as the app moves to the background")
    func backgroundFlushesBatch() async throws {
        let center = NotificationCenter()
        let tracker = Tracker()
        let recorder = InMemoryDestination()
        let expected = ["Tapped(number: 1)", "Tapped(number: 2)", "ApplicationBackgrounded()"]
        tracker.track(Tapped(number: 1))
        tracker.track(Tapped(number: 2))
        let sut = tracker.trackLifecycle(kinds: [.backgrounded], version: nil, versionStore: InMemoryVersionStore(), notificationCenter: center)
        let delivery = Task {
            try await tracker.records.batch(strategy: .lifecycle).deliver(to: recorder).execute()
        }
        var deliveries = recorder.deliveries.makeAsyncIterator()

        center.post(name: NSApplication.didResignActiveNotification, object: nil)

        let batch = try #require(await deliveries.next())
        let actual = batch.map { String(describing: $0.event) }
        #expect(actual == expected)
        sut.cancel()
        await tracker.finish()
        try await delivery.value
    }

    @Test("No record accepted before the app moved to the background is lost when it is killed there and relaunched")
    func relaunch() async throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "LifecycleTracking-\(UUID().uuidString)").path(percentEncoded: false)
        let killed = path + "-killed"
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: killed)
        }
        let events: [any (Event & BinaryCodable).Type] = [Tapped.self, ApplicationBackgrounded.self]
        final class SynchronizationSignallingStore: RecordStore {
            let store: SegmentStore
            let synchronizations: AsyncStream<Void>
            private let synchronized: AsyncStream<Void>.Continuation

            init(_ store: SegmentStore) {
                self.store = store
                (synchronizations, synchronized) = AsyncStream.makeStream(of: Void.self)
            }

            func append(_ record: EventRecord) -> EventRecord { store.append(record) }
            func takeRecoveredRecords() -> [EventRecord] { store.takeRecoveredRecords() }
            func synchronize() {
                store.synchronize()
                synchronized.yield()
            }
        }
        let center = NotificationCenter()
        let store = SynchronizationSignallingStore(try SegmentStore(events: events, directory: FilePath(path)))
        let tracker = Tracker(store: store)
        let expected = ["Tapped(number: 1)", "Tapped(number: 2)", "ApplicationBackgrounded()"]
        tracker.track(Tapped(number: 1))
        let observation = tracker.trackLifecycle(kinds: [.backgrounded], version: nil, versionStore: InMemoryVersionStore(), notificationCenter: center)
        var synchronizations = store.synchronizations.makeAsyncIterator()
        tracker.track(Tapped(number: 2))

        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        await synchronizations.next()
        // Killed in the background: what is on disk now is all the next launch gets.
        try FileManager.default.copyItem(atPath: path, toPath: killed)
        let relaunched = try SegmentStore(events: events, directory: FilePath(killed))

        let actual = relaunched.takeRecoveredRecords().map { String(describing: $0.event) }
        #expect(actual == expected)
        observation.cancel()
        await tracker.finish()
    }
    #endif
}
