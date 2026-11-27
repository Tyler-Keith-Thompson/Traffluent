import Foundation

/// A JSON value, rendered the same way on every platform and release: a tracking plan's
/// documents, and the request bodies the JSON batch encoders write (``minified``).
///
/// A number is ``integer(_:)`` when it is a whole number that fits an `Int64`, and
/// ``number(_:)`` otherwise, both when a plan writes it (``number(exactly:)``) and when it reads one,
/// so a value reads back as the case it was written as.
// Written here rather than with Foundation's `JSONEncoder`, whose key order and pretty-printed
// spacing are Foundation's to change: a plan's bytes are committed and compared, and so are request
// bodies, so they must not move when the toolchain does. swift-json-schema's OrderedJSON renders
// deterministically too, but would be a dependency of the library for a few dozen lines. Reading
// is Foundation's `JSONDecoder`'s: what it parses doesn't reach the bytes a plan writes.
public indirect enum JSON: Hashable, Sendable {
    /// `null`.
    case null
    /// A string.
    case string(String)
    /// A whole number in `Int64`'s range.
    case integer(Int64)
    /// A number with a fraction, or a whole one beyond `Int64`'s range: a bound on a `Double`.
    ///
    /// A NaN or infinite value, which no JSON number is, renders as `null`, as JavaScript's
    /// `JSON.stringify` writes it; ``number(exactly:)`` makes none.
    case number(Double)
    /// `true` or `false`.
    case boolean(Bool)
    /// An array of values, in order.
    case array([JSON])
    /// An object of members by name, written in the order of their names' UTF-8 bytes.
    case object([String: JSON])

    /// The JSON value `bytes` hold, or `nil` when they aren't JSON a plan could have written.
    package init?(parsing bytes: [UInt8]) {
        guard let value = try? JSONDecoder().decode(JSON.self, from: Data(bytes)) else { return nil }
        self = value
    }

    /// The members of an object, or `nil` for any other value.
    package var object: [String: JSON]? {
        if case .object(let members) = self { return members }
        return nil
    }

    /// The elements of an array, or `nil` for any other value.
    package var array: [JSON]? {
        if case .array(let elements) = self { return elements }
        return nil
    }

    /// The text of a string, or `nil` for any other value.
    package var string: String? {
        if case .string(let text) = self { return text }
        return nil
    }

    /// `value` as JSON: an ``integer(_:)`` when it is a whole number in `Int64`'s range, a
    /// ``number(_:)`` otherwise, or `nil` when it is NaN or infinite, which no JSON number is.
    public static func number(exactly value: Double) -> JSON? {
        guard value.isFinite else { return nil }
        // -2^63 ..< 2^63: every whole Double in it converts to Int64 exactly.
        if value.rounded() == value, value >= -9_223_372_036_854_775_808, value < 9_223_372_036_854_775_808 {
            return .integer(Int64(value))
        }
        return .number(value)
    }

    /// The value of a number, an integer included, or `nil` for any other value.
    package var double: Double? {
        switch self {
        case .integer(let value): Double(value)
        case .number(let value): value
        default: nil
        }
    }

    /// The value of an integer, or `nil` for any other value.
    package var integer: Int64? {
        if case .integer(let value) = self { return value }
        return nil
    }

    /// The value on one line, with the same spacing and key order as ``rendered``, for messages.
    package var compact: String {
        switch self {
        case .array(let elements):
            "[" + elements.map(\.compact).joined(separator: ", ") + "]"
        case .object(let members):
            "{" + members.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
                .map { JSON.string($0.key).compact + ": " + $0.value.compact }
                .joined(separator: ", ") + "}"
        default:
            rendered
        }
    }

    /// The value as JSON text with no whitespace between its tokens, object keys in the order of
    /// their UTF-8 bytes, as JavaScript's `JSON.stringify(value)` writes it: a request body. A
    /// ``number(_:)`` that is NaN or infinite is `null`.
    public var minified: String {
        switch self {
        case .array(let elements):
            "[" + elements.map(\.minified).joined(separator: ",") + "]"
        case .object(let members):
            "{" + members.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
                .map { JSON.string($0.key).minified + ":" + $0.value.minified }
                .joined(separator: ",") + "}"
        default:
            rendered
        }
    }

    /// The value as JSON text: two-space indentation, `"key": value`, object keys in the order of
    /// their UTF-8 bytes, and an empty array or object on one line, as JavaScript's
    /// `JSON.stringify(value, null, 2)` writes it.
    package var rendered: String {
        var text = ""
        render(into: &text, indentation: "")
        return text
    }

    private func render(into text: inout String, indentation: String) {
        switch self {
        case .null:
            text += "null"
        case .string(let string):
            string.renderQuoted(into: &text)
        case .integer(let integer):
            text += String(integer)
        case .number(let number) where !number.isFinite:
            // Swift would write `nan` or `inf`, which no JSON reader takes.
            text += "null"
        case .number(let number):
            // Swift's shortest representation that reads back as the same Double, the same on
            // every platform: `0.5`, `1e-05`, `1e+20`, each valid JSON.
            text += number.description
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

extension JSON: Decodable {
    // Bool is tried before Int64, which JSONDecoder doesn't read from `true` or `false`, Int64
    // before Double, and both before String, so each value takes the one case that holds it on
    // every platform.
    /// The value `decoder` holds, a whole number in `Int64`'s range read as ``integer(_:)``.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` when the value isn't JSON.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let boolean = try? container.decode(Bool.self) {
            self = .boolean(boolean)
        } else if let integer = try? container.decode(Int64.self) {
            self = .integer(integer)
        } else if let number = try? container.decode(Double.self), let json = JSON.number(exactly: number) {
            self = json
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let elements = try? container.decode([JSON].self) {
            self = .array(elements)
        } else {
            self = .object(try container.decode([String: JSON].self))
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
