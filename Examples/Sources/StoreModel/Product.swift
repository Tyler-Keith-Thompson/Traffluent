/// Something the store sells.
public struct Product: Identifiable, Hashable, Sendable {
    /// The product's identifier, a lowercase slug such as `canvas-tote`: what its events name it by.
    public var id: String
    /// The name the store shows.
    public var name: String
    /// The price of one, in cents.
    public var priceInCents: Int

    /// A product called `name`, at `priceInCents`.
    ///
    /// - Parameters:
    ///   - id: The product's identifier, a lowercase slug.
    ///   - name: The name the store shows.
    ///   - priceInCents: The price of one, in cents.
    public init(id: String, name: String, priceInCents: Int) {
        self.id = id
        self.name = name
        self.priceInCents = priceInCents
    }
}

extension Product {
    /// Every product the store sells, in the order the catalog shows them.
    public static let catalog = [
        Product(id: "canvas-tote", name: "Canvas Tote", priceInCents: 2_400),
        Product(id: "enamel-mug", name: "Enamel Mug", priceInCents: 1_800),
        Product(id: "wool-beanie", name: "Wool Beanie", priceInCents: 3_200),
        Product(id: "field-notebook", name: "Field Notebook", priceInCents: 1_200),
    ]
}
