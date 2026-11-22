/// Runs `operation` with `tracker` bound to the current task, so ``Tracker/current`` inside it,
/// and in the child tasks it starts, is `tracker`.
///
/// A nested call replaces the binding for its own scope only.
///
/// - Parameters:
///   - tracker: The tracker to bind while `operation` runs.
///   - operation: The work to run with `tracker` bound.
/// - Returns: What `operation` returns.
/// - Throws: What `operation` throws.
public func withTracker<Result, Failure: Error>(
    _ tracker: Tracker,
    _ operation: () throws(Failure) -> Result
) throws(Failure) -> Result {
    do {
        return try Tracker.$bound.withValue(tracker, operation: operation)
    } catch {
        // `withValue` is `rethrows` without typed throws, so the error it rethrows is the one
        // `operation` threw, a `Failure`; the cast cannot fail.
        throw error as! Failure
    }
}

/// Runs `operation` with `tracker` bound to the current task, so ``Tracker/current`` inside it,
/// and in the child tasks it starts, is `tracker`.
///
/// A nested call replaces the binding for its own scope only.
///
/// - Parameters:
///   - tracker: The tracker to bind while `operation` runs.
///   - operation: The work to run with `tracker` bound.
/// - Returns: What `operation` returns.
/// - Throws: What `operation` throws.
public nonisolated(nonsending) func withTracker<Result, Failure: Error>(
    _ tracker: Tracker,
    _ operation: nonisolated(nonsending) () async throws(Failure) -> Result
) async throws(Failure) -> Result {
    do {
        return try await Tracker.$bound.withValue(tracker, operation: operation)
    } catch {
        // `withValue` is `rethrows` without typed throws, so the error it rethrows is the one
        // `operation` threw, a `Failure`; the cast cannot fail.
        throw error as! Failure
    }
}
