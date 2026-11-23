import Foundation
public import SystemPackage

extension SegmentStore {
    /// Where a store keeps its segments unless it is given a directory.
    ///
    /// - Apple platforms: `Traffluent` in the app's Application Support directory, under its bundle
    ///   identifier (or, with none, its process name), so apps sharing a container never share a
    ///   log. Application Support rather than Caches, which the system may purge. The store
    ///   excludes the directory from backups and, on iOS, tvOS, watchOS and visionOS, gives it the
    ///   `completeUntilFirstUserAuthentication` protection class.
    /// - Linux: `traffluent` under the process name in the XDG state
    ///   directory, `$XDG_STATE_HOME` when it is set to an absolute path, otherwise
    ///   `~/.local/state`.
    ///
    /// Pass `directory:` to put the log anywhere else.
    public static var defaultDirectory: FilePath {
        #if canImport(Darwin)
        let owner = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        return FilePath(URL.applicationSupportDirectory.path(percentEncoded: false))
            .appending(owner)
            .appending("Traffluent")
        #else
        let environment = ProcessInfo.processInfo.environment
        let state: FilePath
        if let configured = environment["XDG_STATE_HOME"].map({ FilePath($0) }), configured.isAbsolute {
            state = configured
        } else {
            let home = environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
            state = FilePath(home).appending(".local").appending("state")
        }
        return state
            .appending(ProcessInfo.processInfo.processName)
            .appending("traffluent")
        #endif
    }
}
