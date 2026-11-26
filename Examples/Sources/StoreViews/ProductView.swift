#if canImport(SwiftUI)
    import StoreModel
    import SwiftUI
    import SwiftUITracking
    import Trackers

    /// One product: its price, and a quantity of 1 to 10 to add to the cart.
    struct ProductView: View {
        let product: Product
        @Binding var cart: Cart
        @State private var quantity = 1
        @Environment(\.tracker) private var tracker

        var body: some View {
            Form {
                LabeledContent(product.name) {
                    PriceText(cents: product.priceInCents)
                }
                Stepper("Quantity: \(quantity)", value: $quantity, in: Cart.quantities)
                Button("Add to Cart") {
                    // The stepper keeps the quantity in the cart's range, so the cart never
                    // refuses it.
                    try? cart.add(product, quantity: quantity, trackingWith: tracker)
                }
            }
            .navigationTitle(product.name)
        }
    }
#endif
