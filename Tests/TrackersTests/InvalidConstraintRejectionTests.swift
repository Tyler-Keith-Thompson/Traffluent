import Destinations
import Events
import Foundation
import Testing
import Trackers

// @Event diagnoses every literal it can read that would make a constraint throw, so the expansion's
// fallback can't be reached from a declaration that compiles without warnings. This event checks
// its count as the expansion does, with a bound known only at run time, which can.
@Suite("Tracker: constraints that can't be built", .timeLimit(.minutes(1)))
struct InvalidConstraintRejectionTests {
    /// An event whose count is bounded by `limit`, which a `Double` can't hold exactly.
    struct Counted: Event, Equatable {
        static let limit = Int64(9_007_199_254_740_993)
        var count: Int64

        func constraintViolation() -> ConstraintViolation? {
            do throws(InvalidConstraint) {
                let constraint: Constraint<Int64> = try .maximum(Self.limit)
                if !constraint.isSatisfied(by: count) {
                    return ConstraintViolation(property: "count", keyword: constraint.keyword)
                }
            } catch {
                return ConstraintViolation(property: "count", invalidConstraint: ".maximum(Self.limit)", error: error)
            }
            return nil
        }
    }

    @Test("An event whose constraint throws as it is built is rejected, reaching no destination, and reported as that constraint's error, not as a value breaking a keyword")
    func rejectedAndReported() async throws {
        let sut = Tracker(now: { Date(timeIntervalSince1970: 3) })
        let recorder = InMemoryDestination()
        let expected = RejectionReport(
            eventName: "Counted",
            violation: ConstraintViolation(property: "count", invalidConstraint: ".maximum(Self.limit)", error: .inexactBound),
            recordCount: 1,
            timestamps: Date(timeIntervalSince1970: 3) ... Date(timeIntervalSince1970: 3)
        )
        let expectedDescription = #"Counted: "count"'s .maximum(Self.limit) can't be built (inexactBound) (1 rejected)"#

        sut.track(Counted(count: 1))
        await sut.finish()
        try await sut.records.batch(strategy: .count(10)).deliver(to: recorder).execute()

        var reports = sut.rejectionReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(recorder.events(of: Counted.self).isEmpty)
        #expect(actual == expected)
        #expect(actual?.description == expectedDescription)
    }
}
