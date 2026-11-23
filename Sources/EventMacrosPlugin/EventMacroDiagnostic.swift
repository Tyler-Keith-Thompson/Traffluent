import SwiftDiagnostics

/// Why `@Event` or `@Constrained` can't expand: each is an error at the node that causes it.
// An Error too, so a parse can return a Result whose failure is the diagnostic to report.
enum EventMacroDiagnostic: DiagnosticMessage, Error {
    case notAStruct
    case missingTypeAnnotation
    case lazyProperty
    case destructuringPattern
    case nameNotALiteral
    case emptyName
    case versionNotAPositiveLiteral
    case constraintNotAKeyword
    case countNotANonNegativeLiteral(keyword: String)
    case boundNotANumberLiteral(keyword: String)
    case patternNotALiteral
    case invalidPattern(pattern: String)
    case exampleBreaksKeyword(example: String, keyword: String)
    case unsatisfiable(lower: String, upper: String)
    case constrainedNotStoredProperty

    var message: String {
        switch self {
        case .notAStruct:
            "@Event applies only to a struct"
        case .missingTypeAnnotation:
            "@Event needs the type of every stored property written out; add a type annotation"
        case .lazyProperty:
            "@Event can't encode a lazy property; make it a stored or a computed property"
        case .destructuringPattern:
            "@Event can't encode a destructuring pattern; declare each property on its own"
        case .nameNotALiteral:
            "@Event's name must be a string literal without interpolation"
        case .emptyName:
            "@Event's name must not be empty"
        case .versionNotAPositiveLiteral:
            "@Event's version must be a positive integer literal"
        case .constraintNotAKeyword:
            "@Constrained takes keywords written out, such as .minLength(1), .minimum(0) or .pattern(\"^[a-z]+$\", example: \"abc\")"
        case .countNotANonNegativeLiteral(let keyword):
            "@Constrained's \(keyword) must be a non-negative integer literal"
        case .boundNotANumberLiteral(let keyword):
            "@Constrained's \(keyword) must be a number literal"
        case .patternNotALiteral:
            "@Constrained's pattern and its example must be string literals without interpolation"
        case .invalidPattern(let pattern):
            "@Constrained's pattern \(pattern) isn't a valid regular expression"
        case .exampleBreaksKeyword(let example, let keyword):
            "@Constrained's example \"\(example)\" breaks \(keyword); give an example every constraint on the property accepts"
        case .unsatisfiable(let lower, let upper):
            "@Constrained's \(lower) and \(upper) leave no value that satisfies both"
        case .constrainedNotStoredProperty:
            "@Constrained applies only to a stored instance property of an @Event struct"
        }
    }

    var diagnosticID: MessageID {
        let id = switch self {
        case .notAStruct: "notAStruct"
        case .missingTypeAnnotation: "missingTypeAnnotation"
        case .lazyProperty: "lazyProperty"
        case .destructuringPattern: "destructuringPattern"
        case .nameNotALiteral: "nameNotALiteral"
        case .emptyName: "emptyName"
        case .versionNotAPositiveLiteral: "versionNotAPositiveLiteral"
        case .constraintNotAKeyword: "constraintNotAKeyword"
        case .countNotANonNegativeLiteral: "countNotANonNegativeLiteral"
        case .boundNotANumberLiteral: "boundNotANumberLiteral"
        case .patternNotALiteral: "patternNotALiteral"
        case .invalidPattern: "invalidPattern"
        case .exampleBreaksKeyword: "exampleBreaksKeyword"
        case .unsatisfiable: "unsatisfiable"
        case .constrainedNotStoredProperty: "constrainedNotStoredProperty"
        }
        return MessageID(domain: "EventMacros", id: id)
    }

    var severity: DiagnosticSeverity {
        .error
    }
}
