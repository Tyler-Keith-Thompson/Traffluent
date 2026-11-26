#if canImport(SwiftUI)
    import StoreModel
    import SwiftUI
    import SwiftUITracking
    import Trackers

    /// The shop: the season's promotion, then every product, each opening its own screen.
    struct CatalogView: View {
        @Binding var cart: Cart
        @Environment(\.tracker) private var tracker

        var body: some View {
            List {
                Section {
                    Button(Promotion.springSale.title) {
                        cart.apply(.springSale, trackingWith: tracker)
                    }
                    .disabled(cart.promotion == .springSale)
                }
                Section("Products") {
                    ForEach(Product.catalog) { product in
                        NavigationLink(value: product) {
                            LabeledContent(product.name) {
                                PriceText(cents: product.priceInCents)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Shop")
            .navigationDestination(for: Product.self) { product in
                ProductView(product: product, cart: $cart).trackScreen("Product")
            }
        }
    }
#endif
