import Events

extension EventSchema {
    /// The event's example: a payload its document accepts, with every property present, each set
    /// to the example of its schema.
    var example: JSON {
        .object(Dictionary(uniqueKeysWithValues: properties.map { property in
            (property.name, property.schema.example)
        }))
    }
}

extension Dictionary where Key == String, Value == JSON {
    /// The fixed value a property of this schema takes in an example: `"example"` for a string, or
    /// the reference date or the nil UUID for one of format `date-time` or `uuid`; 0 for a number or an
    /// integer; `false` for a boolean; one element for an array; and `null` for a type the plan
    /// can't map, which accepts any value.
    ///
    /// Read from the schema rather than the Swift type, so a value matches the keywords the
    /// document holds.
    fileprivate var example: JSON {
        switch typeName {
        case "string":
            switch self["format"] {
            case .string("date-time"): .string("2001-01-01T00:00:00Z")
            case .string("uuid"): .string("00000000-0000-0000-0000-000000000000")
            default: .string("example")
            }
        case "integer", "number":
            // Every integer type a plan maps has 0 in its range.
            .integer(0)
        case "boolean":
            .boolean(false)
        case "array":
            .array([self["items"]?.object?.example ?? .null])
        default:
            .null
        }
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
