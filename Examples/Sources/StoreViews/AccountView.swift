#if canImport(SwiftUI)
    import StoreAnalytics
    import StoreModel
    import SwiftUI
    import SwiftUITracking
    import Trackers

    /// The account: a sign-up form until the shopper has an account, then the privacy choices.
    struct AccountView: View {
        @Binding var account: Account?
        let preferences: ConsentPreferences
        @State private var email = ""
        @State private var plan = Account.Plan.basic
        @Environment(\.tracker) private var tracker

        var body: some View {
            Form {
                if let account {
                    Section("Signed Up") {
                        LabeledContent(account.email, value: account.plan.rawValue.capitalized)
                    }
                } else {
                    Section("Sign Up") {
                        TextField("Email", text: $email)
                        Picker("Plan", selection: $plan) {
                            ForEach(Account.Plan.allCases, id: \.self) { plan in
                                Text(plan.rawValue.capitalized)
                            }
                        }
                        Button("Sign Up") {
                            // Bound so the event carries this screen's name, which the app's
                            // bootstrapped tracker doesn't.
                            account = withTracker(tracker) { .signUp(email: email, plan: plan) }
                        }
                        .disabled(email.isEmpty)
                    }
                }
                Section("Privacy") {
                    ForEach(ConsentPreferences.categories, id: \.self) { category in
                        ConsentToggle(category: category, preferences: preferences)
                    }
                }
            }
            .navigationTitle("Account")
        }
    }
#endif
