/// Where the user stands on one consent category.
public enum ConsentStatus: Sendable, Hashable {
    /// The user hasn't decided: a tracker holds the category's events until they do.
    case undecided
    /// The user consented: the category's events are delivered.
    case granted
    /// The user refused: the category's events are dropped.
    case denied
}
