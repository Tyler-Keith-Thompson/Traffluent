import Clocks
import Events
import Foundation
import Persistence
import Sessions
import SystemPackage
import Testing
import Trackers

@Suite("Sessions: random and in memory only", .timeLimit(.minutes(1)))
struct SessionMemoryTests {
    struct Tapped: Event, BinaryCodable, Equatable {
        var number: Int

        init(number: Int) {
            self.number = number
        }

        func encode(to encoder: inout BinaryEncoder) {
            encoder.encodeMap { map in
                map.encode(number, forKey: "number")
            }
        }

        init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
            var map = try decoder.decodeMap()
            number = try map.decode(forKey: "number")
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

    @Test("Nothing about a session reaches the disk: a store's directory holds the same files as without sessions, none holding an identifier, and the user defaults hold none")
    func nothingWritten() async throws {
        let clock = TestClock()
        let origin = Date(timeIntervalSinceReferenceDate: 1_000)
        let root = FileManager.default.temporaryDirectory.appending(path: "Sessions-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let withSessions = root.appending(path: "with")
        let without = root.appending(path: "without")
        let events: [any (Event & BinaryCodable).Type] = [Tapped.self, SessionStarted.self, SessionEnded.self]
        let sessionStore = try SegmentStore(events: events, directory: FilePath(withSessions.path(percentEncoded: false)))
        let controlStore = try SegmentStore(events: events, directory: FilePath(without.path(percentEncoded: false)))
        let sut = Tracker(store: sessionStore, enrichers: [.sessions(timeout: .seconds(60))], now: {
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

        var ids: Set<UUID> = []
        for await record in sut.records {
            ids.insert(try #require(record.context[SessionKey.self]))
        }
        func names(in directory: URL) throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
        }
        func contains(_ bytes: [UInt8], _ needle: [UInt8]) -> Bool {
            guard bytes.count >= needle.count else { return false }
            return (0 ... bytes.count - needle.count).contains { bytes[$0 ..< $0 + needle.count].elementsEqual(needle) }
        }
        let expectedNames = try names(in: without)
        let actualNames = try names(in: withSessions)
        let defaults = UserDefaults.standard.dictionaryRepresentation().values.map { String(describing: $0) }
        #expect(ids.count == 2)
        #expect(actualNames == expectedNames)
        for name in actualNames {
            let bytes = try Array(Data(contentsOf: withSessions.appending(path: name)))
            for id in ids {
                #expect(!contains(bytes, Array(id.uuidString.utf8)))
                #expect(!contains(bytes, Array(id.uuidString.lowercased().utf8)))
                #expect(!contains(bytes, withUnsafeBytes(of: id.uuid) { Array($0) }))
            }
        }
        for id in ids {
            #expect(!defaults.contains { $0.localizedCaseInsensitiveContains(id.uuidString) })
        }
    }

    @Test("Records a store kept from an earlier run carry no session: they aren't enriched again")
    func recoveredRecordsHaveNoSession() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "Sessions-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = FilePath(directory.path(percentEncoded: false))
        let events: [any (Event & BinaryCodable).Type] = [Tapped.self, SessionStarted.self, SessionEnded.self]
        do {
            let store = try SegmentStore(events: events, directory: path)
            let earlier = Tracker(store: store, enrichers: [.sessions()])
            earlier.track(Tapped(number: 1))
            await earlier.finish()
            store.synchronize()
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
        #expect(actual == expected)
        #expect(records[0].context[SessionKey.self] == nil)
        #expect(records[1].context[SessionKey.self] == nil)
        #expect(records[2].context[SessionKey.self] != nil)
    }
}
