#if canImport(SwiftUI)
    import Events

    extension ConsentCategory {
        /// What the privacy screens call the purpose.
        var title: String {
            switch self {
            case .analytics: "Analytics"
            case .functional: "Account"
            case .advertising: "Marketing"
            default: name
            }
        }

        /// What the store collects for the purpose, as the privacy screens explain it.
        var explanation: String {
            switch self {
            case .analytics: "Which screens you visit and what you add to your cart, so we can improve the store."
            case .functional: "That you signed up, and for which plan."
            case .advertising: "Which promotions you tap, so we can measure our campaigns."
            default: name
            }
        }
    }
#endif
