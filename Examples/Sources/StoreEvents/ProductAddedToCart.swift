public import EventMacros

/// Someone added `quantity` of the product `productID` to their cart.
///
/// Both properties carry a rule the tracker checks before anything else: the product's
/// identifier is a lowercase slug, and the quantity is 1 to 10, as many as the product screen
/// offers. An event that breaks one is rejected, never delivered, and reported on the tracker's
/// `rejectionReports`.
@Event(name: "product_added_to_cart")
public struct ProductAddedToCart: Equatable {
    /// The product's identifier, such as `canvas-tote`.
    @Constrained(.pattern("^[a-z0-9]+(-[a-z0-9]+)*$", example: "canvas-tote"))
    public var productID: String
    /// How many were added.
    @Constrained(.minimum(1), .maximum(10))
    public var quantity: Int

    /// The event for `quantity` of the product `productID` added to a cart.
    ///
    /// - Parameters:
    ///   - productID: The product's identifier.
    ///   - quantity: How many were added.
    public init(productID: String, quantity: Int) {
        self.productID = productID
        self.quantity = quantity
    }
}
