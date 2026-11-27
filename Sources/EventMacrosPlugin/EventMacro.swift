import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@Event`: an extension of the struct it is attached to that conforms it to `Event`,
/// `Encodable` and `Decodable`, with its `name`, `consentCategory`, `schemaVersion`, `schema`
/// and, when a property declares constraints with `@Constrained`, its `constraintViolation()`,
/// and its coding: a keyed container of its stored properties, each under its name, an optional's
/// `nil` left out, read back with each property's default value when its key is missing.
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
        let enums = RawValueEnum.enums(in: structure.memberBlock.members)
        let held = properties.map { RawValueEnum.held(by: $0, in: enums, structure: structure.name.text) }
        // Once per enum, however many properties hold it. An enum nested in the event must declare
        // Codable in its inheritance clause: one that adds it in an extension is reported too, a
        // deliberate limit, as the macro sees only the struct. An enum declared elsewhere is left
        // to the requirement below, as is one whose clause lists a protocol the macro doesn't know.
        let lacking = held.compactMap { $0?.lacksCodable == true ? $0?.name : nil }
        let uncodable = Set(lacking).sorted()
        let enumDiagnostics = uncodable.compactMap { name in
            enums[name].map { Diagnostic(node: $0.inheritance, message: EventMacroDiagnostic.enumNotCodable(name: name)) }
        }
        let diagnostics = argumentDiagnostics + propertyDiagnostics + enumDiagnostics
        guard diagnostics.isEmpty else {
            diagnostics.forEach(context.diagnose)
            return []
        }
        let access = structure.modifiers.first { [.keyword(.public), .keyword(.package)].contains($0.name.tokenKind) }
            .map { "\($0.name.text) " } ?? ""
        let conformances = [("Event", "Events.Event"), ("Encodable", "Swift.Encodable"), ("Decodable", "Swift.Decodable")]
            .filter { name, _ in protocols.contains { $0.trimmedDescription.split(separator: ".").last.map(String.init) == name } }
            .map { $0.1 }
        let inheritance = conformances.isEmpty ? "" : ": " + conformances.joined(separator: ", ")
        // The requirements come before the coding, so a property that isn't Codable is first
        // reported where the error names it.
        let members = [
            arguments.name.map { "\(access)static var name: String {\n    \($0)\n}" },
            arguments.consent.map { "\(access)static var consentCategory: Events.ConsentCategory {\n    \($0)\n}" },
            arguments.version.map { "\(access)static var schemaVersion: Int {\n    \($0)\n}" },
            schema(of: Array(zip(properties, held)), access: access),
            constraintViolation(of: properties, access: access),
        ] + requirements(of: properties) + [
            codingKeys(of: properties),
            encode(properties, access: access),
            decode(properties, access: access),
        ] + decodeFunctions(of: properties)
        let body = members.compactMap { $0 }.joined(separator: "\n\n")
        // The expansion is formatted after it returns, which indents the members.
        let source = "extension \(type.trimmedDescription)\(inheritance) {\n\(body)\n}"
        let undiscoverable = undiscoverableNote(structure, in: context)
        undiscoverable.map(context.diagnose)
        let record = undiscoverable == nil ? discoveryRecord(of: type.trimmedDescription) : nil
        return ([source] + [record].compactMap { $0 }).map { DeclSyntax(stringLiteral: $0).cast(ExtensionDeclSyntax.self) }
    }

    /// The extension placing the event's record in the binary, which `DiscoveredEvent.all` reads:
    /// in the library's section of each object format, kept by `@used` from being stripped.
    private static func discoveryRecord(of type: String) -> String {
        """
        extension \(type) {
            #if objectFormat(MachO)
            @section("__DATA_CONST,__trfl_events")
            #elseif objectFormat(ELF)
            @section("trfl_events")
            #endif
            @used
            private nonisolated static let __discoveryRecord: Events.__EventDiscovery.Record = (0x6576_6E74, 0, { outValue, type, _, _ in Events.__EventDiscovery.load(\(type).self, schema: \(type).schema, into: outValue, ofType: type) }, 0, 0)
        }
        """
    }

    /// A note saying `DiscoveredEvent.all` can't find the event, when `structure` can't hold its
    /// record, a static stored property, which neither a generic type nor one nested in a generic
    /// type can; `nil` when it can.
    // A note rather than a warning: first-party builds treat warnings as errors, and Swift has no
    // way to silence one diagnostic at its site, so a warning would make every generic @Event fail
    // to build, this repository's own fixtures included. The note still shows where the event is
    // declared.
    // Only generic declarations are checked: a type declared in a function can't take an
    // extension macro at all. A type nested in an extension of a generic type isn't seen as generic
    // from here (an extension's syntax doesn't say whether the type it extends is generic), so it
    // gets the record and fails to compile, naming the static stored property;
    // //Tests/CompileFailures:EventInGenericExtension pins that error.
    private static func undiscoverableNote(_ structure: StructDeclSyntax, in context: some MacroExpansionContext) -> Diagnostic? {
        if let clause = structure.genericParameterClause {
            return Diagnostic(node: clause, message: EventMacroDiagnostic.genericNotDiscovered)
        }
        guard context.lexicalContext.contains(where: \.isGenericType) else { return nil }
        return Diagnostic(node: structure.name, message: EventMacroDiagnostic.nestedInGenericNotDiscovered)
    }

    /// `schema`, each property with the enum declared in the struct it holds, if any.
    private static func schema(of properties: [(StoredProperty, RawValueEnum?)], access: String) -> String {
        let entries = properties.map { property, held in
            let defaultValue = property.hasDefaultValue ? "hasDefaultValue: true, " : ""
            let enumeration = enumeration(of: property, holding: held).map { ", enumeration: \($0)" } ?? ""
            return "        Events.EventSchema.Property(name: \"\(property.name)\", typeName: \"\(property.typeName)\", isOptional: \(property.isOptional), \(defaultValue)hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.\(property.identifier)), keywords: \(property.keywords)\(enumeration)),"
        }
        let list = entries.isEmpty ? "[]" : "[\n" + entries.joined(separator: "\n") + "\n    ]"
        return """
            \(access)static var schema: Events.EventSchema {
                Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: \(list))
            }
            """
    }

    /// A property's `enumeration:` argument: the cases of `held`, the raw-value enum declared in the
    /// struct it holds, each written out; read at run time for any type but a standard scalar or a
    /// date, which is no enum; `nil`, no argument, for those.
    ///
    /// The cases are written as `Self.<Enum>.<case>`, so the compiler gives each its raw value,
    /// implicit ones included.
    private static func enumeration(of property: StoredProperty, holding held: RawValueEnum?) -> String? {
        if let held, let cases = held.cases {
            // Each case as an implicit member in backticks: `Self.Kind.Type` and `Self.Kind.self`
            // name the metatype and the type even in backticks, but `.`Type`` names the case.
            return "Events.EventSchema.Enumeration(cases: [" + cases.map { ".`\($0)`" }.joined(separator: ", ") + "] as [Self.\(held.name)])"
        }
        guard !property.isStandardScalar, !property.isDate, property.dateArrayElement == nil else { return nil }
        return "Events.EventSchema.Enumeration(of: \\Self.\(property.identifier))"
    }

    /// `constraintViolation()`, checking each property's declared constraints in declaration order,
    /// or `nil` when no property declares one, which leaves `Event`'s default.
    ///
    /// Each constraint is built in a typed context, `Events.Constraint<T>` for a property of type
    /// `T`, so one that doesn't apply to the type is a compile error. An optional property is
    /// checked only when it holds a value.
    ///
    /// Building a constraint throws `InvalidConstraint` for an argument no schema can hold. The
    /// macro diagnoses every such literal it can read against the property's type: a negative
    /// count, a pattern that doesn't compile or match its example, an integer bound a `Double`
    /// can't hold exactly, a bound that overflows its floating-point type. Past those (a type the
    /// macro doesn't know, such as a typealias of `Int`), a constraint that throws makes every
    /// event a violation naming the declaration and its error, so the tracker rejects and reports
    /// it rather than track it unchecked.
    private static func constraintViolation(of properties: [StoredProperty], access: String) -> String? {
        let checks = properties.compactMap { property -> String? in
            guard !property.constraints.isEmpty else { return nil }
            let value = property.isOptional ? "value" : "self.\(property.identifier)"
            let checks = property.constraints.map { constraint in
                "do throws(Events.InvalidConstraint) {\n"
                    + "    let constraint: Events.Constraint<\(property.typeName)> = try \(constraint.source)\n"
                    + "    if !constraint.isSatisfied(by: \(value)) {\n"
                    + "        return Events.ConstraintViolation(property: \"\(property.name)\", keyword: constraint.keyword)\n"
                    + "    }\n"
                    + "} catch {\n"
                    + "    return Events.ConstraintViolation(property: \"\(property.name)\", invalidConstraint: \(constraint.source.stringLiteral), error: error)\n"
                    + "}"
            }.joined(separator: "\n")
            guard property.isOptional else { return checks }
            return "if let value = self.\(property.identifier) {\n\(checks)\n}"
        }
        guard !checks.isEmpty else { return nil }
        return "\(access)func constraintViolation() -> Events.ConstraintViolation? {\n" + checks.map { $0 + "\n" }.joined() + "return nil\n}"
    }

    /// `CodingKeys`: a key per property, its name as its string value, in declaration order.
    private static func codingKeys(of properties: [StoredProperty]) -> String {
        // No raw type without cases: an enum with none can't declare one.
        guard !properties.isEmpty else { return "private enum CodingKeys: Swift.CodingKey {\n}" }
        let cases = properties.map { "    case \($0.identifier)\n" }.joined()
        return "private enum CodingKeys: Swift.String, Swift.CodingKey {\n\(cases)}"
    }

    /// `encode(to:)`, writing each property under its name (the encoder orders the keys: the CBOR
    /// package sorts them canonically): an optional's `nil` left out, unless the property has a
    /// default value, which a missing key would read instead; a `Date`, or each in a `[Date]` or
    /// `[Date?]`, as the seconds since 2001 it stores, which read back exactly.
    private static func encode(_ properties: [StoredProperty], access: String) -> String {
        let lines = properties.map { property in
            let unwrap = property.isOptional ? "?" : ""
            let seconds = property.dateArrayElement.map { element in
                element.isOptional ? "\(unwrap).map { $0?.timeIntervalSinceReferenceDate }" : "\(unwrap).map(\\.timeIntervalSinceReferenceDate)"
            }
            let value = "self.\(property.identifier)" + (property.isDate ? "\(unwrap).timeIntervalSinceReferenceDate" : seconds ?? "")
            let method = property.isOptional && !property.hasDefaultValue ? "encodeIfPresent" : "encode"
            return "    try container.\(method)(\(value), forKey: .\(property.identifier))\n"
        }.joined()
        let body = properties.isEmpty
            ? "    _ = encoder.container(keyedBy: CodingKeys.self)\n"
            : "    var container = encoder.container(keyedBy: CodingKeys.self)\n\(lines)"
        return "\(access)func encode(to encoder: any Swift.Encoder) throws {\n\(body)}"
    }

    /// `init(from:)`, reading each property by its name, in declaration order. An optional
    /// property missing from the container, as one added since it was written is, or holding
    /// `nil`, reads as `nil`. One with a default value reads as that value when its key is missing,
    /// which the property already holds as the initializer starts, so the declaration's expression
    /// runs once, in its own context.
    private static func decode(_ properties: [StoredProperty], access: String) -> String {
        let reads = properties.map { property in
            let key = ".\(property.identifier)"
            let method = property.isOptional ? "decodeIfPresent" : "decode"
            // A standard scalar, or the Double a Date is written as, is read by the container's
            // own method for its type, which a generic read would go through a decoder of its own
            // for.
            let read = property.isDate || property.isStandardScalar || property.dateArrayElement != nil
                ? "container.\(method)(\(Self.writtenType(of: property)).self, forKey: \(key))"
                : "Self.\(method)Value(from: container, forKey: \(key))"
            let date = "\(property.typeName).init(timeIntervalSinceReferenceDate:)"
            let value = property.dateArrayElement.map { element in
                Self.dates(from: read, element: element, isOptional: property.isOptional)
            } ?? (!property.isDate ? read : property.isOptional ? "\(read).map(\(date))" : "\(property.typeName)(timeIntervalSinceReferenceDate: \(read))")
            let assignment = "self.\(property.identifier) = try \(value)"
            guard property.hasDefaultValue else { return "    \(assignment)\n" }
            return "    if container.contains(\(key)) {\n        \(assignment)\n    }\n"
        }.joined()
        let body = properties.isEmpty
            ? "    _ = try decoder.container(keyedBy: CodingKeys.self)\n"
            : "    let container = try decoder.container(keyedBy: CodingKeys.self)\n\(reads)"
        return "\(access)init(from decoder: any Swift.Decoder) throws {\n\(body)}"
    }

    /// The type a property is written as, which `init(from:)` reads: `Swift.Double` for a `Date`,
    /// an array of them for an array of dates, the type itself otherwise.
    private static func writtenType(of property: StoredProperty) -> String {
        if property.isDate { return "Swift.Double" }
        guard let element = property.dateArrayElement else { return property.typeName }
        return element.isOptional ? "[Swift.Double?]" : "[Swift.Double]"
    }

    /// The dates an array of seconds `read` holds, each element `nil` where its seconds are, and
    /// the whole `nil` when the property is optional and its array is.
    private static func dates(from read: String, element: DateArrayElement, isOptional: Bool) -> String {
        let date = "\(element.typeName).init(timeIntervalSinceReferenceDate:)"
        let array = element.isOptional ? ".map { $0.map(\(date)) }" : ".map(\(date))"
        return isOptional ? "\(read).map { $0\(array) }" : "\(read)\(array)"
    }

    /// The functions `init(from:)` reads a property of any other type through, those it calls.
    ///
    /// The extension is outside the struct, where a type nested in the struct's enclosing type is
    /// out of scope, so these reads never name the property's type: the functions take it from the
    /// property they assign. Static rather than local functions, which would capture the container.
    private static func decodeFunctions(of properties: [StoredProperty]) -> [String] {
        let generic = properties.filter { !$0.isDate && !$0.isStandardScalar && $0.dateArrayElement == nil }
        return [
            generic.contains { !$0.isOptional }
                ? "private static func decodeValue<Decoded: Swift.Decodable>(from container: Swift.KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Decoded {\n    try container.decode(Decoded.self, forKey: key)\n}"
                : nil,
            generic.contains(where: \.isOptional)
                ? "private static func decodeIfPresentValue<Decoded: Swift.Decodable>(from container: Swift.KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Decoded? {\n    try container.decodeIfPresent(Decoded.self, forKey: key)\n}"
                : nil,
        ].compactMap { $0 }
    }

    /// One function per property whose label is the property's name, and a body that calls each:
    /// a property whose type isn't `Codable` fails to compile there, and the error names the
    /// function with its label, `requireCodable(plan:)`. The coding's own calls name only
    /// `encode` and `decode`. The body is never called, so it costs nothing at run time.
    private static func requirements(of properties: [StoredProperty]) -> [String] {
        guard !properties.isEmpty else { return [] }
        // An opaque type rather than a named generic parameter, which could shadow one of the
        // event's own.
        let functions = properties.map {
            "private static func requireCodable(\($0.label): KeyPath<Self, some Swift.Codable>) {}"
        }
        let calls = properties.map { "    requireCodable(\($0.label): \\.\($0.identifier))\n" }.joined()
        return functions + ["private static var codableRequirements: Void {\n\(calls)}"]
    }
}

extension String {
    /// The string as a Swift string literal: quoted, with its backslashes, quotes and line breaks
    /// escaped.
    fileprivate var stringLiteral: String {
        // By scalar: "\r\n" is one Character, which neither "\r" nor "\n" would match.
        var escaped = ""
        for scalar in unicodeScalars {
            switch scalar {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            default: escaped.unicodeScalars.append(scalar)
            }
        }
        return "\"" + escaped + "\""
    }
}

extension Syntax {
    /// Whether this node declares a generic struct, class, enum or actor.
    fileprivate var isGenericType: Bool {
        let genericParameters = self.as(StructDeclSyntax.self)?.genericParameterClause
            ?? self.as(ClassDeclSyntax.self)?.genericParameterClause
            ?? self.as(EnumDeclSyntax.self)?.genericParameterClause
            ?? self.as(ActorDeclSyntax.self)?.genericParameterClause
        return genericParameters != nil
    }
}
