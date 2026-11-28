internal import TrackingPlans

/// How a written type's value is read from its CBOR, and written back to it.
enum Shape {
    /// `T?`, `T!` or `Optional<T>`: `null`, or `T`'s value.
    case optional(WrittenType)
    /// `Sensitive<T>`: `T`'s value, or `null` where it is redacted.
    case sensitive(WrittenType)
    /// `Refined<T, Rule>`, whose value is `T`'s.
    case refined(WrittenType)
    /// `[T]` or `Array<T>`.
    case array(WrittenType)
    /// `Date`: a double of its seconds since 2001, or tag 1's since 1970.
    case date
    /// `Double` or `Float`: a floating-point number, which JSON writes without a fraction when it
    /// is whole, so it reads back as an integer unless the type says otherwise.
    case floatingPoint
    /// Any other type, read for what its value holds.
    case other
}

extension WrittenType {
    /// How the type's value is read, with the module names the plan's documents accept.
    var shape: Shape {
        if case .optional(let wrapped) = self { return .optional(wrapped) }
        if case .array(let element) = self { return .array(element) }
        if let arguments = names("Optional", in: ["Swift"]), arguments.count == 1 { return .optional(arguments[0]) }
        if let arguments = names("Array", in: ["Swift"]), arguments.count == 1 { return .array(arguments[0]) }
        if let arguments = names("Refined", in: ["Events", "Traffluent"]), arguments.count == 2 { return .refined(arguments[0]) }
        if let arguments = names("Sensitive", in: ["Events", "Traffluent"]), arguments.count == 1 { return .sensitive(arguments[0]) }
        if names("Date", in: ["Foundation", "FoundationEssentials"])?.isEmpty == true { return .date }
        for name in ["Double", "Float", "Float64", "Float32"] where names(name, in: ["Swift"])?.isEmpty == true {
            return .floatingPoint
        }
        return .other
    }
}
