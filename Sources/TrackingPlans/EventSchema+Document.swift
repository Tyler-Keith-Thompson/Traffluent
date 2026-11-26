import Events

extension EventSchema {
    /// The event's document's file name: `<name>.v<version>.schema.json`, the name's bytes other
    /// than ASCII letters, digits, `_` and `-` percent-encoded, which keeps every name a valid file
    /// name and URI reference and two names' files apart.
    var fileName: String {
        "\(fileStem).schema.json"
    }

    /// The event's example's file name: `<name>.v<version>.example.json`, encoded as ``fileName``.
    var exampleFileName: String {
        "\(fileStem).example.json"
    }

    private var fileStem: String {
        var encoded = ""
        for byte in name.utf8 {
            if byte.isUnreserved {
                encoded.unicodeScalars.append(Unicode.Scalar(byte))
            } else {
                let hex = String(byte, radix: 16, uppercase: true)
                encoded += "%" + (hex.count == 1 ? "0" : "") + hex
            }
        }
        return "\(encoded).v\(version)"
    }

    /// The event's JSON Schema document, as ``TrackingPlan`` describes it, keeping each property
    /// `committed`, the document of this event and version exported before, has that the event no
    /// longer declares: with its schema there, marked `deprecated`.
    func document(keepingRemovedFrom committed: JSON?) -> JSON {
        // Unique: TrackingPlan's initializer rejects a schema with two properties of one name.
        let declared = Dictionary(properties.map { ($0.name, JSON.object($0.schema)) }) { first, _ in first }
        let committedProperties = committed?.object?["properties"]?.object ?? [:]
        let deprecated = committedProperties.compactMapValues { $0.object.map { JSON.object($0.merging(["deprecated": .boolean(true)]) { $1 }) } }
        return .object([
            "$schema": .string("https://json-schema.org/draft/2020-12/schema"),
            "$id": .string(fileName),
            "title": .string(name),
            "type": .string("object"),
            // A property declared again is the declaration's, not the deprecated one's.
            "properties": .object(declared.merging(deprecated, uniquingKeysWith: { current, _ in current })),
            "required": .array(properties.filter(\.isRequired).map { .string($0.name) }),
            "additionalProperties": .boolean(false),
            "x-traffluent-version": .integer(Int64(version)),
            "x-traffluent-consent-category": .string(consentCategory.name),
        ])
    }
}

extension EventSchema.Property {
    /// Whether every payload of the event holds the property, whichever release wrote it and
    /// whichever destination sent it: one that is neither optional nor has a default value, which
    /// a release before it was added leaves out, nor `Sensitive`, which a destination that redacts
    /// it leaves out.
    var isRequired: Bool {
        // Read from the schema's marker, as the plan's check reads it, so a document and the
        // check never disagree on what is sensitive.
        !isOptional && !hasDefaultValue && schema["x-traffluent-sensitive"] != .boolean(true)
    }

    /// The property's schema: its type's, with `null` allowed when it is optional, narrowed by its
    /// keywords, and marked `x-traffluent-default` when it has a default value.
    var schema: [String: JSON] {
        var schema = WrittenType(parsing: typeName)?.schema(isNullable: isOptional) ?? ["x-traffluent-swift-type": .string(typeName)]
        if hasDefaultValue {
            schema["x-traffluent-default"] = .boolean(true)
        }
        return schema.narrowed(by: keywords)
    }
}

extension Dictionary where Key == String, Value == JSON {
    /// The schema with `keywords` added, each bound merged with one the schema has already (an
    /// `Int8`'s, say) by keeping the tighter. The first pattern is `pattern`, with its example in
    /// `examples`; any other is a `pattern` of its own under `allOf`, as an object holds one
    /// `pattern`.
    fileprivate func narrowed(by keywords: [ValidationKeyword]) -> [String: JSON] {
        var schema = self
        var patterns: [String] = []
        for keyword in keywords {
            switch keyword {
            case .minLength(let length): schema.tighten("minLength", to: Double(length), keepingLarger: true)
            case .maxLength(let length): schema.tighten("maxLength", to: Double(length), keepingLarger: false)
            case .minimum(let bound): schema.tighten("minimum", to: bound, keepingLarger: true)
            case .maximum(let bound): schema.tighten("maximum", to: bound, keepingLarger: false)
            case .minItems(let count): schema.tighten("minItems", to: Double(count), keepingLarger: true)
            case .maxItems(let count): schema.tighten("maxItems", to: Double(count), keepingLarger: false)
            case .pattern(let pattern, let example):
                guard !patterns.contains(pattern) else { continue }
                if patterns.isEmpty {
                    schema["pattern"] = .string(pattern)
                    schema["examples"] = .array([.string(example)])
                } else {
                    schema["allOf"] = .array((schema["allOf"]?.array ?? []) + [.object(["pattern": .string(pattern)])])
                }
                patterns.append(pattern)
            }
        }
        return schema
    }

    /// Sets the bound `keyword` to `bound`, unless the schema has a tighter one: larger when
    /// `keepingLarger` is set (a lower bound), smaller otherwise.
    private mutating func tighten(_ keyword: String, to bound: Double, keepingLarger: Bool) {
        if let existing = self[keyword]?.double, keepingLarger ? existing >= bound : existing <= bound { return }
        // Always a number: a plan's initializer rejects a bound that isn't finite.
        guard let number = JSON.number(exactly: bound) else { return }
        self[keyword] = number
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
        // A refined value's JSON is its value's; its rule's keywords come from the property's.
        if let arguments = names("Refined", in: ["Events", "Traffluent"]), arguments.count == 2 {
            return arguments[0].schema(isNullable: isNullable)
        }
        if let arguments = names("Sensitive", in: ["Events", "Traffluent"]), arguments.count == 1 {
            return arguments[0].schema(isNullable: isNullable).merging(["x-traffluent-sensitive": .boolean(true)]) { $1 }
        }
        if let element = arrayElement {
            // A redacted element of an array is null, so a sensitive one allows it.
            return ["type": .type("array", isNullable: isNullable), "items": .object(element.schema(isNullable: element.isSensitive))]
        }
        for scalar in Scalar.all {
            if let arguments = names(scalar.name, in: scalar.modules), arguments.isEmpty {
                return scalar.keywords.merging(["type": .type(scalar.type, isNullable: isNullable)]) { $1 }
            }
        }
        // A type whose JSON shape the plan can't know: any value, null included, is allowed.
        return ["x-traffluent-swift-type": .string(source)]
    }

    /// Whether the type is `Sensitive<T>`, which a destination may redact.
    private var isSensitive: Bool {
        names("Sensitive", in: ["Events", "Traffluent"])?.count == 1
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
