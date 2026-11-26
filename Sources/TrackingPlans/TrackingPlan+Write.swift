public import Foundation

extension TrackingPlan {
    /// Writes the plan's files into `directory`, creating it if needed, and deletes the
    /// `.schema.json` and `.example.json` files there that the plan doesn't hold.
    ///
    /// The files are ``files(carryingForward:)`` of the plan already in `directory`, so each
    /// event's document keeps, marked deprecated, the properties its version had there and no
    /// longer declares. The documents and examples there of an event's earlier versions, below
    /// the newest the plan lists, are kept unchanged and listed in the index, since releases
    /// still installed send those versions.
    ///
    /// What is deleted: every version's files of an event the plan no longer lists, the files of
    /// a version above the newest it lists (a version lowered, or a file from another branch,
    /// which no release of this plan sends), and an earlier version's example without its
    /// document.
    ///
    /// A file whose bytes are already the plan's is left as it is, so its modification date moves
    /// only when its contents do. Other files in the directory are left alone.
    ///
    /// - Parameter directory: The directory the plan's files go in.
    /// - Throws: The `CocoaError` of the first file that couldn't be read, written or removed; the
    ///   files before it are written.
    public func write(to directory: URL) throws(CocoaError) {
        let fileManager = FileManager.default
        let files = files(carryingForward: TrackingPlan.planFiles(in: directory))
        try cocoa { try fileManager.createDirectory(at: directory, withIntermediateDirectories: true) }
        let paths = Set(files.map(\.path))
        let stale = try cocoa { try fileManager.contentsOfDirectory(atPath: directory.path) }
            .filter { TrackingPlan.isPlanFile($0) && !paths.contains($0) }
            .sorted()
        for path in stale {
            try cocoa { try fileManager.removeItem(at: directory.appendingPathComponent(path)) }
        }
        for file in files {
            let url = directory.appendingPathComponent(file.path)
            let contents = Data(file.contents)
            guard fileManager.contents(atPath: url.path) != contents else { continue }
            try cocoa { try contents.write(to: url, options: .atomic) }
        }
    }
}

extension TrackingPlan {
    /// Whether a file of this name in a plan's directory is one a plan writes: the index, or an
    /// event's document or example.
    static func isPlanFile(_ path: String) -> Bool {
        path == indexFileName || path.hasSuffix(".schema.json") || path.hasSuffix(".example.json")
    }

    /// The plan files in `directory` that can be read; none when it doesn't exist or can't be
    /// listed.
    static func planFiles(in directory: URL) -> [File] {
        let fileManager = FileManager.default
        let paths = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return paths.filter(isPlanFile).compactMap { path in
            fileManager.contents(atPath: directory.appendingPathComponent(path).path).map { File(path: path, contents: Array($0)) }
        }
    }
}

/// Runs `body`, whose Foundation calls throw untyped errors, as throwing `CocoaError`: every file
/// error they throw is one.
private func cocoa<Result>(_ body: () throws -> Result) throws(CocoaError) -> Result {
    do {
        return try body()
    } catch let error as CocoaError {
        throw error
    } catch {
        throw CocoaError(.fileWriteUnknown)
    }
}
