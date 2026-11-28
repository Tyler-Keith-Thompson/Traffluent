import Clocks
import Events
import Foundation
import Persistence
import Sessions
import SystemPackage
import Testing
import Trackers

@Suite("Sessions: random, and on disk only beside their records", .timeLimit(.minutes(1)))
struct SessionMemoryTests {
    struct Tapped: Event, Codable, Equatable {
        var number: Int

        init(number: Int) {
            self.number = number
        }

    }

    @Test("A new tracker, as on a relaunch, starts a new session with a new identifier, a version 7 UUID")
    func newTrackerNewSession() async throws {
        let first = Tracker(enrichers: [.sessions(kinds: [])])
        let second = Tracker(enrichers: [.sessions(kinds: [])])
        let expectedVersion: UInt8 = 7

        first.track(Tapped(number: 1))
        second.track(Tapped(number: 1))
        await first.finish()
        await second.finish()

        var firstRecords = first.records.makeAsyncIterator()
        var secondRecords = second.records.makeAsyncIterator()
        let firstID = try #require(await firstRecords.next()?.context[SessionKey.self])
        let secondID = try #require(await secondRecords.next()?.context[SessionKey.self])
        #expect(firstID != secondID)
        #expect(firstID.uuid.6 >> 4 == expectedVersion)
        #expect(secondID.uuid.6 >> 4 == expectedVersion)
    }

    @Test("A session reaches the disk only inside its records, once in each, and is gone once they are delivered: the store's files are the same as without sessions, and the user defaults hold none")
    func writtenOnlyWithItsRecords() async throws {
        let clock = TestClock()
        let origin = Date(timeIntervalSinceReferenceDate: 1_000)
        let root = FileManager.default.temporaryDirectory.appending(path: "Sessions-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let withSessions = root.appending(path: "with")
        let without = root.appending(path: "without")
        let events: [any (Event & Codable).Type] = [Tapped.self, SessionStarted.self, SessionEnded.self]
        let sessionStore = try SegmentStore(events: events, directory: FilePath(withSessions.path(percentEncoded: false)))
        let controlStore = try SegmentStore(events: events, directory: FilePath(without.path(percentEncoded: false)))
        let sut = Tracker(store: sessionStore, enrichers: [try .sessions(timeout: .seconds(60))], now: {
            let elapsed = TestClock<Duration>.Instant().duration(to: clock.now).components
            return origin.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) * 1e-18)
        })
        let control = Tracker(store: controlStore)

        // A start, an event in the same session, then an end and a new start.
        sut.track(Tapped(number: 1))
        await clock.advance(by: .seconds(1))
        sut.track(Tapped(number: 2))
        await clock.advance(by: .seconds(60))
        sut.track(Tapped(number: 3))
        await sut.finish()
        for event in [SessionStarted(), Tapped(number: 1), Tapped(number: 2), SessionEnded(duration: .seconds(1)), SessionStarted(), Tapped(number: 3)] as [any Event] {
            control.track(event)
        }
        await control.finish()
        sessionStore.synchronize()
        controlStore.synchronize()

        var records: [EventRecord] = []
        for await record in sut.records {
            records.append(record)
        }
        let sessions = try records.map { try #require($0.context[SessionKey.self]) }
        func names(in directory: URL) throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
        }
        func occurrences(of needle: [UInt8], in bytes: [UInt8]) -> Int {
            guard bytes.count >= needle.count else { return 0 }
            return (0 ... bytes.count - needle.count).count { bytes[$0 ..< $0 + needle.count].elementsEqual(needle) }
        }
        func stored() throws -> [[UInt8]] {
            try names(in: withSessions).map { try Array(Data(contentsOf: withSessions.appending(path: $0))) }
        }
        let expectedNames = try names(in: without)
        let actualNames = try names(in: withSessions)
        let before = try stored()
        for record in records {
            if let tag = record.deliveryTag {
                tag.acknowledger.acknowledge([tag.position])
            }
        }
        let after = try stored()
        let defaults = UserDefaults.standard.dictionaryRepresentation().values.map { String(describing: $0) }
        #expect(Set(sessions).count == 2)
        #expect(actualNames == expectedNames)
        for id in Set(sessions) {
            let expectedCount = sessions.count { $0 == id }
            let actualCount = before.reduce(0) { $0 + occurrences(of: Array(id.uuidString.utf8), in: $1) }
            let lowercaseCount = before.reduce(0) { $0 + occurrences(of: Array(id.uuidString.lowercased().utf8), in: $1) }
            let rawCount = before.reduce(0) { $0 + occurrences(of: withUnsafeBytes(of: id.uuid) { Array($0) }, in: $1) }
            let afterCount = after.reduce(0) { $0 + occurrences(of: Array(id.uuidString.utf8), in: $1) }
            #expect(actualCount == expectedCount)
            #expect(lowercaseCount == 0)
            #expect(rawCount == 0)
            #expect(afterCount == 0)
            #expect(!defaults.contains { $0.localizedCaseInsensitiveContains(id.uuidString) })
        }
        #expect(after.isEmpty)
    }

    @Test("Records a store kept from an earlier run carry the session they were tracked in, not the new tracker's: they aren't enriched again")
    func recoveredRecordsKeepTheirSession() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "Sessions-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = FilePath(directory.path(percentEncoded: false))
        let events: [any (Event & Codable).Type] = [Tapped.self, SessionStarted.self, SessionEnded.self]
        let earlierSession: UUID?
        do {
            let store = try SegmentStore(events: events, directory: path)
            let earlier = Tracker(store: store, enrichers: [.sessions()])
            earlier.track(Tapped(number: 1))
            await earlier.finish()
            store.synchronize()
            var earlierRecords = earlier.records.makeAsyncIterator()
            earlierSession = await earlierRecords.next()?.context[SessionKey.self]
        }
        let expected = ["SessionStarted()", "Tapped(number: 1)", "SessionStarted()", "Tapped(number: 2)"]
        let store = try SegmentStore(events: events, directory: path)
        let sut = Tracker(store: store, enrichers: [.sessions()])

        sut.track(Tapped(number: 2))
        await sut.finish()

        var records: [EventRecord] = []
        for await record in sut.records {
            records.append(record)
        }
        let actual = records.map { String(describing: $0.event) }
        let expectedEarlier = try #require(earlierSession)
        #expect(actual == expected)
        #expect(records[0].context[SessionKey.self] == expectedEarlier)
        #expect(records[1].context[SessionKey.self] == expectedEarlier)
        #expect(records[2].context[SessionKey.self] != nil)
        #expect(records[2].context[SessionKey.self] != expectedEarlier)
        #expect(records[3].context[SessionKey.self] == records[2].context[SessionKey.self])
    }
}
