import Events

extension EventSchema {
    /// The event's document's file name: `<name>.v<version>.schema.json`, the name's bytes other
    /// than ASCII letters, digits, `_` and `-` percent-encoded, which keeps every name a valid file
    /// name and URI reference and two names' files apart.
    var fileName: String {
        var encoded = ""
        for byte in name.utf8 {
            if byte.isUnreserved {
                encoded.unicodeScalars.append(Unicode.Scalar(byte))
            } else {
                let hex = String(byte, radix: 16, uppercase: true)
                encoded += "%" + (hex.count == 1 ? "0" : "") + hex
            }
        }
        return "\(encoded).v\(version).schema.json"
    }

    /// The event's JSON Schema document, as ``TrackingPlan`` describes it.
    var document: JSON {
        .object([
            "$schema": .string("https://json-schema.org/draft/2020-12/schema"),
            "$id": .string(fileName),
            "title": .string(name),
            "type": .string("object"),
            // Unique: TrackingPlan's initializer rejects a schema with two properties of one name.
            "properties": .object(Dictionary(uniqueKeysWithValues: properties.map { ($0.name, .object($0.schema)) })),
            "required": .array(properties.filter { !$0.isOptional }.map { .string($0.name) }),
            "additionalProperties": .boolean(false),
            "x-traffluent-version": .integer(Int64(version)),
            "x-traffluent-consent-category": .string(consentCategory.name),
        ])
    }
}

extension EventSchema.Property {
    /// The property's schema: its type's, with `null` allowed when it is optional.
    fileprivate var schema: [String: JSON] {
        guard let type = WrittenType(parsing: typeName) else { return ["x-traffluent-swift-type": .string(typeName)] }
        return type.schema(isNullable: isOptional)
    }
}

extension WrittenType {
    /// The type's JSON Schema keywords, allowing `null` too when `isNullable` is set.
    fileprivate func schema(isNullable: Bool) -> [String: JSON] {
        if case .optional(let wrapped) = self {
            return wrapped.schema(isNullable: true)
        }
        if let arguments = names("Optional", in: ["Swift"]), arguments.count == 1 {
            return arguments[0].schema(isNullable: true)
        }
        if let arguments = names("Sensitive", in: ["Events", "Traffluent"]), arguments.count == 1 {
            return arguments[0].schema(isNullable: isNullable).merging(["x-traffluent-sensitive": .boolean(true)]) { $1 }
        }
        if let element = arrayElement {
            return ["type": .type("array", isNullable: isNullable), "items": .object(element.schema(isNullable: false))]
        }
        for scalar in Scalar.all {
            if let arguments = names(scalar.name, in: scalar.modules), arguments.isEmpty {
                return scalar.keywords.merging(["type": .type(scalar.type, isNullable: isNullable)]) { $1 }
            }
        }
        // A type whose JSON shape the plan can't know: any value, null included, is allowed.
        return ["x-traffluent-swift-type": .string(source)]
    }

    private var arrayElement: WrittenType? {
        if case .array(let element) = self { return element }
        if let arguments = names("Array", in: ["Swift"]), arguments.count == 1 { return arguments[0] }
        return nil
    }
}

/// A type a plan maps to a JSON type of its own, with the keywords that narrow it.
private struct Scalar: Sendable {
    let name: String
    let modules: Set<String>
    let type: String
    var keywords: [String: JSON] = [:]

    /// Integers wider than 32 bits get no `maximum`: `Int`'s width depends on the platform, and
    /// one bound for every platform keeps a plan the same everywhere.
    static let all = [
        Scalar(name: "String", modules: ["Swift"], type: "string"),
        Scalar(name: "Bool", modules: ["Swift"], type: "boolean"),
        Scalar(name: "Double", modules: ["Swift"], type: "number"),
        Scalar(name: "Float", modules: ["Swift"], type: "number"),
        Scalar(name: "Int", modules: ["Swift"], type: "integer"),
        Scalar(name: "Int64", modules: ["Swift"], type: "integer"),
        Scalar(name: "Int32", modules: ["Swift"], type: "integer", keywords: bounds(Int64(Int32.min), Int64(Int32.max))),
        Scalar(name: "Int16", modules: ["Swift"], type: "integer", keywords: bounds(Int64(Int16.min), Int64(Int16.max))),
        Scalar(name: "Int8", modules: ["Swift"], type: "integer", keywords: bounds(Int64(Int8.min), Int64(Int8.max))),
        Scalar(name: "UInt", modules: ["Swift"], type: "integer", keywords: ["minimum": .integer(0)]),
        Scalar(name: "UInt64", modules: ["Swift"], type: "integer", keywords: ["minimum": .integer(0)]),
        Scalar(name: "UInt32", modules: ["Swift"], type: "integer", keywords: bounds(0, Int64(UInt32.max))),
        Scalar(name: "UInt16", modules: ["Swift"], type: "integer", keywords: bounds(0, Int64(UInt16.max))),
        Scalar(name: "UInt8", modules: ["Swift"], type: "integer", keywords: bounds(0, Int64(UInt8.max))),
        Scalar(name: "Date", modules: ["Foundation", "FoundationEssentials"], type: "string", keywords: ["format": .string("date-time")]),
        Scalar(name: "UUID", modules: ["Foundation", "FoundationEssentials"], type: "string", keywords: ["format": .string("uuid")]),
    ]

    private static func bounds(_ minimum: Int64, _ maximum: Int64) -> [String: JSON] {
        ["minimum": .integer(minimum), "maximum": .integer(maximum)]
    }
}

extension JSON {
    /// A `type` keyword's value: `name`, or `[name, "null"]` when `null` is allowed too.
    fileprivate static func type(_ name: String, isNullable: Bool) -> JSON {
        isNullable ? .array([.string(name), .string("null")]) : .string(name)
    }
}

extension UInt8 {
    /// ASCII letters, digits, `_` and `-`, which a file name and a URI keep as they are.
    fileprivate var isUnreserved: Bool {
        (0x30...0x39).contains(self) || (0x41...0x5A).contains(self) || (0x61...0x7A).contains(self) || self == 0x5F || self == 0x2D
    }
}
