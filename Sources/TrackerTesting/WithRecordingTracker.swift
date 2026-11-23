import Events
public import Trackers

/// Runs `body` with a tracker of its own bound to the current task, then returns every event
/// tracked through it, in the order tracked.
///
/// For a test of what the code under test tracks through ``/Trackers/Tracker/current``:
///
/// ```swift
/// let tracked = await withRecordingTracker {
///     Tracker.current.track(SignedUp(plan: "pro"))
/// }
/// #expect(tracked.events(of: SignedUp.self) == [SignedUp(plan: "pro")])
/// ```
///
/// Each call makes a fresh tracker and binds it with `withTracker` for `body` alone, so tests
/// running at once never see each other's events, and nothing is shared between calls. Once
/// `body` returns, the tracker is finished and every record it published is read, without a
/// bound. Events tracked after that, by work `body` started but didn't wait for, are dropped.
///
/// - Parameter body: The code under test.
/// - Returns: The events tracked, with what `body` returned as its ``TrackerRecording/value``.
/// - Throws: What `body` throws; the events tracked before it threw are discarded.
public nonisolated(nonsending) func withRecordingTracker<Value, Failure: Error>(
    _ body: () throws(Failure) -> Value
) async throws(Failure) -> TrackerRecording<Value> {
    try await withRecordingTracker { (_: Tracker) throws(Failure) -> Value in try body() }
}

/// Runs `body` with a tracker of its own bound to the current task, then returns every event
/// tracked through it, in the order tracked.
///
/// For a test of what asynchronous code tracks through ``/Trackers/Tracker/current``, including
/// the child tasks it starts:
///
/// ```swift
/// let tracked = await withRecordingTracker {
///     await Task.yield()
///     Tracker.current.track(SignedUp(plan: "pro"))
/// }
/// #expect(tracked.names == ["SignedUp"])
/// ```
///
/// Each call makes a fresh tracker and binds it with `withTracker` for `body` alone, so tests
/// running at once never see each other's events, and nothing is shared between calls. Once
/// `body` returns, the tracker is finished and every record it published is read, without a
/// bound. Events tracked after that, by work `body` started but didn't wait for, are dropped.
///
/// - Parameter body: The code under test.
/// - Returns: The events tracked, with what `body` returned as its ``TrackerRecording/value``.
/// - Throws: What `body` throws; the events tracked before it threw are discarded.
public nonisolated(nonsending) func withRecordingTracker<Value, Failure: Error>(
    _ body: nonisolated(nonsending) () async throws(Failure) -> Value
) async throws(Failure) -> TrackerRecording<Value> {
    try await withRecordingTracker { (_: Tracker) async throws(Failure) -> Value in try await body() }
}

/// Runs `body` with a tracker of its own, which it is given and which is bound to the current
/// task, then returns every event tracked through it, in the order tracked.
///
/// For a test of code that is handed its tracker rather than reading
/// ``/Trackers/Tracker/current``: a SwiftUI view given it with `tracker(_:)`, or a UIKit view
/// controller with `traitOverrides.tracker`:
///
/// ```swift
/// let tracked = await withRecordingTracker { tracker in
///     let host = NSHostingView(rootView: CheckoutView().tracker(tracker))
///     host.layoutSubtreeIfNeeded()
/// }
/// #expect(tracked.events(of: CheckoutViewed.self) == [CheckoutViewed()])
/// ```
///
/// Each call makes a fresh tracker and binds it with `withTracker` for `body` alone, so tests
/// running at once never see each other's events, and nothing is shared between calls. Once
/// `body` returns, the tracker is finished and every record it published is read, without a
/// bound. Events tracked after that, through a copy `body` kept, are dropped.
///
/// - Parameter body: The code under test, given the tracker.
/// - Returns: The events tracked, with what `body` returned as its ``TrackerRecording/value``.
/// - Throws: What `body` throws; the events tracked before it threw are discarded.
public nonisolated(nonsending) func withRecordingTracker<Value, Failure: Error>(
    _ body: (Tracker) throws(Failure) -> Value
) async throws(Failure) -> TrackerRecording<Value> {
    let tracker = Tracker()
    let value = try withTracker(tracker) { () throws(Failure) -> Value in try body(tracker) }
    return await TrackerRecording(value: value, records: tracker.finishedRecords())
}

/// Runs `body` with a tracker of its own, which it is given and which is bound to the current
/// task, then returns every event tracked through it, in the order tracked.
///
/// For a test of asynchronous code that is handed its tracker rather than reading
/// ``/Trackers/Tracker/current``:
///
/// ```swift
/// let tracked = await withRecordingTracker { tracker in
///     await Task.yield()
///     tracker.track(SignedUp(plan: "pro"))
/// }
/// #expect(tracked.events(of: SignedUp.self) == [SignedUp(plan: "pro")])
/// ```
///
/// Each call makes a fresh tracker and binds it with `withTracker` for `body` alone, so tests
/// running at once never see each other's events, and nothing is shared between calls. Once
/// `body` returns, the tracker is finished and every record it published is read, without a
/// bound. Events tracked after that, through a copy `body` kept, are dropped.
///
/// - Parameter body: The code under test, given the tracker.
/// - Returns: The events tracked, with what `body` returned as its ``TrackerRecording/value``.
/// - Throws: What `body` throws; the events tracked before it threw are discarded.
public nonisolated(nonsending) func withRecordingTracker<Value, Failure: Error>(
    _ body: nonisolated(nonsending) (Tracker) async throws(Failure) -> Value
) async throws(Failure) -> TrackerRecording<Value> {
    let tracker = Tracker()
    let value = try await withTracker(tracker) { () async throws(Failure) -> Value in try await body(tracker) }
    return await TrackerRecording(value: value, records: tracker.finishedRecords())
}

extension Tracker {
    /// Finishes the tracker, then reads every record it published, in order.
    fileprivate func finishedRecords() async -> [EventRecord] {
        await finish()
        var records: [EventRecord] = []
        for await record in self.records {
            records.append(record)
        }
        return records
    }
}
