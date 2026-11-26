// The good examples of the "Logging, Tracing, Metrics and Analytics" article
// (Sources/Traffluent/Traffluent.docc/WhatGoesWhere.md), verbatim, so they keep compiling.

import Testing
import Tracing
import Traffluent

@Suite("What goes where examples")
struct WhatGoesWhereExamplesTests {
    @Event
    struct CheckoutFailed {
        enum Reason: String {
            case paymentDeclined
            case outOfStock
            case networkUnavailable
        }
        @Constrained(.pattern("^(paymentDeclined|outOfStock|networkUnavailable)$", example: "paymentDeclined"))
        var reason: String

        init(reason: Reason) {
            self.reason = reason.rawValue
        }
    }

    @Event
    struct CheckoutStarted {
        var itemCount: Int
    }

    @Event
    struct CartViewed {
        var itemCount: Int
    }

    @Test("A failure is tracked with a typed reason, not an error string")
    func typedFailure() {
        let tracker = Tracker()

        tracker.track(CheckoutFailed(reason: .paymentDeclined))
        tracker.track(CheckoutFailed(reason: .networkUnavailable))
    }

    @Test("A funnel step is a typed event, not a log line")
    func funnelStep() {
        let tracker = Tracker()

        tracker.track(CheckoutStarted(itemCount: 3))
    }

    @Test("A request is traced, and the product fact is tracked once inside its span")
    func spanAndEvent() {
        let tracker = Tracker()

        withSpan("GET /cart") { _ in
            tracker.track(CartViewed(itemCount: 3))
        }
    }
}
