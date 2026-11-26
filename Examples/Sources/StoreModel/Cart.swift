import StoreEvents
import Trackers

/// What a shopper is about to buy: a line per product, and the promotion they applied.
///
/// The cart tracks what happens to it through `Tracker.current`, so the code that changes a cart
/// can't forget the event. The app bootstraps its tracker, which `Tracker.current` reaches from a
/// button's action, and a test binds its own with `withRecordingTracker` and reads what was
/// tracked.
public struct Cart: Hashable, Sendable {
    /// A product in the cart, and how many of it.
    public struct Line: Hashable, Sendable {
        /// The product.
        public var product: Product
        /// How many of it.
        public var quantity: Int

        /// A line of `quantity` of `product`.
        ///
        /// - Parameters:
        ///   - product: The product.
        ///   - quantity: How many of it.
        public init(product: Product, quantity: Int) {
            self.product = product
            self.quantity = quantity
        }
    }

    /// The cart's lines, in the order their products were first added.
    public private(set) var lines: [Line] = []
    /// The promotion applied, if any.
    public private(set) var promotion: Promotion?

    /// An empty cart.
    public init() {}

    /// Whether the cart holds nothing.
    public var isEmpty: Bool {
        lines.isEmpty
    }

    /// How many items the cart holds, counting each line's quantity.
    public var itemCount: Int {
        lines.reduce(0) { $0.saturatingAdding($1.quantity) }
    }

    /// What the cart costs, in cents, with the promotion's discount, rounded down to a cent,
    /// taken off. A sum past `Int.max` stops there.
    public var totalInCents: Int {
        let subtotal = lines.reduce(0) { $0.saturatingAdding($1.product.priceInCents.saturatingMultiplied(by: $1.quantity)) }
        let discount = subtotal.saturatingMultiplied(by: promotion?.percentOff ?? 0) / 100
        return subtotal.saturatingSubtracting(discount)
    }

    /// The quantities one addition takes: the product screen's range, and the one
    /// `ProductAddedToCart` allows.
    public static let quantities = 1...10

    /// Adds `quantity` of `product`, to its line if the cart has one, and tracks
    /// `ProductAddedToCart` through `Tracker.current`.
    ///
    /// - Parameters:
    ///   - product: The product to add.
    ///   - quantity: How many to add, from ``quantities``.
    /// - Throws: ``QuantityOutOfRange`` when `quantity` isn't in ``quantities``; the cart is
    ///   unchanged and nothing is tracked.
    public mutating func add(_ product: Product, quantity: Int = 1) throws(QuantityOutOfRange) {
        guard Self.quantities.contains(quantity) else { throw QuantityOutOfRange() }
        if let index = lines.firstIndex(where: { $0.product == product }) {
            lines[index].quantity = lines[index].quantity.saturatingAdding(quantity)
        } else {
            lines.append(Line(product: product, quantity: quantity))
        }
        Tracker.current.track(ProductAddedToCart(productID: product.id, quantity: quantity))
    }

    /// Removes the line of `product`, if the cart has one. Nothing is tracked.
    ///
    /// - Parameter product: The product whose line to remove.
    public mutating func remove(_ product: Product) {
        lines.removeAll { $0.product == product }
    }

    /// Applies `promotion`'s coupon, replacing any other, and tracks `PromotionTapped` through
    /// `Tracker.current`: the shopper tapped its banner.
    ///
    /// - Parameter promotion: The promotion whose banner was tapped.
    public mutating func apply(_ promotion: Promotion) {
        self.promotion = promotion
        Tracker.current.track(PromotionTapped(campaign: promotion.campaign))
    }
}
