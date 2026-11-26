// The tests run on the Mac; elsewhere this target builds empty, without ViewInspector.
#if os(macOS)
    import AppKit
    import AutomaticControlTracking
    import Events
    import Foundation
    import StoreAnalytics
    import StoreEvents
    import StoreModel
    @testable import StoreViews
    import SwiftUI
    import SwiftUITracking
    import Testing
    import Trackers
    import TrackerTesting
    import ViewInspector

    @MainActor
    @Suite("Store views", .serialized, .timeLimit(.minutes(1)))
    struct StoreViewsTests {
        @Test("Tapping Add to Cart tracks ProductAddedToCart through the environment's tracker, bound around the cart's change, with the chosen quantity")
        func addToCart() async throws {
            let tote = Product(id: "canvas-tote", name: "Canvas Tote", priceInCents: 2_400)
            let expected = [ProductAddedToCart(productID: "canvas-tote", quantity: 1)]

            let tracked = try await withRecordingTracker { tracker in
                let sut = ProductView(product: tote, cart: .constant(Cart())).tracker(tracker)
                try sut.inspect().find(button: "Add to Cart").tap()
            }

            #expect(tracked.events(of: ProductAddedToCart.self) == expected)
        }

        @Test("Add to Cart on the product screen tracks ProductAddedToCart with the screen's name, which the environment's tracker carries")
        func addToCartScreen() async throws {
            let tote = Product(id: "canvas-tote", name: "Canvas Tote", priceInCents: 2_400)
            let expected: [String?] = ["Product"]

            let tracked = try await withRecordingTracker { tracker in
                let sut = ProductView(product: tote, cart: .constant(Cart())).trackScreen("Product").tracker(tracker)
                try sut.inspect().find(button: "Add to Cart").tap()
            }

            let actual = tracked.records.filter { $0.event is ProductAddedToCart }.map { $0.context[ScreenKey.self] }
            #expect(actual == expected)
        }

        @Test("Tapping the promotion's banner tracks PromotionTapped")
        func promotion() async throws {
            let expected = [PromotionTapped(campaign: "spring-sale")]

            let tracked = try await withRecordingTracker { tracker in
                let sut = CatalogView(cart: .constant(Cart())).tracker(tracker)
                try sut.inspect().find(button: Promotion.springSale.title).tap()
            }

            #expect(tracked.events(of: PromotionTapped.self) == expected)
        }

        @Test("Placing the order on the SwiftUI checkout tracks OrderCompleted, then says the order was placed")
        func placeOrder() async throws {
            let tote = Product(id: "canvas-tote", name: "Canvas Tote", priceInCents: 2_400)
            var cart = Cart()
            _ = try await withRecordingTracker {
                try cart.add(tote)
            }
            var orderPlaced = false
            let expectedItems = [["canvas-tote"]]

            let tracked = try await withRecordingTracker { tracker in
                let sut = CheckoutView(cart: .constant(cart)) { orderPlaced = true }.tracker(tracker)
                try sut.inspect().find(button: "Place Order").tap()
            }

            #expect(tracked.events(of: OrderCompleted.self).map(\.items) == expectedItems)
            #expect(orderPlaced)
        }

        @Test("Allow All on the consent prompt grants every category the store asks about")
        func allowAll() throws {
            let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("StoreViewsTests-\(UUID().uuidString)/consent.json")
            defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
            let preferences = ConsentPreferences(file: file)
            let sut = ConsentPrompt(preferences: preferences)
            let expected: [ConsentStatus] = [.granted, .granted, .granted]

            try sut.inspect().find(button: "Allow All").tap()

            let actual = ConsentPreferences.categories.map { preferences.status(of: $0) }
            #expect(actual == expected)
        }

        @Test("Decline All on the consent prompt denies every category the store asks about")
        func declineAll() throws {
            let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("StoreViewsTests-\(UUID().uuidString)/consent.json")
            defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
            let preferences = ConsentPreferences(file: file)
            let sut = ConsentPrompt(preferences: preferences)
            let expected: [ConsentStatus] = [.denied, .denied, .denied]

            try sut.inspect().find(button: "Decline All").tap()

            let actual = ConsentPreferences.categories.map { preferences.status(of: $0) }
            #expect(actual == expected)
        }

        @Test("Placed as a screen in a window, the catalog tracks ScreenViewed as it appears")
        func catalogScreen() async throws {
            let expected = [ScreenViewed(screen: "Catalog")]

            let tracked = await withRecordingTracker { tracker in
                _ = NSApplication.shared
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                defer { window.close() }
                let root = NavigationStack { CatalogView(cart: .constant(Cart())).trackScreen("Catalog") }
                let host = NSHostingView(rootView: root.frame(width: 300, height: 400).tracker(tracker))
                window.contentView = host
                window.orderFrontRegardless()
                host.layoutSubtreeIfNeeded()
            }

            #expect(tracked.events(of: ScreenViewed.self) == expected)
        }
    }
#endif
