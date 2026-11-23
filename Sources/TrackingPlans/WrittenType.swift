/// A property's type as written in source, parsed as far as a tracking plan reads it: named types
/// with their generic arguments, optionals and array shorthand.
///
/// The schema holds a type's text, not the type: the macro sees syntax only, so a typealias or a
/// type of the app's own is just a name here.
indirect enum WrittenType: Hashable {
    /// A named type: its dotted components (`Swift`, `Int`) and generic arguments.
    case named([String], [WrittenType])
    /// `T?` or `T!`.
    case optional(WrittenType)
    /// `[T]`.
    case array(WrittenType)

    /// The type `text` spells, or `nil` for one this grammar doesn't cover (a dictionary, a tuple,
    /// a function, `some P` or `any P`).
    ///
    /// - Complexity: O(*n*) in the text's length.
    init?(parsing text: String) {
        var parser = Parser(Array(text))
        guard let type = parser.type(), parser.isAtEnd else { return nil }
        self = type
    }

    /// The type written back as source, canonically spaced.
    var source: String {
        switch self {
        case .named(let components, let arguments):
            components.joined(separator: ".") + (arguments.isEmpty ? "" : "<" + arguments.map(\.source).joined(separator: ", ") + ">")
        case .optional(let wrapped):
            wrapped.source + "?"
        case .array(let element):
            "[" + element.source + "]"
        }
    }

    /// The type's generic arguments when it is named `name`, alone or qualified by one of
    /// `modules`; `nil` when it is another type.
    func names(_ name: String, in modules: Set<String>) -> [WrittenType]? {
        guard case .named(let components, let arguments) = self, components.last == name else { return nil }
        switch components.count {
        case 1: return arguments
        case 2 where modules.contains(components[0]): return arguments
        default: return nil
        }
    }
}

/// A recursive-descent parser over a type's characters, with an integer cursor.
private struct Parser {
    private let characters: [Character]
    private var position = 0

    init(_ characters: [Character]) {
        self.characters = characters
    }

    var isAtEnd: Bool {
        mutating get {
            skipWhitespace()
            return position == characters.count
        }
    }

    /// `primary ('?' | '!')*`
    mutating func type() -> WrittenType? {
        guard var type = primary() else { return nil }
        while consume("?") || consume("!") {
            type = .optional(type)
        }
        return type
    }

    /// `'[' type ']' | name ('.' name)* ('<' type (',' type)* '>')?`
    private mutating func primary() -> WrittenType? {
        if consume("[") {
            guard let element = type(), consume("]") else { return nil }
            return .array(element)
        }
        guard let first = identifier() else { return nil }
        var components = [first]
        while consume(".") {
            guard let next = identifier() else { return nil }
            components.append(next)
        }
        var arguments: [WrittenType] = []
        if consume("<") {
            repeat {
                guard let argument = type() else { return nil }
                arguments.append(argument)
            } while consume(",")
            guard consume(">") else { return nil }
        }
        return .named(components, arguments)
    }

    private mutating func identifier() -> String? {
        skipWhitespace()
        let start = position
        while position < characters.count, characters[position].isIdentifierCharacter {
            position += 1
        }
        // A name starting with a digit, or `some P` and `any P`, which leave a second name unread,
        // aren't types a plan maps; they come out as the unknown types they are either way.
        guard position > start else { return nil }
        return String(characters[start..<position])
    }

    private mutating func consume(_ character: Character) -> Bool {
        skipWhitespace()
        guard position < characters.count, characters[position] == character else { return false }
        position += 1
        return true
    }

    private mutating func skipWhitespace() {
        while position < characters.count, characters[position].isWhitespace {
            position += 1
        }
    }
}

extension Character {
    /// Letters, digits and `_`: what a Swift identifier holds, near enough for a type's name.
    fileprivate var isIdentifierCharacter: Bool {
        isLetter || isNumber || self == "_"
    }
}
