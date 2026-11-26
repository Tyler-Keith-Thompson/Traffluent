/// Runs `operation` with `tracker` bound to the current task, so ``Tracker/current`` inside it,
/// and in the child tasks it starts, is `tracker`.
///
/// A nested call replaces the binding for its own scope only. A view's tracker that was never set,
/// or a copy of one made by ``Tracker/enriched(by:)``, doesn't replace a binding already in place:
/// inside it, `tracker` stands for the bound tracker, with the copy's enrichers run after the
/// bound tracker's own. With nothing bound, it stands for the bootstrapped tracker.
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
    // `withValue` is `rethrows` without typed throws, so `operation`'s error is carried out of it
    // as a value, keeping its type, rather than thrown through it.
    let outcome: Swift.Result<Result, Failure> = Tracker.$bound.withValue(Optional(tracker.binding(over: Tracker.bound))) {
        do throws(Failure) {
            return .success(try operation())
        } catch {
            return .failure(error)
        }
    }
    return try outcome.get()
}

/// Runs `operation` with `tracker` bound to the current task, so ``Tracker/current`` inside it,
/// and in the child tasks it starts, is `tracker`.
///
/// A nested call replaces the binding for its own scope only. A view's tracker that was never set,
/// or a copy of one made by ``Tracker/enriched(by:)``, doesn't replace a binding already in place:
/// inside it, `tracker` stands for the bound tracker, with the copy's enrichers run after the
/// bound tracker's own. With nothing bound, it stands for the bootstrapped tracker.
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
    // `withValue` is `rethrows` without typed throws, so `operation`'s error is carried out of it
    // as a value, keeping its type, rather than thrown through it.
    let outcome: Swift.Result<Result, Failure> = await Tracker.$bound.withValue(Optional(tracker.binding(over: Tracker.bound))) { () async -> Swift.Result<Result, Failure> in
        do throws(Failure) {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }
    return try outcome.get()
}
