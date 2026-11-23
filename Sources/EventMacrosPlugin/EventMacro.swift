import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@Event`: an extension of the struct it is attached to that conforms it to `Event` and
/// `BinaryCodable`, with its `name`, `consentCategory` and `schema`, and its encoding field by
/// field in declaration order.
///
/// The generated code names the library's types by their modules (`Events.Event`), so a type of
/// the same name in the event's module can't capture them.
public struct EventMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structure = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: node, message: EventMacroDiagnostic.notAStruct))
            return []
        }
        let (arguments, argumentDiagnostics) = EventArguments.arguments(of: node)
        let (properties, propertyDiagnostics) = StoredProperty.properties(of: structure.memberBlock.members)
        let diagnostics = argumentDiagnostics + propertyDiagnostics
        guard diagnostics.isEmpty else {
            diagnostics.forEach(context.diagnose)
            return []
        }
        let access = structure.modifiers.first { [.keyword(.public), .keyword(.package)].contains($0.name.tokenKind) }
            .map { "\($0.name.text) " } ?? ""
        let conformances = [("Event", "Events.Event"), ("BinaryCodable", "Persistence.BinaryCodable")]
            .filter { name, _ in protocols.contains { $0.trimmedDescription.split(separator: ".").last.map(String.init) == name } }
            .map { $0.1 }
        let inheritance = conformances.isEmpty ? "" : ": " + conformances.joined(separator: ", ")
        // The requirements come before the encoding, so a property that isn't BinaryCodable is
        // first reported where the error names it.
        let members = [
            arguments.name.map { "\(access)static var name: String {\n    \($0)\n}" },
            arguments.consent.map { "\(access)static var consentCategory: Events.ConsentCategory {\n    \($0)\n}" },
            schema(of: properties, version: arguments.version, access: access),
        ] + requirements(of: properties) + [
            encode(properties, access: access),
            decode(properties, access: access),
        ]
        let body = members.compactMap { $0 }.joined(separator: "\n\n")
        // The expansion is formatted after it returns, which indents the members.
        let source = "extension \(type.trimmedDescription)\(inheritance) {\n\(body)\n}"
        return [DeclSyntax(stringLiteral: source).cast(ExtensionDeclSyntax.self)]
    }

    private static func schema(of properties: [StoredProperty], version: Int, access: String) -> String {
        let entries = properties.map {
            "        Events.EventSchema.Property(name: \"\($0.name)\", typeName: \"\($0.typeName)\", isOptional: \($0.isOptional)),"
        }
        let list = entries.isEmpty ? "[]" : "[\n" + entries.joined(separator: "\n") + "\n    ]"
        return """
            \(access)static var schema: Events.EventSchema {
                Events.EventSchema(name: Self.name, version: \(version), properties: \(list))
            }
            """
    }

    private static func encode(_ properties: [StoredProperty], access: String) -> String {
        let lines = properties.map { "    encoder.encode(self.\($0.identifier))" }
        return "\(access)func encode(to encoder: inout Persistence.BinaryEncoder) {\n" + lines.map { $0 + "\n" }.joined() + "}"
    }

    private static func decode(_ properties: [StoredProperty], access: String) -> String {
        let lines = properties.map { "    self.\($0.identifier) = try decoder.decode()" }
        return "\(access)init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {\n"
            + lines.map { $0 + "\n" }.joined() + "}"
    }

    /// One function per property whose label is the property's name, and a body that calls each:
    /// a property whose type isn't `BinaryCodable` fails to compile there, and the error names the
    /// function with its label, `requireBinaryCodable(plan:)`. The encoding's own calls name only
    /// `encode`. The body is never called, so it costs nothing at run time.
    private static func requirements(of properties: [StoredProperty]) -> [String] {
        guard !properties.isEmpty else { return [] }
        // An opaque type rather than a named generic parameter, which could shadow one of the
        // event's own.
        let functions = properties.map {
            "private static func requireBinaryCodable(\($0.label): KeyPath<Self, some Persistence.BinaryCodable>) {}"
        }
        let calls = properties.map { "    requireBinaryCodable(\($0.label): \\.\($0.identifier))\n" }.joined()
        return functions + ["private static var binaryCodableRequirements: Void {\n\(calls)}"]
    }
}
