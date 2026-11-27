/// Two members that `flattened(separator:)` would write under one name.
public struct FlattenedKeyCollision: Error, Sendable, Hashable {
    /// The name both flatten to.
    public var key: String

    /// The collision of two members at `key`.
    ///
    /// - Parameter key: The name both flatten to.
    public init(key: String) {
        self.key = key
    }
}
