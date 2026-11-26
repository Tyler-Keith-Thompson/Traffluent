import Foundation
import StoreEvents
import StoreModel
import Testing
import Trackers
import TrackerTesting

@Suite("Checkout", .timeLimit(.minutes(1)))
struct CheckoutTests {
    @Test("Starting the checkout tracks CheckoutStarted with the item count and the promotion's coupon")
    func startCheckout() async throws {
        let tote = Product(id: "canvas-tote", name: "Canvas Tote", priceInCents: 2_400)
        let promotion = Promotion(campaign: "spring-sale", title: "Spring sale", couponCode: "SPRING", percentOff: 10)
        var sut = Cart()
        _ = try await withRecordingTracker { tracker in
            try sut.add(tote, quantity: 3, trackingWith: tracker)
            sut.apply(promotion, trackingWith: tracker)
        }
        let expected = [CheckoutStarted(cartSize: 3, coupon: "SPRING")]

        let tracked = await withRecordingTracker { tracker in
            sut.startCheckout(trackingWith: tracker)
        }

        #expect(tracked.events(of: CheckoutStarted.self) == expected)
    }

    @Test("Starting the checkout without a promotion tracks no coupon")
    func startCheckoutWithoutCoupon() async {
        let sut = Cart()
        let expected = [CheckoutStarted(cartSize: 0, coupon: nil)]

        let tracked = await withRecordingTracker { tracker in
            sut.startCheckout(trackingWith: tracker)
        }

        #expect(tracked.events(of: CheckoutStarted.self) == expected)
    }

    @Test("Placing an order tracks OrderCompleted with its lines' products and its total in dollars, and empties the cart")
    func placeOrder() async throws {
        let tote = Product(id: "canvas-tote", name: "Canvas Tote", priceInCents: 2_400)
        let mug = Product(id: "enamel-mug", name: "Enamel Mug", priceInCents: 1_850)
        let id = try #require(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        let placedAt = Date(timeIntervalSince1970: 1_764_000_000)
        var sut = Cart()
        _ = try await withRecordingTracker { tracker in
            try sut.add(tote, quantity: 2, trackingWith: tracker)
            try sut.add(mug, trackingWith: tracker)
        }
        let expectedEvents = [
            OrderCompleted(orderID: id, total: 66.5, itemCount: 3, items: ["canvas-tote", "enamel-mug"], completedAt: placedAt, express: true)
        ]
        let expectedOrder = Order(
            id: id,
            lines: [Cart.Line(product: tote, quantity: 2), Cart.Line(product: mug, quantity: 1)],
            totalInCents: 6_650,
            expressShipping: true,
            placedAt: placedAt
        )

        let tracked = await withRecordingTracker { tracker in
            sut.placeOrder(expressShipping: true, id: id, at: placedAt, trackingWith: tracker)
        }

        #expect(tracked.events(of: OrderCompleted.self) == expectedEvents)
        #expect(tracked.value == expectedOrder)
        #expect(sut.isEmpty)
    }
}
