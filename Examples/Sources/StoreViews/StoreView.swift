// SwiftUI is on Apple platforms alone; on Linux this module builds empty, so the package still
// does.
#if canImport(SwiftUI)
    import StoreAnalytics
    import StoreModel
    public import SwiftUI
    import SwiftUITracking

    /// The store app's window: the shop, the cart and the account, each a tab, and the consent
    /// prompt until the shopper has decided.
    ///
    /// Every view below reads the tracker from the environment, which the app sets around this
    /// one with `tracker(_:)`. Each tab's screen is placed with `trackScreen(_:)`, which tracks
    /// `ScreenViewed` as it appears and stamps the events tracked inside it with its name.
    public struct StoreView: View {
        private let preferences: ConsentPreferences
        @State private var cart = Cart()
        @State private var account: Account?
        @State private var asksForConsent: Bool

        /// The window, asking for consent first when `preferences` are undecided about any
        /// category.
        ///
        /// - Parameter preferences: The shopper's consent, restored from their saved decisions.
        public init(preferences: ConsentPreferences) {
            self.preferences = preferences
            _asksForConsent = State(initialValue: !preferences.isComplete)
        }

        public var body: some View {
            TabView {
                Tab("Shop", systemImage: "bag") {
                    NavigationStack {
                        CatalogView(cart: $cart).trackScreen("Catalog")
                    }
                }
                Tab("Cart", systemImage: "cart") {
                    NavigationStack {
                        CartView(cart: $cart).trackScreen("Cart")
                    }
                }
                Tab("Account", systemImage: "person") {
                    NavigationStack {
                        AccountView(account: $account, preferences: preferences).trackScreen("Account")
                    }
                }
            }
            .sheet(isPresented: $asksForConsent) {
                ConsentPrompt(preferences: preferences).trackScreen("Consent")
            }
        }
    }
#endif
