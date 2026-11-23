public import Foundation

extension TrackingPlan {
    /// Compares the plan with `committed`, the files of a plan exported before, and reports every
    /// difference.
    ///
    /// The files are compared by what they mean, not by their bytes: each event the committed index
    /// lists is matched with this plan's event of the same name and version, and their properties,
    /// requiredness, types, sensitivity and consent categories compared. Only when that finds no
    /// difference are the bytes compared, each file that differs, is missing or is no longer part of
    /// the plan reported as ``TrackingPlanDifference/fileOutOfDate(path:)``, so a match means the
    /// committed plan is exactly what ``files`` holds. Files of `committed` that a plan doesn't
    /// write, any but `tracking-plan.json`, `.schema.json` and `.example.json` files, are ignored.
    ///
    /// - Parameter committed: The committed plan's files, by their paths in its directory.
    /// - Returns: The check, whose ``TrackingPlanCheck/description`` is its report.
    /// - Complexity: O(*n* log *n*) in the size of the two plans.
    public func check(against committed: [File]) -> TrackingPlanCheck {
        let committedFiles = Dictionary(committed.filter { TrackingPlan.isPlanFile($0.path) }.map { ($0.path, $0.contents) }) { first, _ in first }
        let differences = semanticDifferences(from: committedFiles)
        guard differences.isEmpty else { return TrackingPlanCheck(differences: differences) }
        let currentFiles = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0.contents) })
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
        let fileManager = FileManager.default
        let paths = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        let committed = paths.filter(TrackingPlan.isPlanFile).compactMap { path in
            fileManager.contents(atPath: directory.appendingPathComponent(path).path).map { File(path: path, contents: Array($0)) }
        }
        return check(against: committed)
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
        // The current plan's documents always have the shape EventContract reads: it is the shape
        // EventSchema.document writes, so the force unwrap can't fail, and a failure would be a bug
        // in this module that no caller could handle.
        let currentEvents = schemas.map { EventContract(document: $0.document)! }
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
}

/// What a committed plan promises about one event: what a payload of it must and may hold.
private struct EventContract {
    let name: String
    let version: Int
    let consentCategory: String
    let properties: [String: PropertyContract]

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
    /// properties by the UTF-8 bytes of their names.
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
                if !before.isRequired && after.isRequired {
                    differences.append(.propertyMadeRequired(event: name, version: version, property: property))
                }
                if before.isRequired && !after.isRequired {
                    differences.append(.propertyMadeOptional(event: name, version: version, property: property))
                }
                if before.isSensitive != after.isSensitive {
                    differences.append(.sensitivityChanged(event: name, version: version, property: property, isSensitive: after.isSensitive))
                }
            case (.some, nil):
                differences.append(.propertyRemoved(event: name, version: version, property: property))
            case (nil, let after?):
                differences.append(after.isRequired
                    ? .requiredPropertyAdded(event: name, version: version, property: property)
                    : .optionalPropertyAdded(event: name, version: version, property: property))
            case (nil, nil):
                break
            }
        }
        return differences
    }
}

/// What a committed plan promises about one property.
private struct PropertyContract {
    /// Whether every payload holds the property.
    let isRequired: Bool
    /// Whether it is marked `x-traffluent-sensitive`.
    let isSensitive: Bool
    /// Its schema, without the sensitivity marker, its constraint keywords and the `null` its
    /// `type` allows when it is optional, which is how optionality reads in a document: so a change
    /// to optionality or to a bound alone is one difference, not a retyping too.
    let type: JSON
    /// Its constraint keywords.
    let constraints: ConstraintContract

    init(schema: [String: JSON], isRequired: Bool) {
        self.isRequired = isRequired
        isSensitive = schema["x-traffluent-sensitive"] == .boolean(true)
        constraints = ConstraintContract(schema: schema)
        var type = schema
        type["x-traffluent-sensitive"] = nil
        for keyword in ConstraintContract.keywords {
            type[keyword] = nil
        }
        if !isRequired, case .array(let names) = type["type"] {
            let named = names.filter { $0 != .string("null") }
            type["type"] = named.count == 1 ? named[0] : .array(named)
        }
        self.type = .object(type)
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
        JSON.number(exactly: bound).compact
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
