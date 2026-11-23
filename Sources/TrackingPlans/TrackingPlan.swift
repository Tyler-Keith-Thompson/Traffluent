public import Events

/// The JSON Schema (draft 2020-12) of every event an app tracks: one document per event and an
/// index, exported from the events' ``/Events/EventSchema`` values.
///
/// ```swift
/// import EventMacros
/// import TrackingPlans
///
/// @Event(name: "checkout_started", version: 2)
/// struct CheckoutStarted {
///     var cartSize: Int
///     var coupon: String?
/// }
///
/// let plan = TrackingPlan(schemas: [CheckoutStarted.schema])
/// plan.files.map(\.path)
/// // ["tracking-plan.json", "checkout_started.v2.schema.json", "checkout_started.v2.example.json"]
/// ```
///
/// The plan's files are values, so the same schemas give the same bytes on every run and
/// platform: keys sorted by their UTF-8 bytes, two-space indentation, a trailing newline and no
/// timestamps.
///
/// Each event's document is named `<name>.v<version>.schema.json`, its name with every byte but
/// ASCII letters, digits, `_` and `-` percent-encoded (`Box<String>` is `Box%3CString%3E`). The
/// document describes the event's properties as a JSON object:
///
/// - `$schema` is draft 2020-12's, and `$id` the document's file name, so the index's references
///   to it resolve against the directory the plan is written to.
/// - `title` is the event's name, `type` is `object` and `additionalProperties` is `false`.
/// - `properties` holds each stored property's schema, and `required` the names of the properties
///   that aren't optional, in declaration order.
/// - `x-traffluent-version` is the event's version and `x-traffluent-consent-category` the name of
///   its consent category.
///
/// A property's schema follows its type as written: `String` is a `string`; `Bool` a `boolean`;
/// `Double` and `Float` a `number`; every integer type an `integer`, with `minimum` and `maximum`
/// for the types of 32 bits or fewer and a `minimum` of 0 for the unsigned ones; `Date` a `string`
/// of `format` `date-time` and `UUID` one of `format` `uuid`; an array (`[T]`, `Array<T>`) an
/// `array` whose `items` are `T`'s schema. An optional type (`T?`, `T!`, `Optional<T>`) adds `null`
/// to `T`'s `type`. `Sensitive<T>` is `T`'s schema with `x-traffluent-sensitive: true`. Each may be
/// qualified by its module (`Swift.Int`, `Foundation.Date`, `Events.Sensitive`). Any other type,
/// whose JSON shape the plan can't know, accepts any value and records the type in
/// `x-traffluent-swift-type`.
///
/// Beside each document is the event's example, `<name>.v<version>.example.json`: a conformance
/// vector, the payload of the event with every property present and set to a fixed value its
/// schema accepts. Another platform's code can encode the same event and compare. A `string` is
/// `"example"`, one of `format` `date-time` is `"2001-01-01T00:00:00Z"` and one of `format`
/// `uuid` the nil UUID; a `number` or an `integer` is 0; a `boolean` is `false`; an `array` holds
/// one example of its `items`; and a type the plan can't map is `null`.
///
/// The index, `tracking-plan.json`, lists every event under `events`, by name and then version,
/// with its `name`, `version`, `consentCategory`, `schema`, its document's file name, and
/// `example`, its example's.
///
/// ``check(againstDirectory:)`` compares a plan with the one committed in a directory, reporting
/// each ``TrackingPlanDifference``.
public struct TrackingPlan: Sendable, Hashable {
    /// The plan's event schemas, ordered by the UTF-8 bytes of their names and then by version.
    public let schemas: [EventSchema]

    /// The plan of the events `schemas` describe, in any order.
    ///
    /// - Parameter schemas: The schemas of the events the plan describes.
    /// - Precondition: No two schemas share a file, and every schema has a name and properties
    ///   with distinct names; ``init(checkedSchemas:)`` throws instead.
    public init(schemas: [EventSchema]) {
        do {
            try self.init(checkedSchemas: schemas)
        } catch {
            preconditionFailure("TrackingPlan(schemas:): \(error)")
        }
    }

    /// The plan of the events `schemas` describe, in any order, or an error naming the first rule
    /// they break.
    ///
    /// - Parameter schemas: The schemas of the events the plan describes.
    /// - Throws: ``TrackingPlanError/emptyEventName`` for a schema with an empty name,
    ///   ``TrackingPlanError/duplicateProperty`` for one that lists two properties of the same
    ///   name, and ``TrackingPlanError/duplicateEvent`` for two schemas whose files would have the
    ///   same name on a case-insensitive file system.
    public init(checkedSchemas schemas: [EventSchema]) throws(TrackingPlanError) {
        for schema in schemas {
            guard !schema.name.isEmpty else { throw .emptyEventName }
            guard schema.hasDistinctPropertyNames else { throw .duplicateProperty }
        }
        let sorted = schemas.sorted(by: EventSchema.precedesInPlan)
        // Neighbours after sorting by name are enough for exact duplicates, but names that differ
        // only in case needn't be neighbours, so every file name is compared case-folded.
        var fileNames = Set<String>()
        for schema in sorted {
            guard fileNames.insert(schema.fileName.lowercased()).inserted else { throw .duplicateEvent }
        }
        self.schemas = sorted
    }

    /// The plan's files: the index, `tracking-plan.json`, then each event's document and its
    /// example, in the order of ``schemas``.
    ///
    /// - Complexity: O(*n* log *n*) in the plan's properties, for sorting each object's keys.
    public var files: [File] {
        [File(path: TrackingPlan.indexFileName, json: index)] + schemas.flatMap { schema in
            [File(path: schema.fileName, json: schema.document), File(path: schema.exampleFileName, json: schema.example)]
        }
    }

    /// The name of the plan's index file.
    static let indexFileName = "tracking-plan.json"

    private var index: JSON {
        .object(["events": .array(schemas.map(\.indexEntry))])
    }
}

extension EventSchema {
    /// Orders schemas by their names' UTF-8 bytes, then by version: an order that doesn't depend on
    /// a locale or a platform's string comparison.
    fileprivate static func precedesInPlan(_ first: EventSchema, _ second: EventSchema) -> Bool {
        first.name == second.name ? first.version < second.version : first.name.utf8.lexicographicallyPrecedes(second.name.utf8)
    }

    fileprivate var hasDistinctPropertyNames: Bool {
        Set(properties.map(\.name)).count == properties.count
    }

    fileprivate var indexEntry: JSON {
        .object([
            "name": .string(name),
            "version": .integer(Int64(version)),
            "consentCategory": .string(consentCategory.name),
            "schema": .string(fileName),
            "example": .string(exampleFileName),
        ])
    }
}

extension TrackingPlan.File {
    fileprivate init(path: String, json: JSON) {
        self.init(path: path, contents: Array((json.rendered + "\n").utf8))
    }
}
