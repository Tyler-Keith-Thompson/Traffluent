// Must not compile: Reason, declared inside the event, lists no Codable, so @Event reports it at
// the enum's inheritance clause.

import EventMacros

@Event
struct CheckoutFailed {
    enum Reason: String {
        case paymentDeclined
        case outOfStock
    }
    var reason: Reason
}
