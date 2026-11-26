#if canImport(SwiftUI)
    import SwiftUI

    /// A price in cents, shown in US dollars.
    struct PriceText: View {
        let cents: Int

        var body: some View {
            Text(Double(cents) / 100, format: .currency(code: "USD"))
        }
    }
#endif
