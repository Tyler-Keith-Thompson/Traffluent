/// What reading a map's key found: the key looked for, another one, or no text string at all.
@usableFromInline
enum KeyOutcome {
    /// The key looked for; its bytes end at `end`.
    case matched(end: Int)
    /// Another key; its bytes end at `end`.
    case different(end: Int)
    /// An item other than a text string, not yet read.
    case notText
    /// A head that runs past the end or isn't well formed.
    case failed(BinaryDecodingError)
}
