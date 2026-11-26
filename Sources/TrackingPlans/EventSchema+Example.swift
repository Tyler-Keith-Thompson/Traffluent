import Events

extension EventSchema {
    /// The event's example: a payload its document accepts, with every property present, each set
    /// to the example of its schema.
    var example: JSON {
        // Unique: TrackingPlan's initializer rejects a schema with two properties of one name.
        .object(Dictionary(properties.map { property in
            (property.name, property.schema.example)
        }) { first, _ in first })
    }
}

extension Dictionary where Key == String, Value == JSON {
    /// The fixed value a property of this schema takes in an example: for a string, its pattern's
    /// example, or else `"example"`, cut to its `maxLength`, or `x` repeated to a `minLength` above
    /// 7, or the reference date or the nil UUID for one of format `date-time` or `uuid`; for a
    /// number or an
    /// integer, 0, or the nearest value its `minimum` and `maximum` allow; `false` for a boolean;
    /// for an array, one example of its `items`, or as many as its `minItems` and `maxItems` allow;
    /// and `null` for a type the plan can't map, which accepts any value.
    ///
    /// Read from the schema rather than the Swift type, so a value matches the keywords the
    /// document holds.
    fileprivate var example: JSON {
        switch typeName {
        case "string":
            switch self["format"] {
            case .string("date-time"): .string("2001-01-01T00:00:00Z")
            case .string("uuid"): .string("00000000-0000-0000-0000-000000000000")
            default: self["examples"]?.array?.first ?? .string(textExample)
            }
        case "integer":
            // Every integer type a plan maps has 0 in its range; a bound with a fraction is met by
            // the whole number on its inner side.
            .number(exactly: (self["minimum"]?.double.map { Swift.max(0, $0.rounded(.up)) } ?? 0).clamped(below: self["maximum"]?.double.map { $0.rounded(.down) })) ?? .null
        case "number":
            .number(exactly: (self["minimum"]?.double.map { Swift.max(0, $0) } ?? 0).clamped(below: self["maximum"]?.double)) ?? .null
        case "boolean":
            .boolean(false)
        case "array":
            .array(Array(repeating: self["items"]?.object?.example ?? .null, count: itemCount))
        default:
            .null
        }
    }

    /// `"example"`, cut to `maxLength` scalars, or `x` repeated to a `minLength` above its 7.
    private var textExample: String {
        var text = "example"
        if let minimum = self["minLength"]?.integer, minimum > 7 {
            text = String(repeating: "x", count: Int(minimum))
        }
        if let maximum = self["maxLength"]?.integer, maximum < Int64(text.unicodeScalars.count) {
            text = String(text.unicodeScalars.prefix(Int(maximum)))
        }
        return text
    }

    /// One, or as many as `minItems` asks for, but no more than `maxItems` allows.
    private var itemCount: Int {
        let minimum = self["minItems"]?.integer.map { Int($0) } ?? 1
        let count = Swift.max(1, minimum)
        guard let maximum = self["maxItems"]?.integer else { return count }
        return Swift.min(count, Int(maximum))
    }

    /// The schema's `type`, the first that isn't `null` when it lists several.
    private var typeName: String? {
        switch self["type"] {
        case .string(let name): name
        case .array(let names): names.compactMap(\.string).first { $0 != "null" }
        default: nil
        }
    }
}

extension Double {
    /// The value, or `bound` when that is smaller: a value no larger than a schema's maximum.
    fileprivate func clamped(below bound: Double?) -> Double {
        bound.map { Swift.min(self, $0) } ?? self
    }
}
