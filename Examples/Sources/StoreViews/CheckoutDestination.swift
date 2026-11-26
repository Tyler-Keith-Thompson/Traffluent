#if canImport(SwiftUI)
    import Events
    import StoreModel
    import SwiftUI
    import SwiftUITracking
    import Trackers

    /// The checkout: a UIKit screen where UIKit has window scenes, whose screen view and controls
    /// the scene tracks automatically, and a SwiftUI one elsewhere, which tracks the same events
    /// with modifiers.
    struct CheckoutDestination: View {
        @Binding var cart: Cart
        let orderPlaced: () -> Void

        var body: some View {
            #if canImport(UIKit) && !os(watchOS)
                CheckoutScreen(cart: $cart, orderPlaced: orderPlaced)
                    .navigationTitle("Checkout")
                    // The destination inherits the cart screen's tracker, and the controller's
                    // traits read it, so its events would say "Cart". A tracker enriched with
                    // the checkout's name says "Checkout", as the SwiftUI checkout does, and adds
                    // no screen marker, so the scene still tracks the controller's screen view.
                    .transformEnvironment(\.tracker) { tracker in
                        tracker = tracker.enriched(by: Enricher { $0[ScreenKey.self] = "Checkout" })
                    }
            #else
                CheckoutView(cart: $cart, orderPlaced: orderPlaced).trackScreen("Checkout")
            #endif
        }
    }
#endif
