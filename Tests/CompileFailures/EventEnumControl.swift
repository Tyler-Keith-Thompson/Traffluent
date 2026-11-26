// Must compile: raw-value enums that are Codable, one declared inside the event, whose cases the
// macro lists, and one outside, whose cases CaseIterable gives, so the checks above fail for the
// missing conformance alone.

import EventMacros

enum Priority: Int, Codable, CaseIterable {
    case low
    case high
}

@Event
struct CheckoutFailed {
    enum Reason: String, Codable {
        case paymentDeclined
        case outOfStock = "out_of_stock"
    }
    var reason: Reason
    var previous: Reason?
    var priority: Priority
}
