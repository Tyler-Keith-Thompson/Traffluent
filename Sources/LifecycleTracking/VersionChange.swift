/// How the app's version changed since the launch before: what tells an install from an update.
enum VersionChange: Equatable {
    /// No version was saved: a first launch.
    case installed
    /// Another version was saved: the first launch of this one.
    case updated(previousVersion: String)
    /// This version was saved: neither.
    case unchanged

    /// The change from `previous`, the version saved, if any, to `current`.
    init(previous: String?, current: String) {
        switch previous {
        case nil:
            self = .installed
        case current:
            self = .unchanged
        case let previous?:
            self = .updated(previousVersion: previous)
        }
    }
}
