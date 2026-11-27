public import JSONValues

extension Dictionary where Key == String, Value == JSON {
    /// The members with every object and array spread into scalar members, for a vendor that takes
    /// only strings, numbers, booleans and `null`.
    ///
    /// A member of an object is named after the object's member, `separator` and its own name;
    /// an element of an array after the array's member, `separator` and its offset, counting from
    /// 0. An empty object or array has no scalar, so it leaves nothing.
    ///
    /// ```swift
    /// let properties: [String: JSON] = ["cart": .object(["size": .integer(2)]), "tags": .array([.string("beta")])]
    /// let flattened = try properties.flattened()  // ["cart.size": 2, "tags.0": "beta"]
    /// ```
    ///
    /// - Parameter separator: What joins a member's name to its container's; `.` by default.
    /// - Returns: The scalar members, by their joined names.
    /// - Throws: ``FlattenedKeyCollision`` when two members flatten to one name, such as a member
    ///   named `cart.size` beside `cart`'s `size`.
    /// - Complexity: O(*n* log *n*) in the scalars, for visiting each object's members in order.
    public func flattened(separator: String = ".") throws(FlattenedKeyCollision) -> [String: JSON] {
        var flattened: [String: JSON] = [:]
        try JSON.object(self).flatten(into: &flattened, name: nil, separator: separator)
        return flattened
    }
}

extension JSON {
    /// Adds the value's scalars to `flattened`, named from `name`; a value at the top has none.
    fileprivate func flatten(into flattened: inout [String: JSON], name: String?, separator: String) throws(FlattenedKeyCollision) {
        switch self {
        case .object(let members):
            // In order, so of two members that collide, the error always names the same key.
            for (key, value) in members.sorted(by: { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }) {
                try value.flatten(into: &flattened, name: name.map { $0 + separator + key } ?? key, separator: separator)
            }
        case .array(let elements):
            for (offset, element) in elements.enumerated() {
                try element.flatten(into: &flattened, name: name.map { $0 + separator + String(offset) } ?? String(offset), separator: separator)
            }
        case .null, .string, .integer, .number, .boolean:
            let key = name ?? ""
            guard flattened.updateValue(self, forKey: key) == nil else {
                throw FlattenedKeyCollision(key: key)
            }
        }
    }
}
