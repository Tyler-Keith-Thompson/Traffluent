import Synchronization

/// A ``VersionStore`` that keeps the version in memory, for tests and for processes with nothing
/// to compare against: each new one starts with the version it is given.
///
/// Copies share the version.
public struct InMemoryVersionStore: VersionStore {
    // A class holding a Mutex, so copies share one version and the struct stays copyable.
    private final class Storage: Sendable {
        let version: Mutex<String?>

        init(_ version: String?) {
            self.version = Mutex(version)
        }
    }

    private let storage: Storage

    /// A store holding `version`.
    ///
    /// - Parameter version: The version a launch before ran at; `nil`, a first launch, by default.
    public init(version: String? = nil) {
        storage = Storage(version)
    }

    /// The version saved last.
    public var version: String? {
        storage.version.withLock { $0 }
    }

    /// The version saved last.
    ///
    /// - Returns: ``version``.
    public func load() -> String? {
        version
    }

    /// Keeps `version`.
    ///
    /// - Parameter version: The version the app runs at now.
    public func save(_ version: String) {
        storage.version.withLock { $0 = version }
    }
}
