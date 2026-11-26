// `import Traffluent` alone gives `@Event` and `@Constrained`. This file imports no other module of
// the library, so it compiles only while the umbrella re-exports EventMacros.

import Testing
import Traffluent

@Suite("The umbrella import", .timeLimit(.minutes(1)))
struct UmbrellaImportTests {
    @Event(name: "coupon_applied")
    struct CouponApplied {
        @Constrained(.minLength(1))
        var code: String
    }

    @Test("A file that imports only Traffluent declares an @Event type and tracks it")
    func eventMacroThroughTheUmbrella() async throws {
        let destination = InMemoryDestination()
        let sut = Tracker()
        let delivery = sut.records.batch().deliver(to: destination)
        let expectedName = "coupon_applied"
        let expectedCodes = ["SPRING"]

        sut.track(CouponApplied(code: "SPRING"))
        await sut.finish()
        try await delivery.execute()

        let actual = destination.events(of: CouponApplied.self).map(\.code)
        #expect(CouponApplied.name == expectedName)
        #expect(actual == expectedCodes)
    }

    @Test("A file that imports only Traffluent gets @Constrained, whose broken constraint the tracker rejects")
    func constrainedThroughTheUmbrella() async {
        let sut = Tracker()
        let expectedRejectionCount = 1

        sut.track(CouponApplied(code: ""))
        await sut.finish()

        var actual = 0
        for await _ in sut.rejectionReports {
            actual += 1
        }
        #expect(actual == expectedRejectionCount)
    }
}
