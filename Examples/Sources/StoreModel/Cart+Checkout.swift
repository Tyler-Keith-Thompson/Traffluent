public import Foundation
import StoreEvents
import Trackers

extension Cart {
    /// Tracks `CheckoutStarted` through `Tracker.current`, with the cart's item count and its
    /// promotion's coupon code: the shopper opened the checkout.
    public func startCheckout() {
        Tracker.current.track(CheckoutStarted(cartSize: itemCount, coupon: promotion?.couponCode))
    }

    /// Places an order of everything in the cart, empties the cart, and tracks `OrderCompleted`
    /// through `Tracker.current`.
    ///
    /// - Parameters:
    ///   - expressShipping: Whether the order ships express.
    ///   - id: The order's identifier; a new one by default.
    ///   - date: When the order is placed; now by default.
    /// - Returns: The order placed.
    public mutating func placeOrder(expressShipping: Bool, id: UUID = UUID(), at date: Date = .now) -> Order {
        let order = Order(id: id, lines: lines, totalInCents: totalInCents, expressShipping: expressShipping, placedAt: date)
        self = Cart()
        Tracker.current.track(OrderCompleted(order))
        return order
    }
}

extension OrderCompleted {
    /// The event for placing `order`: its products' identifiers, one per line, and its total in
    /// dollars.
    fileprivate init(_ order: Order) {
        self.init(
            orderID: order.id,
            total: Double(order.totalInCents) / 100,
            // A cart large enough to pass 65,535 items is clamped rather than trapping: the count
            // is for analytics, and the order itself keeps every line.
            itemCount: UInt16(clamping: order.lines.reduce(0) { $0.saturatingAdding($1.quantity) }),
            items: order.lines.map(\.product.id),
            completedAt: order.placedAt,
            express: order.expressShipping
        )
    }
}
