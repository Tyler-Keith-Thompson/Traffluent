import Foundation
import StoreEvents
import StoreModel
import Testing
import Trackers
import TrackerTesting

@Suite("Cart", .timeLimit(.minutes(1)))
struct CartTests {
    @Test("Adding a product tracks ProductAddedToCart with its identifier and the quantity")
    func add() async throws {
        let tote = Product(id: "canvas-tote", name: "Canvas Tote", priceInCents: 2_400)
        var sut = Cart()
        let expected = [ProductAddedToCart(productID: "canvas-tote", quantity: 2)]

        let tracked = try await withRecordingTracker { tracker in
            try sut.add(tote, quantity: 2, trackingWith: tracker)
        }

        let actual = tracked.events(of: ProductAddedToCart.self)
        #expect(actual == expected)
        #expect(sut.itemCount == 2)
    }

    @Test("Adding a product the cart holds adds to its line, and tracks each addition")
    func addAgain() async throws {
        let mug = Product(id: "enamel-mug", name: "Enamel Mug", priceInCents: 1_800)
        var sut = Cart()
        let expectedLines = [Cart.Line(product: mug, quantity: 3)]
        let expectedEvents = [
            ProductAddedToCart(productID: "enamel-mug", quantity: 1),
            ProductAddedToCart(productID: "enamel-mug", quantity: 2),
        ]

        let tracked = try await withRecordingTracker { tracker in
            try sut.add(mug, trackingWith: tracker)
            try sut.add(mug, quantity: 2, trackingWith: tracker)
        }

        #expect(sut.lines == expectedLines)
        #expect(tracked.events(of: ProductAddedToCart.self) == expectedEvents)
    }

    @Test("A quantity outside 1 to 10 throws QuantityOutOfRange, leaves the cart unchanged and tracks nothing", arguments: [0, 11, Int.min, Int.max])
    func quantityOutOfRange(quantity: Int) async {
        let mug = Product(id: "enamel-mug", name: "Enamel Mug", priceInCents: 1_800)
        var sut = Cart()
        let expectedError: QuantityOutOfRange? = QuantityOutOfRange()
        let expectedNames: [String] = []

        let tracked = await withRecordingTracker { tracker -> QuantityOutOfRange? in
            do throws(QuantityOutOfRange) {
                try sut.add(mug, quantity: quantity, trackingWith: tracker)
                return nil
            } catch {
                return error
            }
        }

        #expect(tracked.value == expectedError)
        #expect(sut.isEmpty)
        #expect(tracked.names == expectedNames)
    }

    @Test("The quantities 1 and 10, the range's bounds, are added")
    func quantityBounds() async throws {
        let mug = Product(id: "enamel-mug", name: "Enamel Mug", priceInCents: 1_800)
        var sut = Cart()
        let expected = [
            ProductAddedToCart(productID: "enamel-mug", quantity: 1),
            ProductAddedToCart(productID: "enamel-mug", quantity: 10),
        ]

        let tracked = try await withRecordingTracker { tracker in
            try sut.add(mug, quantity: 1, trackingWith: tracker)
            try sut.add(mug, quantity: 10, trackingWith: tracker)
        }

        #expect(tracked.events(of: ProductAddedToCart.self) == expected)
        #expect(sut.itemCount == 11)
    }

    @Test("A total past Int.max stops at Int.max rather than trapping")
    func totalSaturates() async throws {
        let priceless = Product(id: "priceless", name: "Priceless", priceInCents: .max / 2)
        var sut = Cart()
        let expected = Int.max

        _ = try await withRecordingTracker { tracker in
            try sut.add(priceless, quantity: 3, trackingWith: tracker)
        }

        #expect(sut.totalInCents == expected)
    }

    @Test("Every product in the catalog has an identifier the event accepts")
    func catalogIdentifiers() async throws {
        var sut = Cart()
        let expected = Product.catalog.map(\.id)

        let tracked = try await withRecordingTracker { tracker in
            for product in Product.catalog {
                try sut.add(product, trackingWith: tracker)
            }
        }

        let actual = tracked.events(of: ProductAddedToCart.self).map(\.productID)
        #expect(actual == expected)
    }

    @Test("Removing a product removes its line and tracks nothing")
    func remove() async throws {
        let mug = Product(id: "enamel-mug", name: "Enamel Mug", priceInCents: 1_800)
        var sut = Cart()
        _ = try await withRecordingTracker { tracker in
            try sut.add(mug, trackingWith: tracker)
        }
        let expected: [String] = []

        let tracked = await withRecordingTracker {
            sut.remove(mug)
        }

        #expect(sut.isEmpty)
        #expect(tracked.names == expected)
    }

    @Test("Applying a promotion tracks PromotionTapped and takes its discount, rounded down to a cent, off the total")
    func applyPromotion() async throws {
        let notebook = Product(id: "field-notebook", name: "Field Notebook", priceInCents: 1_299)
        let promotion = Promotion(campaign: "spring-sale", title: "Spring sale", couponCode: "SPRING", percentOff: 10)
        var sut = Cart()
        let expectedEvents = [PromotionTapped(campaign: "spring-sale")]
        // 10% of 1,299 cents is 129.9, rounded down to 129.
        let expectedTotal = 1_170

        let tracked = try await withRecordingTracker { tracker in
            try sut.add(notebook, trackingWith: tracker)
            sut.apply(promotion, trackingWith: tracker)
        }

        #expect(tracked.events(of: PromotionTapped.self) == expectedEvents)
        #expect(sut.totalInCents == expectedTotal)
    }

    @Test("An empty cart costs nothing and holds no items")
    func empty() {
        let sut = Cart()

        #expect(sut.isEmpty)
        #expect(sut.itemCount == 0)
        #expect(sut.totalInCents == 0)
    }
}
