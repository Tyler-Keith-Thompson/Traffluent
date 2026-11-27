/// Another package's top-level `JSON`, as SwiftyJSON and GenericJSON declare one, for the checks
/// that `import Traffluent` doesn't make the name ambiguous.
public struct JSON: Equatable, Sendable {
    /// The value's text.
    public var text: String

    /// A value of `text`.
    public init(text: String) {
        self.text = text
    }
}
