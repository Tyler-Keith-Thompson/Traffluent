// The checkout's automatic tracking, in the iOS simulator's test host (tools/test_host), which gives
// windows a scene: `just example-ios-test`. SwiftPM builds none of it; Package.swift has no target
// for this directory.
//
// Each test awaits its tracker's records in order rather than sleeping: the scene's discovery
// tracks a screen after a turn of the main run loop, which awaiting gives it.
#if canImport(UIKit) && !os(watchOS)
    import AutomaticControlTracking
    import AutomaticScreenTracking
    import Events
    import Observation
    import StoreEvents
    import StoreModel
    @testable import StoreViews
    import SwiftUI
    import SwiftUITracking
    import Testing
    import Trackers
    import UIKit

    @MainActor
    @Suite("The checkout's automatic tracking", .serialized, .timeLimit(.minutes(1)))
    struct CheckoutTrackingTests {
        /// What the cart screen below shows: its cart, and whether checkout is pushed.
        @Observable
        final class Checkout {
            var cart = Cart()
            var checksOut = false
            var ordersPlaced = 0
        }

        /// The cart tab as `StoreView` and `CartView` place it: a navigation stack whose root
        /// is tracked as "Cart" and pushes the checkout.
        struct CartTab: View {
            @Bindable var checkout: Checkout
            let tracker: Tracker

            var body: some View {
                NavigationStack {
                    Text("Cart")
                        .navigationDestination(isPresented: $checkout.checksOut) {
                            CheckoutDestination(cart: $checkout.cart) { checkout.ordersPlaced += 1 }
                        }
                        .trackScreen("Cart")
                }
                .trackWindowSceneAutomatically(tracker)
                .tracker(tracker)
            }
        }

        @Test("Pushing the checkout tracks ScreenViewed Checkout, whose record's screen is Checkout, not Cart")
        func checkoutScreenViewed() async throws {
            let tracker = Tracker()
            var records = tracker.records.makeAsyncIterator()
            let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let window = UIWindow(windowScene: scene)
            let checkout = Checkout()
            window.rootViewController = UIHostingController(rootView: CartTab(checkout: checkout, tracker: tracker))
            window.isHidden = false
            defer {
                scene.stopTrackingScreensAutomatically()
                scene.stopTrackingControlsAutomatically()
                window.isHidden = true
            }
            let expectedCart = ScreenViewed(screen: "Cart")
            let expectedCheckout = ScreenViewed(screen: "Checkout")
            let expectedScreen: String? = "Checkout"

            let cart = try #require(await records.next())
            checkout.checksOut = true
            let actual = try #require(await records.next())

            #expect(cart.event as? ScreenViewed == expectedCart)
            #expect(actual.event as? ScreenViewed == expectedCheckout)
            #expect(actual.context[ScreenKey.self] == expectedScreen)
        }

        @Test("Placing the order from the checkout's button tracks OrderCompleted, whose record's screen is Checkout")
        func placeOrder() async throws {
            let tracker = Tracker()
            var records = tracker.records.makeAsyncIterator()
            let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let window = UIWindow(windowScene: scene)
            let checkout = Checkout()
            window.rootViewController = UIHostingController(rootView: CartTab(checkout: checkout, tracker: tracker))
            window.isHidden = false
            defer {
                scene.stopTrackingScreensAutomatically()
                scene.stopTrackingControlsAutomatically()
                window.isHidden = true
            }
            let expectedScreen: String? = "Checkout"
            let expectedOrders = 1

            _ = try #require(await records.next())
            checkout.checksOut = true
            _ = try #require(await records.next())
            let button = try #require(window.subview(identifiedAs: "place-order") as? UIButton)
            button.sendActions(for: .primaryActionTriggered)
            // Sending the action skips the touch that automatic control tracking tracks
            // ControlActivated from, so the order is the next record.
            let actual = try #require(await records.next())

            #expect(actual.event is OrderCompleted)
            #expect(actual.context[ScreenKey.self] == expectedScreen)
            #expect(checkout.ordersPlaced == expectedOrders)
        }
    }

    extension UIView {
        /// The first view in this one's hierarchy, itself included, whose accessibility
        /// identifier is `identifier`.
        fileprivate func subview(identifiedAs identifier: String) -> UIView? {
            if accessibilityIdentifier == identifier { return self }
            return subviews.lazy.compactMap { $0.subview(identifiedAs: identifier) }.first
        }
    }
#endif
