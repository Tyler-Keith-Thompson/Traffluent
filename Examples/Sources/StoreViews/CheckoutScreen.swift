#if canImport(UIKit) && !os(watchOS)
    import StoreModel
    import SwiftUI

    /// ``CheckoutViewController`` in a SwiftUI navigation stack, placing the order in the cart
    /// it is given.
    struct CheckoutScreen: UIViewControllerRepresentable {
        @Binding var cart: Cart
        let orderPlaced: () -> Void

        func makeUIViewController(context: Context) -> CheckoutViewController {
            CheckoutViewController(totalInCents: cart.totalInCents) { [cart = $cart, orderPlaced] expressShipping, tracker in
                _ = cart.wrappedValue.placeOrder(expressShipping: expressShipping, trackingWith: tracker)
                orderPlaced()
            }
        }

        func updateUIViewController(_ controller: CheckoutViewController, context: Context) {}
    }
#endif
