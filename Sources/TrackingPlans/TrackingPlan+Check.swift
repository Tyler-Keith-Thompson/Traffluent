import Events
public import Foundation

extension TrackingPlan {
    /// Compares the plan with `committed`, the files of a plan exported before, and reports every
    /// difference.
    ///
    /// The files are compared by what they mean, not by their bytes: each event the committed index
    /// lists is matched with this plan's event of the same name and version, and their properties,
    /// optionality, default values, types, sensitivity and consent categories compared. A property
    /// the committed document marks `deprecated` is one the event no longer declares: its absence
    /// is no difference, and declaring it again is compared with the schema it had. Only when that
    /// finds no difference are the bytes compared, each file that differs, is missing or is no
    /// longer part of the plan reported as ``TrackingPlanDifference/fileOutOfDate(path:)``, so a
    /// match means the committed plan is exactly what ``files(carryingForward:)`` of it holds. Files of `committed` that a plan doesn't
    /// write, any but `tracking-plan.json`, `.schema.json` and `.example.json` files, are ignored.
    ///
    /// - Parameter committed: The committed plan's files, by their paths in its directory.
    /// - Returns: The check, whose ``TrackingPlanCheck/description`` is its report.
    /// - Complexity: O(*n* log *n*) in the size of the two plans.
    public func check(against committed: [File]) -> TrackingPlanCheck {
        let committedFiles = Dictionary(committed.filter { TrackingPlan.isPlanFile($0.path) }.map { ($0.path, $0.contents) }) { first, _ in first }
        let differences = semanticDifferences(from: committedFiles)
        guard differences.isEmpty else { return TrackingPlanCheck(differences: differences) }
        // Unique: a plan's initializer rejects two schemas that share a file.
        let currentFiles = Dictionary(files(carryingForward: committed).map { ($0.path, $0.contents) }) { first, _ in first }
        let outOfDate = Set(committedFiles.keys).union(currentFiles.keys)
            .filter { committedFiles[$0] != currentFiles[$0] }
            .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            .map(TrackingPlanDifference.fileOutOfDate)
        return TrackingPlanCheck(differences: outOfDate)
    }

    /// Compares the plan with the one committed in `directory`, as ``check(against:)`` does with
    /// the directory's files.
    ///
    /// A directory that doesn't exist or can't be read holds no plan, which the check reports as
    /// ``TrackingPlanDifference/unreadableFile(path:)`` of `tracking-plan.json`.
    ///
    /// - Parameter directory: The directory the committed plan was exported to.
    /// - Returns: The check, whose ``TrackingPlanCheck/description`` is its report.
    public func check(againstDirectory directory: URL) -> TrackingPlanCheck {
        check(against: TrackingPlan.planFiles(in: directory))
    }

    private func semanticDifferences(from committedFiles: [String: [UInt8]]) -> [TrackingPlanDifference] {
        guard let entries = committedFiles[TrackingPlan.indexFileName].flatMap(JSON.init(parsing:)).flatMap(\.indexedDocuments) else {
            return [.unreadableFile(path: TrackingPlan.indexFileName)]
        }
        var differences: [TrackingPlanDifference] = []
        var committedEvents: [EventContract] = []
        for path in entries {
            guard let event = committedFiles[path].flatMap(JSON.init(parsing:)).flatMap(EventContract.init(document:)) else {
                differences.append(.unreadableFile(path: path))
                continue
            }
            committedEvents.append(event)
        }
        let currentEvents = schemas.map(EventContract.init(schema:))
        return differences + EventContract.differences(from: committedEvents, to: currentEvents)
    }
}

extension JSON {
    /// The document file names an index lists, in its order, or `nil` when the value isn't an
    /// index.
    fileprivate var indexedDocuments: [String]? {
        guard let events = object?["events"]?.array else { return nil }
        let paths = events.compactMap { $0.object?["schema"]?.string }
        return paths.count == events.count ? paths : nil
    }

    /// A `type` keyword's value without the `null` it lists: the one name left, or an array of
    /// the names left.
    fileprivate var withoutNull: JSON {
        guard case .array(let names) = self else { return self }
        let named = names.filter { $0 != .string("null") }
        return named.count == 1 ? named[0] : .array(named)
    }
}

/// What a committed plan promises about one event: what a payload of it must and may hold.
private struct EventContract {
    let name: String
    let version: Int
    let consentCategory: String
    let properties: [String: PropertyContract]

    /// The contract of the event `schema` describes: the one its document states, read from the
    /// schema rather than the JSON.
    init(schema: EventSchema) {
        name = schema.name
        version = schema.version
        consentCategory = schema.consentCategory.name
        // Unique: a plan's initializer rejects a schema with two properties of one name.
        properties = Dictionary(schema.properties.map { property in
            (property.name, PropertyContract(schema: property.schema, isRequired: property.isRequired))
        }) { first, _ in first }
    }

    /// The contract of the event `document` describes, or `nil` when it isn't a document of the
    /// shape a plan writes.
    init?(document: JSON) {
        guard let members = document.object,
            let name = members["title"]?.string,
            let version = members["x-traffluent-version"]?.integer.flatMap({ Int(exactly: $0) }),
            let consentCategory = members["x-traffluent-consent-category"]?.string,
            let schemas = members["properties"]?.object,
            let requiredNames = members["required"]?.array
        else { return nil }
        let required = Set(requiredNames.compactMap(\.string))
        guard required.count == requiredNames.count else { return nil }
        var properties: [String: PropertyContract] = [:]
        for (property, schema) in schemas {
            guard let schema = schema.object else { return nil }
            properties[property] = PropertyContract(schema: schema, isRequired: required.contains(property))
        }
        self.name = name
        self.version = version
        self.consentCategory = consentCategory
        self.properties = properties
    }

    /// Every difference between the committed events and the current ones: for each committed
    /// event, in order, whether it is gone, superseded by a later version or changed, then each
    /// current event the committed plan lacks.
    static func differences(from committed: [EventContract], to current: [EventContract]) -> [TrackingPlanDifference] {
        let currentByKey = Dictionary(current.map { ($0.key, $0) }) { first, _ in first }
        let committedKeys = Set(committed.map(\.key))
        var differences: [TrackingPlanDifference] = []
        var superseding = Set<Key>()
        for event in committed {
            let laterVersions = current.filter { $0.name == event.name && $0.version > event.version }.map(\.version)
            if let now = currentByKey[event.key] {
                differences += event.differences(to: now)
            } else if let later = laterVersions.min() {
                differences.append(.versionRaised(event: event.name, committed: event.version, current: later))
                superseding.insert(Key(name: event.name, version: later))
            } else {
                differences.append(.eventRemoved(event: event.name, version: event.version))
            }
        }
        for event in current where !committedKeys.contains(event.key) && !superseding.contains(event.key) {
            differences.append(.eventAdded(event: event.name, version: event.version))
        }
        return differences
    }

    struct Key: Hashable {
        let name: String
        let version: Int
    }

    var key: Key {
        Key(name: name, version: version)
    }

    /// How `current`, the same event at the same version, differs: its consent category, then its
    /// properties by the UTF-8 bytes of their names. A default value gained or lost is compared
    /// only for a property that isn't optional on either side: an optional one reads as `nil`
    /// without it. A deprecated property is one no longer declared: missing from `current`, it is
    /// no difference; declared again, it is compared with the schema it had, and is added as
    /// required when it is now, as the records and payloads since its removal lack it.
    private func differences(to current: EventContract) -> [TrackingPlanDifference] {
        var differences: [TrackingPlanDifference] = []
        if consentCategory != current.consentCategory {
            differences.append(.consentCategoryChanged(event: name, version: version, committed: consentCategory, current: current.consentCategory))
        }
        let names = Set(properties.keys).union(current.properties.keys).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        for property in names {
            switch (properties[property], current.properties[property]) {
            case (let before?, let after?):
                if before.type != after.type {
                    differences.append(.propertyRetyped(event: name, version: version, property: property, committed: before.type.compact, current: after.type.compact))
                } else {
                    // Only for the same type: a retyping says it all, and another type's bounds
                    // mean something else.
                    differences += before.constraints.differences(to: after.constraints).map { change in
                        change.isTightened
                            ? .constraintTightened(event: name, version: version, property: property, keyword: change.keyword, committed: change.committed, current: change.current)
                            : .constraintLoosened(event: name, version: version, property: property, keyword: change.keyword, committed: change.committed, current: change.current)
                    }
                }
                if !before.isNullable && !after.isNullable && before.hasDefaultValue != after.hasDefaultValue {
                    differences.append(after.hasDefaultValue
                        ? .defaultValueAdded(event: name, version: version, property: property)
                        : .defaultValueRemoved(event: name, version: version, property: property))
                }
                if before.isNullable && !after.isNullable {
                    differences.append(.propertyMadeRequired(event: name, version: version, property: property))
                }
                if !before.isNullable && after.isNullable {
                    differences.append(.propertyMadeOptional(event: name, version: version, property: property))
                }
                // The other changes to optionality and defaults already cover a deprecated property
                // that was optional or defaulted.
                if before.isDeprecated && before.isRequiredWhenDeclared && after.isRequiredWhenDeclared {
                    differences.append(.requiredPropertyAdded(event: name, version: version, property: property))
                }
                // A document leaves a Sensitive property out of `required`, as a destination may
                // redact it. Making a property Sensitive only drops it from `required`, which every
                // earlier payload still meets, so it is compatible. Making one not Sensitive puts it
                // back when it is neither optional nor defaulted, and the payloads that redacted it
                // lack it: breaking, unless a change to optionality or a default above already says
                // so, or it was deprecated, which a required property added does.
                if before.isSensitive && !after.isSensitive && before.isRequiredWhenDeclared && after.isRequiredWhenDeclared && !before.isDeprecated {
                    differences.append(.sensitivePropertyMadeRequired(event: name, version: version, property: property))
                } else if before.isSensitive != after.isSensitive {
                    differences.append(.sensitivityChanged(event: name, version: version, property: property, isSensitive: after.isSensitive))
                }
            case (let before?, nil):
                if !before.isDeprecated {
                    differences.append(.propertyRemoved(event: name, version: version, property: property))
                }
            case (nil, let after?):
                differences.append(
                    after.isNullable ? .optionalPropertyAdded(event: name, version: version, property: property)
                        : after.hasDefaultValue ? .defaultedPropertyAdded(event: name, version: version, property: property)
                        : .requiredPropertyAdded(event: name, version: version, property: property)
                )
            case (nil, nil):
                break
            }
        }
        return differences
    }
}

/// What a committed plan promises about one property.
private struct PropertyContract {
    /// Whether every payload holds the property: it is in the document's `required`.
    let isRequired: Bool
    /// Whether its value may be `null`: its `type` allows `null`, or, for a type the plan can't
    /// map, which has no `type`, it is neither required nor defaulted, as only an optional
    /// property is.
    let isNullable: Bool
    /// Whether it is marked `deprecated`: the event declared it at this version and no longer
    /// does.
    let isDeprecated: Bool
    /// Whether it is marked `x-traffluent-sensitive`.
    let isSensitive: Bool
    /// Whether it is marked `x-traffluent-default`: a stored payload without it reads its default
    /// value.
    let hasDefaultValue: Bool
    /// Its schema, without the sensitivity, default and deprecation markers, its constraint
    /// keywords and the `null` its `type` allows when it is optional, which is how optionality
    /// reads in a document: so a change to optionality, to a default or to a bound alone is one
    /// difference, not a retyping too.
    let type: JSON
    /// Its constraint keywords.
    let constraints: ConstraintContract

    /// Whether a payload must hold it while the event declares it: it is neither nullable nor
    /// defaulted. A deprecated property's document leaves it out of `required` all the same.
    var isRequiredWhenDeclared: Bool {
        !isNullable && !hasDefaultValue
    }

    init(schema: [String: JSON], isRequired: Bool) {
        self.isRequired = isRequired
        isSensitive = schema["x-traffluent-sensitive"] == .boolean(true)
        hasDefaultValue = schema["x-traffluent-default"] == .boolean(true)
        isDeprecated = schema["deprecated"] == .boolean(true)
        constraints = ConstraintContract(schema: schema)
        // A type the plan can't map has no `type` to hold `null`; it is nullable when it is
        // optional, which is all that leaves it out of `required` without a default, but for
        // `Sensitive`. So `Money?` and `Money` with a default read alike, and so do
        // `Sensitive<Money>?` and `Sensitive<Money>`: their payloads are, as such a schema allows
        // any value and a redacting destination leaves it out, but a stored null wouldn't decode
        // as the second. Reading a Sensitive one as nullable keeps a sensitivity change classed
        // right: `Sensitive<Money>` made `Money` is made required, and `Money?` made
        // `Sensitive<Money>?` changes sensitivity alone.
        let allowsNull = schema["type"].map { $0 == .string("null") || ($0.array ?? []).contains(.string("null")) }
        isNullable = allowsNull ?? (!isRequired && !hasDefaultValue)
        var type = schema
        type["x-traffluent-sensitive"] = nil
        type["x-traffluent-default"] = nil
        type["deprecated"] = nil
        for keyword in ConstraintContract.keywords {
            type[keyword] = nil
        }
        type["type"] = type["type"]?.withoutNull
        if let items = type["items"]?.object {
            type["items"] = .object(Self.withoutRedactedNull(items))
        }
        self.type = .object(type)
    }

    /// An array's `items` schema without the `null` a `Sensitive` element allows, there for the
    /// element a destination redacts: a plan exported by a release that didn't allow it then
    /// compares as the same type. `[Sensitive<T>?]` and `[Sensitive<T>]` already read alike.
    private static func withoutRedactedNull(_ items: [String: JSON]) -> [String: JSON] {
        var items = items
        if items["x-traffluent-sensitive"] == .boolean(true) {
            items["type"] = items["type"]?.withoutNull
        }
        if let nested = items["items"]?.object {
            items["items"] = .object(withoutRedactedNull(nested))
        }
        return items
    }
}

/// What a committed plan promises about one property's constraint keywords: its bounds and its
/// patterns.
private struct ConstraintContract {
    /// The keywords a constraint writes, which ``PropertyContract/type`` leaves out: the bounds,
    /// the patterns (the first as `pattern`, any other under `allOf`) and the first pattern's
    /// `examples`, an annotation that constrains nothing.
    static let keywords = ["minLength", "maxLength", "minimum", "maximum", "minItems", "maxItems", "pattern", "allOf", "examples"]

    /// A bound, by its keyword's name, and whether it is a lower one.
    private static let bounds: [(keyword: String, isLower: Bool)] = [
        ("minLength", true), ("maxLength", false), ("minimum", true), ("maximum", false), ("minItems", true), ("maxItems", false),
    ]

    let values: [String: Double]
    let patterns: [String]

    init(schema: [String: JSON]) {
        var values: [String: Double] = [:]
        for (keyword, _) in Self.bounds {
            values[keyword] = schema[keyword]?.double
        }
        self.values = values
        let extra = (schema["allOf"]?.array ?? []).compactMap { $0.object?["pattern"]?.string }
        patterns = (schema["pattern"]?.string.map { [$0] } ?? []) + extra
    }

    /// One keyword's change: tightened when a payload the committed bound accepts may be one the
    /// current rejects.
    struct Change {
        let keyword: String
        let committed: String?
        let current: String?
        let isTightened: Bool
    }

    /// Each bound that moved, in the order of ``bounds``, then the patterns, when any was added or
    /// removed.
    ///
    /// A lower bound that rose, an upper one that fell, or one added is tightened; the reverse is
    /// loosened. A pattern added is tightened, as one regular expression can't be shown to accept
    /// all another does; a pattern only removed is loosened.
    func differences(to current: ConstraintContract) -> [Change] {
        var changes: [Change] = []
        for (keyword, isLower) in Self.bounds {
            let before = values[keyword]
            let after = current.values[keyword]
            guard before != after else { continue }
            let isTightened = switch (before, after) {
            case (nil, _): true
            case (_, nil): false
            case (let before?, let after?): isLower ? after > before : after < before
            }
            changes.append(Change(keyword: keyword, committed: before.map(Self.text), current: after.map(Self.text), isTightened: isTightened))
        }
        let added = current.patterns.filter { !patterns.contains($0) }
        let removed = patterns.filter { !current.patterns.contains($0) }
        if !added.isEmpty || !removed.isEmpty {
            changes.append(Change(keyword: "pattern", committed: Self.text(patterns), current: Self.text(current.patterns), isTightened: !added.isEmpty))
        }
        return changes
    }

    private static func text(_ bound: Double) -> String {
        JSON.number(exactly: bound)?.compact ?? String(bound)
    }

    /// The patterns as JSON, one string, or an array of several; `nil` for none.
    private static func text(_ patterns: [String]) -> String? {
        switch patterns.count {
        case 0: nil
        case 1: JSON.string(patterns[0]).compact
        default: JSON.array(patterns.map(JSON.string)).compact
        }
    }
}
