#if canImport(SwiftUI)
    import AutomaticControlTracking
    import StoreModel
    import SwiftUI
    import SwiftUITracking
    import Trackers

    /// The checkout in SwiftUI, for the Mac and the watch: the total, express shipping, and the
    /// button that places the order.
    ///
    /// SwiftUI's controls are never tracked automatically, so its two controls track the
    /// `ControlActivated` events the UIKit checkout's controls do, under the same names, with
    /// `trackChange(of:_:)` and `trackOnTap(_:)`.
    struct CheckoutView: View {
        @Binding var cart: Cart
        let orderPlaced: () -> Void
        @State private var expressShipping = false
        @Environment(\.tracker) private var tracker

        var body: some View {
            Form {
                LabeledContent("Total") {
                    PriceText(cents: cart.totalInCents)
                }
                Toggle("Express Shipping", isOn: $expressShipping)
                    .trackChange(of: expressShipping) { _ in
                        ControlActivated(control: "express-shipping", kind: "Toggle")
                    }
                Button("Place Order") {
                    _ = cart.placeOrder(expressShipping: expressShipping, trackingWith: tracker)
                    orderPlaced()
                }
                .trackOnTap(ControlActivated(control: "place-order", kind: "Button"))
            }
            .navigationTitle("Checkout")
        }
    }
#endif
