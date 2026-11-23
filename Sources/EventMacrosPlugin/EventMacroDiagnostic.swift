import SwiftDiagnostics

/// Why `@Event` can't expand: each is an error at the node that causes it.
enum EventMacroDiagnostic: String, DiagnosticMessage {
    case notAStruct
    case missingTypeAnnotation
    case lazyProperty
    case destructuringPattern
    case nameNotALiteral
    case emptyName
    case versionNotAPositiveLiteral

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
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "EventMacros", id: rawValue)
    }

    var severity: DiagnosticSeverity {
        .error
    }
}
