// Exit tests, in a file of their own: each runs its body in a child process, which iOS, tvOS,
// watchOS and visionOS cannot start.
//
// Why child processes: `Tracker.bootstrap` sets the process's default tracker once, and nothing
// can reset it, so every test that bootstraps does it in a child process of its own (see
// TrackerBootstrapExitTests). Each child checks what it sees and exits with a failure when it
// differs from what is expected.

import Foundation
import Events
import Instrumentation
import Persistence
import Testing
import Trackers

@Suite("Tracker.viewDefault with a tracker bootstrapped", .timeLimit(.minutes(1)))
struct ViewDefaultExitTests {
    struct Tapped: Event {
        var number: Int
    }

    enum ScreenKey: ServiceContextKey {
        typealias Value = String
    }

    enum SessionKey: ServiceContextKey {
        typealias Value = String
    }

    struct Scrolled: Event {}

    /// An event whose query must not be empty.
    struct Searched: Event {
        var query: String

        func constraintViolation() -> ConstraintViolation? {
            query.isEmpty ? ConstraintViolation(property: "query", keyword: .minLength(1)) : nil
        }
    }

    /// A store that keeps nothing.
    final class DiscardingStore: RecordStore {
        func append(_ record: EventRecord) -> EventRecord {
            record
        }

        func takeRecoveredRecords() -> [EventRecord] {
            []
        }

        func synchronize() {}
    }

    @Test("A never-set view tracker read before the bootstrap tracks through the bootstrapped tracker, looked up as it tracks, with its clock and the caller's call site")
    func readBeforeBootstrap() async {
        await #expect(processExitsWith: .success) {
            let sut = Tracker.viewDefault(environment: [:])
            let expectedTimestamp = Date(timeIntervalSince1970: 1_000)
            let tracker = Tracker(now: { expectedTimestamp })
            let expected = [1, 2]
            // An explicit call site: inside an exit test's body, the default arguments' #fileID
            // and #line name the macro's expansion, not this file's lines.
            let expectedLocation = Events.SourceLocation(file: "Checkout.swift", fileID: "Store/Checkout.swift", function: "checkOut()", line: 7, column: 9)
            try Tracker.bootstrap(tracker)

            for number in [1, 2] {
                sut.track(Tapped(number: number), file: "Checkout.swift", fileID: "Store/Checkout.swift", function: "checkOut()", line: 7, column: 9)
            }
            await tracker.finish()

            var actual: [Int] = []
            var actualTimestamps: [Date] = []
            var actualLocations: [Events.SourceLocation?] = []
            for await record in tracker.records {
                actual.append((record.event as? Tapped)?.number ?? -1)
                actualTimestamps.append(record.timestamp)
                actualLocations.append(record.sourceLocation)
            }
            guard actual == expected,
                actualTimestamps == [expectedTimestamp, expectedTimestamp],
                actualLocations == [expectedLocation, expectedLocation],
                !sut.isNoOp
            else { exit(EXIT_FAILURE) }
        }
    }

    @Test("A never-set view tracker's enriched copy, made before the bootstrap, reaches the bootstrapped tracker and keeps what it adds, after the bootstrapped tracker's own enrichers and its copy's")
    func enrichedCopy() async {
        await #expect(processExitsWith: .success) {
            let sut = Tracker.viewDefault(environment: [:])
                .enriched(by: Enricher { $0[ScreenKey.self] = "Checkout" })
                .enriched(by: Enricher { $0[ScreenKey.self] = ($0[ScreenKey.self] ?? "") + "/Payment" })
            let tracker = Tracker(enrichers: [Enricher { $0[SessionKey.self] = ($0[SessionKey.self] ?? "") + "s-1" }])
            let expectedScreen = "Checkout/Payment"
            let expectedSession = "copy/s-1"
            try Tracker.bootstrap(tracker.enriched(by: Enricher {
                $0[ScreenKey.self] = "Bootstrapped"
                $0[SessionKey.self] = "copy/"
            }))

            sut.track(Tapped(number: 1))
            Tracker.viewDefault(environment: [:]).track(Tapped(number: 2))
            await tracker.finish()

            var records = tracker.records.makeAsyncIterator()
            guard let record = await records.next(),
                record.context[ScreenKey.self] == expectedScreen,
                record.context[SessionKey.self] == expectedSession,
                let plain = await records.next(),
                plain.context[ScreenKey.self] == "Bootstrapped",
                plain.context[SessionKey.self] == expectedSession,
                await records.next() == nil
            else { exit(EXIT_FAILURE) }
        }
    }

    @Test("Tracker.current inside withTracker given a never-set view tracker, or its enriched copy, is the bootstrapped tracker, not one that drops")
    func boundViewDefault() async {
        await #expect(processExitsWith: .success) {
            let sut = Tracker.viewDefault(environment: [:])
            let tracker = Tracker()
            let expected = [1, 2]
            let expectedScreens: [String?] = [nil, "Checkout"]
            try Tracker.bootstrap(tracker)

            withTracker(sut) {
                Tracker.current.track(Tapped(number: 1))
            }
            withTracker(sut.enriched(by: Enricher { $0[ScreenKey.self] = "Checkout" })) {
                Tracker.current.track(Tapped(number: 2))
            }
            await tracker.finish()

            var actual: [Int] = []
            var actualScreens: [String?] = []
            for await record in tracker.records {
                actual.append((record.event as? Tapped)?.number ?? -1)
                actualScreens.append(record.context[ScreenKey.self])
            }
            guard actual == expected, actualScreens == expectedScreens else { exit(EXIT_FAILURE) }
        }
    }

    @Test("A never-set view tracker's records, store, reports, flush and finish are the bootstrapped tracker's")
    func membersResolve() async {
        await #expect(processExitsWith: .success) {
            let sut = Tracker.viewDefault(environment: [:])
            let consent = Consent()
            let tracker = Tracker(store: DiscardingStore(), consent: consent, samplers: [.events(of: Scrolled.self, rate: try SampleRate(0))])
            let expected = [1]
            try Tracker.bootstrap(tracker)

            tracker.track(Searched(query: ""))
            tracker.track(Scrolled())
            tracker.track(Tapped(number: 1))
            await sut.flush()
            let actualHeld = consent.heldRecordCount
            consent.grant(.analytics)
            await sut.finish()
            tracker.track(Tapped(number: 2))

            var actual: [Int] = []
            for await record in sut.records {
                actual.append((record.event as? Tapped)?.number ?? -1)
            }
            var rejections = sut.rejectionReports.makeAsyncIterator()
            var samplingDrops = sut.samplingDropReports.makeAsyncIterator()
            guard actual == expected,
                actualHeld == 1,
                sut.store != nil,
                await rejections.next() != nil,
                await samplingDrops.next() != nil
            else { exit(EXIT_FAILURE) }
        }
    }

    @Test("An explicit Tracker.noOp, and a preview's never-set view tracker, drop every event though a tracker is bootstrapped")
    func noOpAndPreviewDrop() async {
        await #expect(processExitsWith: .success) {
            let preview = Tracker.viewDefault(environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"])
            let tracker = Tracker()
            let expected: [Int] = []
            try Tracker.bootstrap(tracker)

            Tracker.noOp.track(Tapped(number: 1))
            preview.track(Tapped(number: 2))
            withTracker(preview) {
                Tracker.current.track(Tapped(number: 3))
            }
            await tracker.finish()

            var actual: [Int] = []
            for await record in tracker.records {
                actual.append((record.event as? Tapped)?.number ?? -1)
            }
            guard actual == expected, preview.isNoOp else { exit(EXIT_FAILURE) }
        }
    }

    @Test("A never-set view tracker bootstrapped as the process's default drops what it tracks rather than look itself up for ever")
    func bootstrappedViewDefault() async {
        await #expect(processExitsWith: .success) {
            let sut = Tracker.viewDefault(environment: [:])
            try Tracker.bootstrap(sut)

            sut.track(Tapped(number: 1))
            Tracker.current.track(Tapped(number: 2))
            await sut.flush()
            await sut.finish()

            var actual = 0
            for await _ in sut.records {
                actual += 1
            }
            guard actual == 0 else { exit(EXIT_FAILURE) }
        }
    }
}
