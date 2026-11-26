public import EventMacros

/// Someone started checking out a cart of `cartSize` items, with `coupon` if they entered one.
@Event(name: "checkout_started", version: 2)
public struct CheckoutStarted: Equatable {
    /// The number of items in the cart.
    public var cartSize: Int
    /// The coupon code entered, if any.
    public var coupon: String?

    /// The event for a checkout of `cartSize` items, with `coupon`.
    ///
    /// - Parameters:
    ///   - cartSize: The number of items in the cart.
    ///   - coupon: The coupon code entered, if any.
    public init(cartSize: Int, coupon: String?) {
        self.cartSize = cartSize
        self.coupon = coupon
    }
}
