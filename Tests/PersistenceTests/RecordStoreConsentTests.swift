import Destinations
import Events
import Foundation
import Persistence
import Testing
import Trackers

@Suite("RecordStore: consent", .timeLimit(.minutes(1)))
struct RecordStoreConsentTests {
    struct Tapped: Event, Equatable {
        var number: Int
    }

    /// An event of a category other than Tapped's, whose records are as large as Tapped's: its
    /// name has as many characters.
    struct Opened: Event, Equatable {
        static let consentCategory = ConsentCategory.functional
        var number: Int
    }

    @Test("A record held while undecided isn't written; granting writes it before it is delivered", arguments: StoreKind.all)
    func heldNotWritten(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try kind.open(at: path, events: [Tapped.self]).store
        let consent = Consent()
        let tracker = Tracker(store: store, consent: consent)
        let recorder = InMemoryDestination()
        tracker.track(Tapped(number: 1))
        await tracker.flush()
        let actualHeld = store.pendingRecordCount

        consent.grant(.analytics)
        await tracker.flush()
        let actualGranted = store.pendingRecordCount
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(5)).deliver(to: recorder).execute()

        #expect(actualHeld == 0)
        #expect(actualGranted == 1)
        #expect(recorder.events(of: Tapped.self) == [Tapped(number: 1)])
        #expect(store.pendingRecordCount == 0)
    }

    @Test("A record held then denied is never written", arguments: StoreKind.all)
    func deniedNeverWritten(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try kind.open(at: path, events: [Tapped.self]).store
        let consent = Consent()
        let tracker = Tracker(store: store, consent: consent)

        tracker.track(Tapped(number: 1))
        consent.deny(.analytics)
        tracker.track(Tapped(number: 2))
        await tracker.flush()

        #expect(store.pendingRecordCount == 0)
    }

    @Test("A recovered record whose category is now denied is dropped, reported, and forgotten by the store", arguments: StoreKind.all)
    func recoveredDenied(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let first = try kind.open(at: path, events: [Tapped.self]).store
        let earlier = Tracker(store: first, now: { Date(timeIntervalSince1970: 4) })
        earlier.track(Tapped(number: 1))
        await earlier.finish()
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Tapped.self]).store
        let consent = Consent([.analytics: .denied])
        let recorder = InMemoryDestination()
        let expectedReport = ConsentDropReport.denied(
            category: .analytics, recordCount: 1, timestamps: Date(timeIntervalSince1970: 4) ... Date(timeIntervalSince1970: 4))

        let sut = Tracker(store: next, consent: consent)
        await sut.finish()
        try await sut.records.batch(strategy: .count(5)).deliver(to: recorder).execute()

        var reports = consent.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expectedReport)
        #expect(recorder.records.isEmpty)
        #expect(next.pendingRecordCount == 0)
        let third = copy + "-third"
        defer { try? FileManager.default.removeItem(atPath: third) }
        try FileManager.default.copyItem(atPath: copy, toPath: third)
        #expect(try kind.open(at: third, events: [Tapped.self]).store.takeRecoveredRecords().isEmpty)
    }

    @Test("A recovered record whose category is granted is delivered first, as without a consent", arguments: StoreKind.all)
    func recoveredGranted(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let first = try kind.open(at: path, events: [Tapped.self]).store
        let earlier = Tracker(store: first)
        earlier.track(Tapped(number: 1))
        await earlier.finish()
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Tapped.self]).store
        let recorder = InMemoryDestination()
        let expected = [Tapped(number: 1), Tapped(number: 2)]

        let sut = Tracker(store: next, consent: Consent([.analytics: .granted]))
        sut.track(Tapped(number: 2))
        await sut.finish()
        try await sut.records.batch(strategy: .count(5)).deliver(to: recorder).execute()

        #expect(recorder.events(of: Tapped.self) == expected)
        #expect(next.pendingRecordCount == 0)
    }

    @Test("A recovered record whose category is undecided is held and stays in the store, unreported, when the tracker finishes", arguments: StoreKind.all)
    func recoveredUndecided(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let first = try kind.open(at: path, events: [Tapped.self]).store
        let earlier = Tracker(store: first)
        earlier.track(Tapped(number: 1))
        await earlier.finish()
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Tapped.self]).store
        let consent = Consent()
        let recorder = InMemoryDestination()
        // A tracker finishing with a memory-only record held reports it; as the first report, it
        // shows the finish before it reported nothing.
        let marker = Tracker(consent: consent, now: { Date(timeIntervalSince1970: 99) })
        let expectedReport = ConsentDropReport.finishedUndecided(
            recordCount: 1, timestamps: Date(timeIntervalSince1970: 99) ... Date(timeIntervalSince1970: 99))

        let sut = Tracker(store: next, consent: consent)
        await sut.flush()
        let actualHeld = consent.heldRecordCount
        await sut.finish()
        try await sut.records.batch(strategy: .count(5)).deliver(to: recorder).execute()
        marker.track(Tapped(number: 2))
        await marker.finish()

        var reports = consent.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expectedReport)
        #expect(actualHeld == 1)
        #expect(consent.heldRecordCount == 0)
        #expect(recorder.records.isEmpty)
        #expect(next.pendingRecordCount == 1)
    }

    @Test("A recovered record held then granted is delivered without being written again", arguments: StoreKind.all)
    func recoveredHeldThenGranted(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let first = try kind.open(at: path, events: [Tapped.self]).store
        let earlier = Tracker(store: first)
        earlier.track(Tapped(number: 1))
        await earlier.finish()
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Tapped.self]).store
        let consent = Consent()
        let recorder = InMemoryDestination()
        let sut = Tracker(store: next, consent: consent)

        consent.grant(.analytics)
        await sut.flush()
        let actualPending = next.pendingRecordCount
        await sut.finish()
        try await sut.records.batch(strategy: .count(5)).deliver(to: recorder).execute()

        #expect(actualPending == 1)
        #expect(recorder.events(of: Tapped.self) == [Tapped(number: 1)])
        #expect(next.pendingRecordCount == 0)
    }

    @Test("A recovered record held then denied is dropped, reported, and forgotten by the store", arguments: StoreKind.all)
    func recoveredHeldThenDenied(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let first = try kind.open(at: path, events: [Tapped.self]).store
        let earlier = Tracker(store: first, now: { Date(timeIntervalSince1970: 5) })
        earlier.track(Tapped(number: 1))
        await earlier.finish()
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Tapped.self]).store
        let consent = Consent()
        let expectedReport = ConsentDropReport.denied(
            category: .analytics, recordCount: 1, timestamps: Date(timeIntervalSince1970: 5) ... Date(timeIntervalSince1970: 5))
        let sut = Tracker(store: next, consent: consent)

        consent.deny(.analytics)
        await sut.finish()

        var reports = consent.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expectedReport)
        #expect(next.pendingRecordCount == 0)
        let third = copy + "-third"
        defer { try? FileManager.default.removeItem(atPath: third) }
        try FileManager.default.copyItem(atPath: copy, toPath: third)
        #expect(try kind.open(at: third, events: [Tapped.self]).store.takeRecoveredRecords().isEmpty)
    }

    @Test("Finishing another tracker on the same consent leaves a tracker's recovered held records to it", arguments: StoreKind.all)
    func otherFinishLeavesRecovered(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let first = try kind.open(at: path, events: [Tapped.self]).store
        let earlier = Tracker(store: first)
        earlier.track(Tapped(number: 1))
        await earlier.finish()
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Tapped.self]).store
        let consent = Consent()
        let recorder = InMemoryDestination()
        let sut = Tracker(store: next, consent: consent)
        let other = Tracker(consent: consent)
        await sut.flush()

        await other.finish()
        consent.grant(.analytics)
        await sut.finish()
        try await sut.records.batch(strategy: .count(5)).deliver(to: recorder).execute()

        #expect(recorder.events(of: Tapped.self) == [Tapped(number: 1)])
    }

    @Test("Recovered records are held outside the bound: a hold of 0 keeps them, in the store, and a grant delivers them", arguments: StoreKind.all)
    func recoveredOutsideZeroBound(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let first = try kind.open(at: path, events: [Tapped.self]).store
        let earlier = Tracker(store: first)
        earlier.track(Tapped(number: 1))
        earlier.track(Tapped(number: 2))
        await earlier.finish()
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Tapped.self]).store
        let consent = try Consent(heldRecordLimit: 0)
        let recorder = InMemoryDestination()
        let expected = [Tapped(number: 1), Tapped(number: 2)]
        let sut = Tracker(store: next, consent: consent)

        await sut.flush()
        let actualHeld = consent.heldRecordCount
        let actualPending = next.pendingRecordCount
        consent.grant(.analytics)
        await sut.finish()
        try await sut.records.batch(strategy: .count(5)).deliver(to: recorder).execute()

        #expect(actualHeld == 2)
        #expect(actualPending == 2)
        #expect(recorder.events(of: Tapped.self) == expected)
        #expect(next.pendingRecordCount == 0)
    }

    @Test("More recovered records than the bound all stay in the store when the tracker finishes undecided, for the next launch", arguments: StoreKind.all)
    func recoveredPastBoundKept(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let first = try kind.open(at: path, events: [Tapped.self]).store
        let earlier = Tracker(store: first)
        for number in 1 ... 3 {
            earlier.track(Tapped(number: number))
        }
        await earlier.finish()
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Tapped.self]).store
        let expected = [Tapped(number: 1), Tapped(number: 2), Tapped(number: 3)]

        let sut = Tracker(store: next, consent: try Consent(heldRecordLimit: 1))
        await sut.finish()

        #expect(next.pendingRecordCount == 3)
        let third = copy + "-third"
        defer { try? FileManager.default.removeItem(atPath: third) }
        try FileManager.default.copyItem(atPath: copy, toPath: third)
        let recovered = try kind.open(at: third, events: [Tapped.self]).store.takeRecoveredRecords()
        #expect(recovered.compactMap { $0.event as? Tapped } == expected)
    }

    @Test("Events tracked into a full hold drop each other, never a recovered record", arguments: StoreKind.all)
    func tracksDontEvictRecovered(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let first = try kind.open(at: path, events: [Tapped.self]).store
        let earlier = Tracker(store: first)
        earlier.track(Tapped(number: 1))
        await earlier.finish()
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Tapped.self]).store
        let consent = try Consent(heldRecordLimit: 1)
        let recorder = InMemoryDestination()
        let expected = [Tapped(number: 1), Tapped(number: 3)]
        let expectedReport = ConsentDropReport.heldRecordLimit(
            recordCount: 1, timestamps: Date(timeIntervalSince1970: 2) ... Date(timeIntervalSince1970: 2))
        let sut = Tracker(store: next, consent: consent, now: { Date(timeIntervalSince1970: 2) })

        sut.track(Tapped(number: 2))
        sut.track(Tapped(number: 3))
        consent.grant(.analytics)
        await sut.finish()
        try await sut.records.batch(strategy: .count(5)).deliver(to: recorder).execute()

        var reports = consent.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expectedReport)
        #expect(recorder.events(of: Tapped.self) == expected)
        #expect(next.pendingRecordCount == 0)
    }

    @Test("A held recovered record the store drops for its byte bound is reported by the store and still delivered on grant, as a record already read is", arguments: StoreKind.all)
    func heldRecoveredDroppedByStore(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let first = try kind.open(at: path, events: [Tapped.self, Opened.self]).store
        _ = first.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try await kind.open(at: copy, events: [Tapped.self, Opened.self], holding: 1) { probe in
            _ = probe.append(EventRecord(event: Tapped(number: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        }.store
        let consent = Consent([.functional: .granted])
        let recorder = InMemoryDestination()
        let expectedStoreReport = DropReport.sizeBound(recordCount: 1, timestamps: Date(timeIntervalSince1970: 0) ... Date(timeIntervalSince1970: 0))
        let sut = Tracker(store: next, consent: consent, now: { Date(timeIntervalSince1970: 0) })
        var storeReports = next.dropReports.makeAsyncIterator()

        sut.track(Opened(number: 2), file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let actualStoreReport = await storeReports.next()
        consent.grant(.analytics)
        await sut.finish()
        try await sut.records.batch(strategy: .count(5)).deliver(to: recorder).execute()

        #expect(actualStoreReport == expectedStoreReport)
        #expect(recorder.events(of: Tapped.self) == [Tapped(number: 1)])
        #expect(recorder.events(of: Opened.self) == [Opened(number: 2)])
    }

    @Test("A record with no call site comes back with none after a relaunch", arguments: StoreKind.all)
    func noCallSiteRecovered(kind: StoreKind) throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try kind.open(at: path, events: [Tapped.self]).store
        _ = store.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil))

        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Tapped.self]).store
        let actual = try #require(next.takeRecoveredRecords().first)
        #expect(actual.sourceLocation == nil)
        #expect(actual.event as? Tapped == Tapped(number: 1))
    }
}

extension RecordStoreConsentTests.Tapped: Codable {}

extension RecordStoreConsentTests.Opened: Codable {}
