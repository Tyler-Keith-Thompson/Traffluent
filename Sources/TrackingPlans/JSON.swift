/// A JSON value, rendered the same way on every platform and release.
///
/// Written here rather than with Foundation's `JSONEncoder`, whose key order and pretty-printed
/// spacing are Foundation's to change: a plan's bytes are committed and compared, so they must not
/// move when the toolchain does. swift-json-schema's OrderedJSON renders deterministically too, but
/// would be a dependency of the library for a few dozen lines.
indirect enum JSON: Hashable, Sendable {
    case string(String)
    case integer(Int64)
    case boolean(Bool)
    case array([JSON])
    case object([String: JSON])

    /// The value as JSON text: two-space indentation, `"key": value`, object keys in the order of
    /// their UTF-8 bytes, and an empty array or object on one line, as JavaScript's
    /// `JSON.stringify(value, null, 2)` writes it.
    var rendered: String {
        var text = ""
        render(into: &text, indentation: "")
        return text
    }

    private func render(into text: inout String, indentation: String) {
        switch self {
        case .string(let string):
            string.renderQuoted(into: &text)
        case .integer(let integer):
            text += String(integer)
        case .boolean(let boolean):
            text += boolean ? "true" : "false"
        case .array(let elements):
            guard !elements.isEmpty else {
                text += "[]"
                return
            }
            let inner = indentation + "  "
            text += "[\n"
            for (offset, element) in elements.enumerated() {
                text += inner
                element.render(into: &text, indentation: inner)
                text += offset == elements.count - 1 ? "\n" : ",\n"
            }
            text += indentation + "]"
        case .object(let members):
            guard !members.isEmpty else {
                text += "{}"
                return
            }
            let inner = indentation + "  "
            let sorted = members.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
            text += "{\n"
            for (offset, member) in sorted.enumerated() {
                text += inner
                member.key.renderQuoted(into: &text)
                text += ": "
                member.value.render(into: &text, indentation: inner)
                text += offset == sorted.count - 1 ? "\n" : ",\n"
            }
            text += indentation + "}"
        }
    }
}

extension String {
    /// Appends the string as a JSON string literal: quotes, backslashes and control characters
    /// escaped (RFC 8259, section 7), everything else as it is.
    fileprivate func renderQuoted(into text: inout String) {
        text += "\""
        for scalar in unicodeScalars {
            switch scalar {
            case "\"": text += "\\\""
            case "\\": text += "\\\\"
            case "\n": text += "\\n"
            case "\r": text += "\\r"
            case "\t": text += "\\t"
            case "\u{08}": text += "\\b"
            case "\u{0C}": text += "\\f"
            case "\u{00}"..."\u{1F}":
                let hex = String(scalar.value, radix: 16, uppercase: true)
                text += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default:
                text.unicodeScalars.append(scalar)
            }
        }
        text += "\""
    }
}
