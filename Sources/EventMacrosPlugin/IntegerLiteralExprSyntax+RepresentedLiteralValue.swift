// swift-syntax 601 added `IntegerLiteralExprSyntax.representedLiteralValue`; 600, the oldest
// release the plugin accepts, lacks it. This is the same reading under the same name, so the call
// sites don't change and the file can go when the floor reaches 601.
#if !canImport(SwiftSyntax601)
import SwiftSyntax

extension IntegerLiteralExprSyntax {
    /// The literal's value, its radix prefix (`0b`, `0o`, `0x`) read and its underscores dropped;
    /// `nil` when the literal has a syntax error or its value doesn't fit an `Int`.
    var representedLiteralValue: Int? {
        guard !hasError else { return nil }
        let text = literal.text
        let (prefixLength, radix) = switch text.prefix(2) {
        case "0b": (2, 2)
        case "0o": (2, 8)
        case "0x": (2, 16)
        default: (0, 10)
        }
        return Int(text.dropFirst(prefixLength).filter { $0 != "_" }, radix: radix)
    }
}
#endif
