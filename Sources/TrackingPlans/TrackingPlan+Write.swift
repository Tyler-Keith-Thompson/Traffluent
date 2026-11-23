public import Foundation

extension TrackingPlan {
    /// Writes the plan's files into `directory`, creating it if needed, and deletes the
    /// `.schema.json` files there that the plan doesn't hold, the documents of events it no longer
    /// has.
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
            .filter { $0.hasSuffix(".schema.json") && !paths.contains($0) }
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
