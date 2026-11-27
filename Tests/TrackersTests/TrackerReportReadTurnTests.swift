// Which reader reaches the stream first decides which path a read takes, so these tests run their
// tasks on the main serial executor (swift-concurrency-extras), which runs every job in the order
// it was enqueued: a second reader that sends its gate and then reads is waiting for its turn
// before the test resumes. It changes a global hook, so the suite runs its tests one at a time, apart from the
// other SerializedSuites.
import Afluent
import ConcurrencyExtras
import Events
import Foundation
import Testing
import Trackers

extension SerializedSuites {
    @MainActor
    @Suite("Tracker and Consent reports: one reader at a time", .serialized, .timeLimit(.minutes(1)))
    struct TrackerReportReadTurnTests {
        struct Searched: Event {
            var query: String
            var count: Int

            func constraintViolation() -> ConstraintViolation? {
                if query.isEmpty { return ConstraintViolation(property: "query", keyword: .minLength(1)) }
                if count > 10 { return ConstraintViolation(property: "count", keyword: .maximum(10)) }
                return nil
            }
        }

        struct Filtered: Event {
            var term: String

            func constraintViolation() -> ConstraintViolation? {
                term.isEmpty ? ConstraintViolation(property: "term", keyword: .minLength(1)) : nil
            }
        }

        struct Scrolled: Event {}

        struct Swiped: Event {}

        struct Pinched: Event {}

        struct Viewed: Event {}

        struct AdClicked: Event {
            static let consentCategory = ConsentCategory.advertising
        }

        struct Personalized: Event {
            static let consentCategory = ConsentCategory.personalization
        }

        @Test("A second reader of rejectionReports that starts while the first waits ends once the first's iteration ends and the tracker finishes; the first gets every rejection, in order")
        func rejectionReportsSecondReader() async throws {
            try await withMainSerialExecutor {
                let sut = Tracker()
                let reports = sut.rejectionReports
                let firstHoldsTurn = SingleValueSubject<Void>()
                let secondAboutToRead = SingleValueSubject<Void>()
                let expectedFirst = ["Searched.query", "Searched.count", "Filtered.term"]
                let expectedSecond: [String] = []
                let first = Task {
                    var rejected: [String] = []
                    for await report in reports {
                        rejected.append("\(report.eventName).\(report.violation.property)")
                        if rejected.count == 1 { try? firstHoldsTurn.send() }
                    }
                    return rejected
                }
                sut.track(Searched(query: "", count: 1))
                try await firstHoldsTurn.execute()
                let second = Task {
                    var rejected: [String] = []
                    try? secondAboutToRead.send()
                    for await report in reports {
                        rejected.append("\(report.eventName).\(report.violation.property)")
                    }
                    return rejected
                }
                try await secondAboutToRead.execute()

                sut.track(Searched(query: "shoes", count: 11))
                sut.track(Filtered(term: ""))
                await sut.finish()
                let actualFirst = await first.value
                let actualSecond = await second.value

                #expect(actualFirst == expectedFirst)
                #expect(actualSecond == expectedSecond)
            }
        }

        @Test("A second reader of samplingDropReports that starts while the first waits ends once the first's iteration ends and the tracker finishes; the first gets every drop, in order")
        func samplingDropReportsSecondReader() async throws {
            try await withMainSerialExecutor {
                let sut = Tracker(samplers: [
                    .events(of: Scrolled.self, rate: try SampleRate(0)),
                    .events(of: Swiped.self, rate: try SampleRate(0)),
                    .events(of: Pinched.self, rate: try SampleRate(0)),
                ], samplingSeed: 1)
                let reports = sut.samplingDropReports
                let firstHoldsTurn = SingleValueSubject<Void>()
                let secondAboutToRead = SingleValueSubject<Void>()
                let expectedFirst = ["Scrolled", "Swiped", "Pinched"]
                let expectedSecond: [String] = []
                let first = Task {
                    var dropped: [String] = []
                    for await report in reports {
                        dropped.append(report.eventName)
                        if dropped.count == 1 { try? firstHoldsTurn.send() }
                    }
                    return dropped
                }
                sut.track(Scrolled())
                try await firstHoldsTurn.execute()
                let second = Task {
                    var dropped: [String] = []
                    try? secondAboutToRead.send()
                    for await report in reports {
                        dropped.append(report.eventName)
                    }
                    return dropped
                }
                try await secondAboutToRead.execute()

                sut.track(Swiped())
                sut.track(Pinched())
                await sut.finish()
                let actualFirst = await first.value
                let actualSecond = await second.value

                #expect(actualFirst == expectedFirst)
                #expect(actualSecond == expectedSecond)
            }
        }

        @Test("A second reader of a consent's dropReports that starts while the first waits ends once the first's iteration ends and the consent is gone; the first gets every drop, in order")
        func consentDropReportsSecondReader() async throws {
            try await withMainSerialExecutor {
                let time = Date(timeIntervalSince1970: 5)
                var consent: Consent? = Consent()
                var sut: Tracker? = consent.map { consent in Tracker(consent: consent, now: { time }) }
                let reports = try #require(consent?.dropReports)
                let firstHoldsTurn = SingleValueSubject<Void>()
                let secondAboutToRead = SingleValueSubject<Void>()
                let expectedFirst: [ConsentDropReport] = [
                    .denied(category: .analytics, recordCount: 1, timestamps: time ... time),
                    .denied(category: .advertising, recordCount: 1, timestamps: time ... time),
                    .finishedUndecided(recordCount: 1, timestamps: time ... time),
                ]
                let expectedSecond: [ConsentDropReport] = []
                let first = Task {
                    var dropped: [ConsentDropReport] = []
                    for await report in reports {
                        dropped.append(report)
                        if dropped.count == 1 { try? firstHoldsTurn.send() }
                    }
                    return dropped
                }
                sut?.track(Viewed())
                consent?.deny(.analytics)
                try await firstHoldsTurn.execute()
                let second = Task {
                    var dropped: [ConsentDropReport] = []
                    try? secondAboutToRead.send()
                    for await report in reports {
                        dropped.append(report)
                    }
                    return dropped
                }
                try await secondAboutToRead.execute()

                sut?.track(AdClicked())
                consent?.deny(.advertising)
                sut?.track(Personalized())
                await sut?.finish()
                sut = nil
                consent = nil
                let actualFirst = await first.value
                let actualSecond = await second.value

                #expect(actualFirst == expectedFirst)
                #expect(actualSecond == expectedSecond)
            }
        }
    }
}
