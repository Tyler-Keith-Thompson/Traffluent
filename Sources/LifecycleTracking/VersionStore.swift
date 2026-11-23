/// Where `trackLifecycle` keeps the app's version from one launch to the next, to tell an install
/// from an update.
///
/// It keeps the version and nothing else: never an identifier of the device, the user or the
/// install. ``FileVersionStore`` keeps it in a file; ``InMemoryVersionStore`` keeps it for the
/// life of the value, for tests. Conform to keep it elsewhere, such as in `UserDefaults`.
public protocol VersionStore: Sendable {
    /// The version the app last ran at, or `nil` if none was saved: a first launch.
    ///
    /// Called once, off the main thread, as lifecycle tracking starts.
    ///
    /// - Returns: The version saved last.
    /// - Throws: When the version can't be read. Tracking then tracks neither an install nor an
    ///   update, and doesn't save the version, so a later launch decides again.
    func load() throws -> String?

    /// Keeps `version` for the next launch's ``load()``.
    ///
    /// Called once, off the main thread, as lifecycle tracking starts, after ``load()``.
    ///
    /// - Parameter version: The version the app runs at now.
    /// - Throws: When the version can't be written. Tracking then tracks neither an install nor an
    ///   update, so a later launch decides again rather than reporting this one twice.
    func save(_ version: String) throws
}
