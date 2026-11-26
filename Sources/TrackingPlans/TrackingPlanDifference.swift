/// One way the plan an app's events make now differs from the plan committed before them, as
/// ``TrackingPlan/check(against:)`` reports it.
///
/// An event is named by its name and version, `checkout_started v2`. A difference is breaking
/// (``isBreaking``) when, at the same version, a record a store still holds or a payload an
/// already-released app sends may stop decoding or validating against the current event. A
/// breaking change needs a new version (`Event.schemaVersion`, `@Event(version:)`), and a store
/// then drops the records stored at the earlier one, reporting both versions. Every other
/// difference keeps them decoding and validating: keep the version, and the committed plan is only
/// out of date.
///
/// | Difference | Breaking |
/// |---|---|
/// | ``eventRemoved(event:version:)``, which is also how a rename shows | yes |
/// | ``propertyRetyped(event:version:property:committed:current:)`` | yes |
/// | ``propertyMadeRequired(event:version:property:)`` | yes |
/// | ``sensitivePropertyMadeRequired(event:version:property:)`` | yes |
/// | ``requiredPropertyAdded(event:version:property:)`` | yes |
/// | ``defaultValueRemoved(event:version:property:)`` | yes |
/// | ``constraintTightened(event:version:property:keyword:committed:current:)`` | yes |
/// | ``unreadableFile(path:)`` | yes |
/// | ``eventAdded(event:version:)`` | no |
/// | ``versionRaised(event:committed:current:)`` | no |
/// | ``optionalPropertyAdded(event:version:property:)`` | no |
/// | ``defaultedPropertyAdded(event:version:property:)`` | no |
/// | ``propertyRemoved(event:version:property:)`` | no |
/// | ``propertyMadeOptional(event:version:property:)`` | no |
/// | ``defaultValueAdded(event:version:property:)`` | no |
/// | ``consentCategoryChanged(event:version:committed:current:)`` | no |
/// | ``sensitivityChanged(event:version:property:isSensitive:)`` | no |
/// | ``constraintLoosened(event:version:property:keyword:committed:current:)`` | no |
/// | ``fileOutOfDate(path:)`` | no |
///
/// A removed property is compatible: a stored record that still holds it decodes with the entry
/// skipped, and the event's document keeps it, marked `deprecated` and not required, so a payload
/// that holds it still validates. Declaring it again is compared with the schema it had: another
/// type is ``propertyRetyped(event:version:property:committed:current:)``, and the same one is
/// compatible unless it is now required, as ``requiredPropertyAdded(event:version:property:)``,
/// since the records and payloads written while it was gone lack it.
///
/// A `Sensitive` property is never required, as any destination may redact it. Making a property
/// `Sensitive` is compatible: the payloads that hold it still validate. Making one that is neither
/// optional nor defaulted stop being `Sensitive` makes it required, as
/// ``sensitivePropertyMadeRequired(event:version:property:)``, since the payloads a redacting
/// destination sent lack it.
///
/// Raising an event's version is how its author marks a breaking change: the plan then holds a
/// new document, and the committed version's properties aren't compared with the new one's.
public enum TrackingPlanDifference: Sendable, Hashable, CustomStringConvertible {
    /// The committed plan has `event` at `version`, and no event of that name has that version or
    /// a later one now: it was removed or renamed, or its version was lowered.
    case eventRemoved(event: String, version: Int)
    /// A property of the committed event is gone; a stored payload that holds it reads with it
    /// skipped, and the event's document keeps it, marked `deprecated`.
    case propertyRemoved(event: String, version: Int, property: String)
    /// A property's schema changed, given by its JSON Schema keywords on one line, without the
    /// `null` an optional property allows.
    case propertyRetyped(event: String, version: Int, property: String, committed: String, current: String)
    /// An optional property, whose value the committed plan lets be `null`, isn't optional now, so
    /// a stored `null` can't be read.
    case propertyMadeRequired(event: String, version: Int, property: String)
    /// A property that is neither optional nor has a default value, which the committed plan
    /// marks `Sensitive` and so doesn't require, isn't `Sensitive` now, so a payload a redacting
    /// destination sent without it doesn't validate.
    case sensitivePropertyMadeRequired(event: String, version: Int, property: String)
    /// The event has a property that is neither optional nor has a default value, and that the
    /// committed plan doesn't have, or marks `deprecated`: the payloads and records written without
    /// it can't be read.
    case requiredPropertyAdded(event: String, version: Int, property: String)
    /// A property that isn't optional, which the committed plan gives a default value, has none
    /// now, so a stored payload written before the property was added can't be read.
    case defaultValueRemoved(event: String, version: Int, property: String)
    /// A property's constraint keyword is tighter: a lower bound (`minLength`, `minimum`,
    /// `minItems`) rose, an upper one (`maxLength`, `maximum`, `maxItems`) fell, or one was added,
    /// or a `pattern` was added or changed. `committed` and `current` are its values as JSON, `nil`
    /// where there is none; a property's patterns are one string, or an array of several.
    case constraintTightened(event: String, version: Int, property: String, keyword: String, committed: String?, current: String?)
    /// A file of the committed plan is missing, or isn't JSON of the shape a plan writes, so the
    /// events can't be compared with it: the index, `tracking-plan.json`, when there is no
    /// committed plan at all.
    case unreadableFile(path: String)
    /// The event is new.
    case eventAdded(event: String, version: Int)
    /// The event's version is raised from `committed` to `current`.
    case versionRaised(event: String, committed: Int, current: Int)
    /// The event has an optional property the committed plan doesn't.
    case optionalPropertyAdded(event: String, version: Int, property: String)
    /// The event has a property with a default value, not optional, that the committed plan
    /// doesn't, which a stored payload without it reads.
    case defaultedPropertyAdded(event: String, version: Int, property: String)
    /// A property that isn't optional, which the committed plan gives no default value, has one
    /// now.
    case defaultValueAdded(event: String, version: Int, property: String)
    /// A property whose value the committed plan doesn't let be `null` is optional now.
    case propertyMadeOptional(event: String, version: Int, property: String)
    /// The event's consent category changed, from the committed name to the current one.
    case consentCategoryChanged(event: String, version: Int, committed: String, current: String)
    /// A property became `Sensitive`, or stopped being, as `isSensitive` says, and payloads that
    /// left it out still validate: it became `Sensitive`, or it is optional or has a default
    /// value.
    case sensitivityChanged(event: String, version: Int, property: String, isSensitive: Bool)
    /// A property's constraint keyword is looser: a lower bound fell, an upper one rose, or one
    /// was removed, or a `pattern` was only removed. The values are as for
    /// ``constraintTightened(event:version:property:keyword:committed:current:)``.
    case constraintLoosened(event: String, version: Int, property: String, keyword: String, committed: String?, current: String?)
    /// A file of the committed plan isn't the bytes exporting the plan writes now, though its
    /// events are the same: written by hand or by another release, or missing, or no longer part
    /// of the plan.
    case fileOutOfDate(path: String)

    /// Whether a payload the committed plan accepts may be one the current plan rejects; the
    /// table in ``TrackingPlanDifference`` lists which differences are.
    public var isBreaking: Bool {
        switch self {
        case .eventRemoved, .propertyRetyped, .propertyMadeRequired, .sensitivePropertyMadeRequired, .requiredPropertyAdded, .defaultValueRemoved,
            .constraintTightened, .unreadableFile:
            true
        case .eventAdded, .versionRaised, .optionalPropertyAdded, .defaultedPropertyAdded, .propertyRemoved, .propertyMadeOptional,
            .defaultValueAdded, .consentCategoryChanged, .sensitivityChanged, .constraintLoosened, .fileOutOfDate:
            false
        }
    }

    /// The difference as one line, naming the event and property.
    public var description: String {
        switch self {
        case .eventRemoved(let event, let version):
            "\(event) v\(version) is in the committed plan, but no event named \(event) has version \(version) or later: it was renamed or removed"
        case .propertyRemoved(let event, let version, let property):
            "\(event) v\(version): property \"\(property)\" was removed"
        case .propertyRetyped(let event, let version, let property, let committed, let current):
            "\(event) v\(version): property \"\(property)\" changed type from \(committed) to \(current)"
        case .propertyMadeRequired(let event, let version, let property):
            "\(event) v\(version): property \"\(property)\" was optional and is now required"
        case .sensitivePropertyMadeRequired(let event, let version, let property):
            "\(event) v\(version): property \"\(property)\" is no longer sensitive and is now required"
        case .requiredPropertyAdded(let event, let version, let property):
            "\(event) v\(version): required property \"\(property)\" was added without a default value"
        case .defaultValueRemoved(let event, let version, let property):
            "\(event) v\(version): property \"\(property)\" lost its default value"
        case .unreadableFile(let path):
            "\(path) is missing from the committed plan, or isn't a tracking plan file"
        case .eventAdded(let event, let version):
            "\(event) v\(version) is new"
        case .versionRaised(let event, let committed, let current):
            "\(event) went from version \(committed) to \(current)"
        case .optionalPropertyAdded(let event, let version, let property):
            "\(event) v\(version): optional property \"\(property)\" was added"
        case .defaultedPropertyAdded(let event, let version, let property):
            "\(event) v\(version): property \"\(property)\" was added with a default value"
        case .defaultValueAdded(let event, let version, let property):
            "\(event) v\(version): property \"\(property)\" gained a default value"
        case .propertyMadeOptional(let event, let version, let property):
            "\(event) v\(version): property \"\(property)\" was required and is now optional"
        case .consentCategoryChanged(let event, let version, let committed, let current):
            "\(event) v\(version): consent category changed from \(committed) to \(current)"
        case .sensitivityChanged(let event, let version, let property, let isSensitive):
            "\(event) v\(version): property \"\(property)\" \(isSensitive ? "is now" : "is no longer") sensitive"
        case .constraintTightened(let event, let version, let property, let keyword, let committed, let current):
            "\(event) v\(version): property \"\(property)\" \(TrackingPlanDifference.change(keyword, committed, current)), which is tighter"
        case .constraintLoosened(let event, let version, let property, let keyword, let committed, let current):
            "\(event) v\(version): property \"\(property)\" \(TrackingPlanDifference.change(keyword, committed, current)), which is looser"
        case .fileOutOfDate(let path):
            "\(path) isn't what exporting the plan writes now"
        }
    }

    /// How a keyword changed, in words: gained, lost or changed from one value to another.
    private static func change(_ keyword: String, _ committed: String?, _ current: String?) -> String {
        switch (committed, current) {
        case (nil, let current?): "gained \(keyword) \(current)"
        case (let committed?, nil): "lost \(keyword) \(committed)"
        default: "changed \(keyword) from \(committed ?? "") to \(current ?? "")"
        }
    }
}
