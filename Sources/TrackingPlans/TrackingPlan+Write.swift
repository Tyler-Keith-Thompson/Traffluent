public import Foundation

extension TrackingPlan {
    /// Writes the plan's files into `directory`, creating it if needed, and deletes the
    /// `.schema.json` and `.example.json` files there that the plan doesn't hold, the documents and
    /// examples of events it no longer has.
    ///
    /// A file whose bytes are already the plan's is left as it is, so its modification date moves
    /// only when its contents do. Other files in the directory are left alone.
    ///
    /// - Parameter directory: The directory the plan's files go in.
    /// - Throws: The `CocoaError` of the first file that couldn't be read, written or removed; the
    ///   files before it are written.
    public func write(to directory: URL) throws(CocoaError) {
        let fileManager = FileManager.default
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
