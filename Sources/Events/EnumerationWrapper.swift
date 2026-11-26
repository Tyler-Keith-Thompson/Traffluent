/// A type whose JSON is its wrapped type's, or an array of them, which an enumeration looks
/// through.
///
/// Internal, and found by a dynamic cast, as `RefinedKeywords` is.
protocol EnumerationWrapper {
    static var wrappedType: Any.Type { get }
}

extension Optional: EnumerationWrapper {
    static var wrappedType: Any.Type {
        Wrapped.self
    }
}

extension Sensitive: EnumerationWrapper {
    static var wrappedType: Any.Type {
        Value.self
    }
}

extension Array: EnumerationWrapper {
    static var wrappedType: Any.Type {
        Element.self
    }
}
