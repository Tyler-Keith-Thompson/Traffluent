import Foundation
public import Persistence
public import SystemPackage

/// A ``VersionStore`` that keeps the version in a file named `version` in a directory.
///
/// Give it the directory a `SegmentStore` keeps its records in, its default, so the version and
/// the records the app hasn't delivered live and are removed together. The store reads only its
/// own segment files, so it leaves this one alone.
public struct FileVersionStore: VersionStore {
    /// The file the version is kept in.
    public let file: FilePath

    /// A store keeping the version in a file named `version` in `directory`.
    ///
    /// - Parameter directory: Where the file goes; created, with its parents, when the version is
    ///   first saved. `SegmentStore.defaultDirectory` unless given.
    public init(directory: FilePath = SegmentStore.defaultDirectory) {
        file = directory.appending("version")
    }

    /// The version in the file, or `nil` when there is no file.
    ///
    /// - Returns: The file's contents as UTF-8.
    /// - Throws: Foundation's error when the file exists but can't be read.
    public func load() throws -> String? {
        let url = URL(filePath: file.string)
        guard FileManager.default.fileExists(atPath: file.string) else { return nil }
        return String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    /// Writes `version` to the file, as UTF-8, replacing it atomically.
    ///
    /// - Parameter version: The version the app runs at now.
    /// - Throws: Foundation's error when the directory can't be created or the file written.
    public func save(_ version: String) throws {
        let url = URL(filePath: file.string)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Atomically, so a launch killed mid-write leaves the previous version, not half of one.
        try Data(version.utf8).write(to: url, options: .atomic)
    }
}
