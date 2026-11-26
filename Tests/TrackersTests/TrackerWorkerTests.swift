// The worker's work blocks a thread here on purpose (a store's append and an enricher are
// synchronous).
import Dispatch
import Destinations
import Events
import Persistence
import Synchronization
import Testing
import Trackers

extension SerializedSuites {
    @Suite("Tracker: the worker", .timeLimit(.minutes(1)))
    struct TrackerWorkerTests {
        struct Viewed: Event {
            var number: Int
        }

        struct AdClicked: Event {
            static let consentCategory = ConsentCategory.advertising
            var number: Int
        }

        /// An event whose number must be at least 2, whose check waits at `gate` first.
        struct Checked: Event {
            var number: Int
            let gate: Gate

            func constraintViolation() -> ConstraintViolation? {
                gate.wait()
                return number >= 2 ? nil : ConstraintViolation(property: "number", keyword: .minimum(2))
            }
        }

        /// A gate the worker waits at until the test opens it, and stays open from then on.
        final class Gate: Sendable {
            private let opened = Mutex(false)
            private let semaphore = DispatchSemaphore(value: 0)
            let entered: AsyncStream<Void>
            private let entering: AsyncStream<Void>.Continuation

            init() {
                (entered, entering) = AsyncStream.makeStream(of: Void.self)
            }

            /// Announces the wait on ``entered``, then blocks until ``open()``.
            func wait() {
                entering.yield()
                guard !opened.withLock({ $0 }) else { return }
                semaphore.wait()
                // Passed on, so a later wait finds the gate open too.
                semaphore.signal()
            }

            func open() {
                opened.withLock { $0 = true }
                semaphore.signal()
            }
        }

        /// A store whose every append waits at `gate` before keeping nothing.
        final class BlockingStore: RecordStore {
            let gate = Gate()
            let appended = Mutex(0)

            func append(_ record: EventRecord) -> EventRecord {
                gate.wait()
                appended.withLock { $0 += 1 }
                return record
            }

            func takeRecoveredRecords() -> [EventRecord] {
                []
            }

            func synchronize() {}
        }

        @Test("track returns while the store's write is blocked: the worker writes, not the caller")
        func trackDoesNotWaitForStore() async throws {
            let store = BlockingStore()
            let sut = Tracker(store: store)
            let recorder = InMemoryDestination()
            let expected = [1, 2]
            var entered = store.gate.entered.makeAsyncIterator()
            sut.track(Viewed(number: 1))
            _ = await entered.next()

            sut.track(Viewed(number: 2))
            let actualAppended = store.appended.withLock { $0 }
            store.gate.open()
            await sut.finish()
            try await sut.records.batch(strategy: .count(10)).deliver(to: recorder).execute()

            #expect(actualAppended == 0)
            #expect(recorder.numbers == expected)
            #expect(store.appended.withLock { $0 } == 2)
        }

        @Test("track returns while an enricher is blocked: the worker enriches, not the caller")
        func trackDoesNotWaitForEnricher() async throws {
            let gate = Gate()
            let sut = Tracker(enrichers: [Enricher { _ in gate.wait() }])
            let recorder = InMemoryDestination()
            let expected = [1, 2]
            var entered = gate.entered.makeAsyncIterator()
            sut.track(Viewed(number: 1))
            _ = await entered.next()

            sut.track(Viewed(number: 2))
            gate.open()
            await sut.finish()
            try await sut.records.batch(strategy: .count(10)).deliver(to: recorder).execute()

            #expect(recorder.numbers == expected)
        }

        @Test("grant returns while the worker is blocked, records the decision at once, and the released record still comes before one tracked after")
        func grantDoesNotWaitForWorker() async throws {
            let gate = Gate()
            let consent = Consent()
            let sut = Tracker(consent: consent, enrichers: [Enricher { _ in gate.wait() }])
            let recorder = InMemoryDestination()
            let expected = [1, 2]
            var entered = gate.entered.makeAsyncIterator()
            sut.track(Viewed(number: 1))
            _ = await entered.next()

            consent.grant(.analytics)
            let actualStatus = consent.status(of: .analytics)
            sut.track(Viewed(number: 2))
            gate.open()
            await sut.finish()
            try await sut.records.batch(strategy: .count(10)).deliver(to: recorder).execute()

            #expect(actualStatus == .granted)
            #expect(recorder.numbers == expected)
        }

        @Test("Tracks and decisions are handled in the order they were made, whatever the worker was doing meanwhile")
        func orderAcrossDecisions() async throws {
            let gate = Gate()
            let consent = Consent()
            let sut = Tracker(consent: consent, enrichers: [Enricher { _ in gate.wait() }])
            let recorder = InMemoryDestination()
            let expected = [1, 3, 2, 4, 6]
            var entered = gate.entered.makeAsyncIterator()
            sut.track(Viewed(number: 1))
            _ = await entered.next()

            sut.track(AdClicked(number: 2))
            consent.grant(.analytics)
            sut.track(Viewed(number: 3))
            consent.grant(.advertising)
            sut.track(AdClicked(number: 4))
            consent.deny(.analytics)
            sut.track(Viewed(number: 5))
            sut.track(AdClicked(number: 6))
            gate.open()
            await sut.finish()
            try await sut.records.batch(strategy: .count(10)).deliver(to: recorder).execute()

            #expect(recorder.numbers == expected)
        }

        @Test("track returns while an event's constraint check is blocked: the worker validates, not the caller")
        func trackDoesNotWaitForValidation() async throws {
            let gate = Gate()
            let sut = Tracker()
            let recorder = InMemoryDestination()
            let expected = [2]
            let expectedViolation = ConstraintViolation(property: "number", keyword: .minimum(2))
            var entered = gate.entered.makeAsyncIterator()
            sut.track(Checked(number: 1, gate: gate))
            _ = await entered.next()

            sut.track(Checked(number: 2, gate: gate))
            gate.open()
            await sut.finish()
            try await sut.records.batch(strategy: .count(10)).deliver(to: recorder).execute()

            #expect(recorder.records.compactMap { ($0.event as? Checked)?.number } == expected)
            var reports = sut.rejectionReports.makeAsyncIterator()
            #expect(await reports.next()?.violation == expectedViolation)
        }

        @Test("flush waits until every event tracked before it is written")
        func flushWaitsForWrites() async {
            let store = BlockingStore()
            let sut = Tracker(store: store)
            store.gate.open()
            sut.track(Viewed(number: 1))
            sut.track(Viewed(number: 2))

            await sut.flush()

            #expect(store.appended.withLock { $0 } == 2)
        }

        @Test("finish waits until every event tracked before it is written")
        func finishWaitsForWrites() async {
            let store = BlockingStore()
            let sut = Tracker(store: store)
            store.gate.open()
            sut.track(Viewed(number: 1))
            sut.track(Viewed(number: 2))

            await sut.finish()

            #expect(store.appended.withLock { $0 } == 2)
        }

        @Test("flush after finish returns once the worker is done")
        func flushAfterFinish() async {
            let sut = Tracker()
            await sut.finish()

            await sut.flush()
        }
    }

}

extension InMemoryDestination {
    /// The numbers of the events received, in the order received.
    fileprivate var numbers: [Int] {
        records.compactMap { record in
            switch record.event {
            case let event as SerializedSuites.TrackerWorkerTests.Viewed: event.number
            case let event as SerializedSuites.TrackerWorkerTests.AdClicked: event.number
            default: nil
            }
        }
    }
}
