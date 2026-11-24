// The examples of the "Defining Events" article
// (Sources/Traffluent/Traffluent.docc/DefiningEvents.md), verbatim, so the article cannot drift from
// the code.

import EventMacros
import Testing
import Traffluent

@Suite("Defining events examples", .timeLimit(.minutes(1)))
struct DefiningEventsExamplesTests {
    @Event(name: "checkout_started", version: 2)
    struct CheckoutStarted {
        var cartSize: Int
        var coupon: String?
    }

    @Test("Deriving events with @Event")
    func derivingEvents() async throws {
        let tracker = Tracker()
        tracker.track(CheckoutStarted(cartSize: 3, coupon: nil))
        let properties = CheckoutStarted.schema.properties.map(\.name)  // ["cartSize", "coupon"]
        await tracker.finish()

        #expect(properties == ["cartSize", "coupon"])
        #expect(CheckoutStarted.name == "checkout_started")
        #expect(CheckoutStarted.schema.version == 2)
    }

    enum CouponCode: Refinement {
        static let constraints: [Constraint<String>] = [.pattern("^[A-Z0-9]{6}$", example: "SPRING")]
    }

    @Event(name: "search_performed")
    struct SearchPerformed {
        @Constrained(.minLength(1), .maxLength(200))
        var query: String
        @Constrained(.minimum(0))
        var resultCount: Int
        var coupon: Refined<String, CouponCode>?
    }

    @Test("Constraining properties")
    func constrainingProperties() async throws {
        let coupon = try? Refined<String, CouponCode>(checked: "spring")  // nil: UnsatisfiedConstraint.pattern
        let tracker = Tracker()
        tracker.track(SearchPerformed(query: "", resultCount: 3, coupon: Refined("SPRING")))
        await tracker.finish()
        for await report in tracker.rejectionReports {
            print(report)  // search_performed: "query" breaks minLength 1 (1 rejected)
        }

        #expect(coupon == nil)
        #expect(throws: UnsatisfiedConstraint.pattern) { try Refined<String, CouponCode>(checked: "spring") }
        var reports = tracker.rejectionReports.makeAsyncIterator()
        #expect(await reports.next() == nil)
    }

    @Test("Constraining properties: the report")
    func constrainingPropertiesReport() async {
        let tracker = Tracker()
        let expected = #"search_performed: "query" breaks minLength 1 (1 rejected)"#

        tracker.track(SearchPerformed(query: "", resultCount: 3, coupon: Refined("SPRING")))
        await tracker.finish()

        var reports = tracker.rejectionReports.makeAsyncIterator()
        #expect(await reports.next()?.description == expected)
    }
}
