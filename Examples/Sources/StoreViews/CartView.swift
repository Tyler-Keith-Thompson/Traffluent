#if canImport(SwiftUI)
    import StoreModel
    import SwiftUI
    import SwiftUITracking
    import Trackers

    /// The cart: its lines and total, and the way to the checkout.
    struct CartView: View {
        @Binding var cart: Cart
        @State private var checksOut = false
        @State private var confirmsOrder = false
        @Environment(\.tracker) private var tracker

        var body: some View {
            List {
                if cart.isEmpty {
                    Text("Your cart is empty.")
                }
                ForEach(cart.lines, id: \.product) { line in
                    LabeledContent(line.product.name, value: "× \(line.quantity)")
                }
                .onDelete { offsets in
                    for product in offsets.map({ cart.lines[$0].product }) {
                        cart.remove(product)
                    }
                }
                if !cart.isEmpty {
                    LabeledContent("Total") {
                        PriceText(cents: cart.totalInCents)
                    }
                    Button("Check Out") {
                        cart.startCheckout(trackingWith: tracker)
                        checksOut = true
                    }
                }
            }
            .navigationTitle("Cart")
            .navigationDestination(isPresented: $checksOut) {
                CheckoutDestination(cart: $cart) {
                    checksOut = false
                    confirmsOrder = true
                }
            }
            .alert("Thanks for your order", isPresented: $confirmsOrder) {
                Button("OK") {}
            }
        }
    }
#endif
