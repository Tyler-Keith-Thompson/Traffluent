#if canImport(SwiftUI)
    import StoreAnalytics
    import SwiftUI

    /// The prompt the app shows until the shopper has decided about every purpose: allow them
    /// all, or decline them all.
    ///
    /// Until then the tracker holds each event in memory, delivering it once its purpose is
    /// granted and dropping it once it is denied.
    struct ConsentPrompt: View {
        let preferences: ConsentPreferences
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your Privacy")
                        .font(.title2)
                    ForEach(ConsentPreferences.categories, id: \.self) { category in
                        VStack(alignment: .leading) {
                            Text(category.title).font(.headline)
                            Text(category.explanation).font(.caption)
                        }
                    }
                    Button("Allow All") {
                        for category in ConsentPreferences.categories {
                            preferences.grant(category)
                        }
                        dismiss()
                    }
                    Button("Decline All") {
                        for category in ConsentPreferences.categories {
                            preferences.deny(category)
                        }
                        dismiss()
                    }
                    Text("You can change these choices in Account at any time.")
                        .font(.footnote)
                }
                .padding()
            }
            .interactiveDismissDisabled()
        }
    }
#endif
