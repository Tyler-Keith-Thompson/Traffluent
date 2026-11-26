import SwiftSyntax

/// An enum declared inside an event's struct whose raw value is a `String` or a standard integer
/// type, as written: the macro lists its cases in the schema, which it can't for an enum declared
/// elsewhere.
struct RawValueEnum {
    /// The enum's name, as written.
    let name: String
    /// Its cases' names without backticks, in declaration order; `nil` when a case sits under `#if`,
    /// which the macro can't evaluate.
    let cases: [String]?
    /// Whether its inheritance clause surely lacks `Codable`: every type it lists after the raw type
    /// is a standard protocol that doesn't refine `Codable`, and they aren't both `Encodable` and
    /// `Decodable`. One that lists a type the macro doesn't know, which may refine `Codable`, doesn't.
    let lacksCodable: Bool
    /// The inheritance clause, where a missing `Codable` is reported.
    let inheritance: InheritanceClauseSyntax

    /// The raw-value enums `members` declare, by name.
    static func enums(in members: MemberBlockItemListSyntax) -> [String: RawValueEnum] {
        var enums: [String: RawValueEnum] = [:]
        for member in members {
            guard let declaration = member.decl.as(EnumDeclSyntax.self),
                let inheritance = declaration.inheritanceClause,
                let rawType = inheritance.inheritedTypes.first?.type.trimmedDescription,
                rawTypeNames.contains(rawType.withoutSwiftModule)
            else { continue }
            let name = declaration.name.text
            enums[name] = RawValueEnum(
                name: name,
                cases: declaration.memberBlock.members.caseNames,
                lacksCodable: inheritance.inheritedTypes.dropFirst().map(\.type.trimmedDescription).lacksCodable,
                inheritance: inheritance
            )
        }
        return enums
    }

    /// The enum `property` holds, when it is one of `enums`, written as its name, `Self.` or
    /// `<structure>.` before it, also inside `Optional`, `Sensitive` and arrays.
    static func held(by property: StoredProperty, in enums: [String: RawValueEnum], structure: String) -> RawValueEnum? {
        let leaf = property.leafTypeName
        for prefix in ["", "Self.", "\(structure)."] where leaf.hasPrefix(prefix) {
            if let held = enums[String(leaf.dropFirst(prefix.count))] { return held }
        }
        return nil
    }

    /// The raw value types the macro lists cases for: those a tracking plan maps.
    private static let rawTypeNames: Set<String> = ["String", "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64"]
}

extension MemberBlockItemListSyntax {
    /// The names of the cases an enum's members declare, without the backticks a keyword is
    /// written in (`` `Type` ``); `nil` when one sits under `#if`.
    fileprivate var caseNames: [String]? {
        var names: [String] = []
        for member in self {
            if member.decl.is(IfConfigDeclSyntax.self) { return nil }
            guard let declaration = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            names += declaration.elements.map(\.name.text.withoutBackticks)
        }
        return names
    }
}

extension Array where Element == String {
    /// Whether an enum inheriting these, after its raw type, surely isn't `Codable`: each is a
    /// standard protocol that doesn't refine `Codable`, written alone or qualified by `Swift`, and
    /// they aren't both `Encodable` and `Decodable`.
    fileprivate var lacksCodable: Bool {
        let names = Set(map(\.withoutSwiftModule))
        let unrelated: Set<String> = [
            "Encodable", "Decodable", "CaseIterable", "Hashable", "Equatable", "Comparable", "Sendable", "CustomStringConvertible",
            "CustomDebugStringConvertible",
        ]
        return names.isSubset(of: unrelated) && !names.isSuperset(of: ["Encodable", "Decodable"])
    }
}

extension String {
    /// The identifier without the backticks around it, if any.
    fileprivate var withoutBackticks: String {
        hasPrefix("`") && hasSuffix("`") && count > 1 ? String(dropFirst().dropLast()) : self
    }

    /// The type's name without a leading `Swift.`.
    fileprivate var withoutSwiftModule: String {
        hasPrefix("Swift.") ? String(dropFirst("Swift.".count)) : self
    }
}
