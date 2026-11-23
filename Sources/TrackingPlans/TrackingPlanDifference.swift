/// One way the plan an app's events make now differs from the plan committed before them, as
/// ``TrackingPlan/check(against:)`` reports it.
///
/// An event is named by its name and version, `checkout_started v2`. A difference is breaking
/// (``isBreaking``) when a payload the committed plan accepts may be one the current plan rejects:
/// an app already released sends events of the committed shape, and whatever validates them
/// against the plan would start refusing them. Every other difference leaves those payloads valid
/// and only means the committed plan is out of date.
///
/// | Difference | Breaking |
/// |---|---|
/// | ``eventRemoved(event:version:)``, which is also how a rename shows | yes |
/// | ``propertyRemoved(event:version:property:)`` | yes |
/// | ``propertyRetyped(event:version:property:committed:current:)`` | yes |
/// | ``propertyMadeRequired(event:version:property:)`` | yes |
/// | ``requiredPropertyAdded(event:version:property:)`` | yes |
/// | ``unreadableFile(path:)`` | yes |
/// | ``eventAdded(event:version:)`` | no |
/// | ``versionRaised(event:committed:current:)`` | no |
/// | ``optionalPropertyAdded(event:version:property:)`` | no |
/// | ``propertyMadeOptional(event:version:property:)`` | no |
/// | ``consentCategoryChanged(event:version:committed:current:)`` | no |
/// | ``sensitivityChanged(event:version:property:isSensitive:)`` | no |
/// | ``fileOutOfDate(path:)`` | no |
///
/// Raising an event's version is how its author marks a breaking change: the plan then holds a
/// new document, and the committed version's properties aren't compared with the new one's.
public enum TrackingPlanDifference: Sendable, Hashable, CustomStringConvertible {
    /// The committed plan has `event` at `version`, and no event of that name has that version or
    /// a later one now: it was removed or renamed, or its version was lowered.
    case eventRemoved(event: String, version: Int)
    /// A property of the committed event is gone.
    case propertyRemoved(event: String, version: Int, property: String)
    /// A property's schema changed, given by its JSON Schema keywords on one line, without the
    /// `null` an optional property allows.
    case propertyRetyped(event: String, version: Int, property: String, committed: String, current: String)
    /// A property the committed plan lets an event leave out is required now.
    case propertyMadeRequired(event: String, version: Int, property: String)
    /// The event has a required property the committed plan doesn't, which every committed
    /// payload lacks.
    case requiredPropertyAdded(event: String, version: Int, property: String)
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
    /// A property the committed plan requires is optional now.
    case propertyMadeOptional(event: String, version: Int, property: String)
    /// The event's consent category changed, from the committed name to the current one.
    case consentCategoryChanged(event: String, version: Int, committed: String, current: String)
    /// A property became `Sensitive`, or stopped being, as `isSensitive` says.
    case sensitivityChanged(event: String, version: Int, property: String, isSensitive: Bool)
    /// A file of the committed plan isn't the bytes exporting the plan writes now, though its
    /// events are the same: written by hand or by another release, or missing, or no longer part
    /// of the plan.
    case fileOutOfDate(path: String)

    /// Whether a payload the committed plan accepts may be one the current plan rejects; the
    /// table in ``TrackingPlanDifference`` lists which differences are.
    public var isBreaking: Bool {
        switch self {
        case .eventRemoved, .propertyRemoved, .propertyRetyped, .propertyMadeRequired, .requiredPropertyAdded, .unreadableFile:
            true
        case .eventAdded, .versionRaised, .optionalPropertyAdded, .propertyMadeOptional, .consentCategoryChanged, .sensitivityChanged, .fileOutOfDate:
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
        case .requiredPropertyAdded(let event, let version, let property):
            "\(event) v\(version): required property \"\(property)\" was added"
        case .unreadableFile(let path):
            "\(path) is missing from the committed plan, or isn't a tracking plan file"
        case .eventAdded(let event, let version):
            "\(event) v\(version) is new"
        case .versionRaised(let event, let committed, let current):
            "\(event) went from version \(committed) to \(current)"
        case .optionalPropertyAdded(let event, let version, let property):
            "\(event) v\(version): optional property \"\(property)\" was added"
        case .propertyMadeOptional(let event, let version, let property):
            "\(event) v\(version): property \"\(property)\" was required and is now optional"
        case .consentCategoryChanged(let event, let version, let committed, let current):
            "\(event) v\(version): consent category changed from \(committed) to \(current)"
        case .sensitivityChanged(let event, let version, let property, let isSensitive):
            "\(event) v\(version): property \"\(property)\" \(isSensitive ? "is now" : "is no longer") sensitive"
        case .fileOutOfDate(let path):
            "\(path) isn't what exporting the plan writes now"
        }
    }
}
