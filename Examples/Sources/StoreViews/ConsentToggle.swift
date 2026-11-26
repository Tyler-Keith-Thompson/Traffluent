#if canImport(SwiftUI)
    import Events
    import StoreAnalytics
    import SwiftUI

    /// A switch that grants or denies one purpose.
    ///
    /// `Consent` isn't observable, so the switch keeps its own state, read from the preferences
    /// as it appears, and grants or denies as it is flipped.
    struct ConsentToggle: View {
        let category: ConsentCategory
        let preferences: ConsentPreferences
        @State private var isGranted = false

        var body: some View {
            Toggle(isOn: $isGranted) {
                VStack(alignment: .leading) {
                    Text(category.title)
                    Text(category.explanation).font(.caption)
                }
            }
            .onAppear {
                isGranted = preferences.status(of: category) == .granted
            }
            .onChange(of: isGranted) { _, isGranted in
                guard isGranted != (preferences.status(of: category) == .granted) else { return }
                if isGranted {
                    preferences.grant(category)
                } else {
                    preferences.deny(category)
                }
            }
        }
    }
#endif
