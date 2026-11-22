public import Events
import Logging
public import Pipelines

/// What app code tracks events with: it hands each event, with the caller's source location, to
/// its pipeline.
///
/// A tracker is a value. Build one from the pipeline where the app starts, then either pass it
/// down or bind it to a task with `withTracker` and read it
/// anywhere inside with ``current``:
///
/// ```swift
/// let pipeline = Pipeline(ConsoleDestination())
/// withTracker(Tracker(pipeline)) {
///     Tracker.current.track(SignedUp(plan: "pro"))
/// }
/// ```
///
/// A binding reaches the work run inside `withTracker`, and the child tasks it starts, but not
/// callbacks a framework runs on tasks of its own, such as a UI framework's button actions: pass
/// those a tracker.
public struct Tracker: Sendable {
    // An enum of what can back a tracker, so a no-op tracker is a case rather than an optional
    // pipeline that every call checks.
    enum Backing: Sendable {
        case pipeline(Pipeline)
        case none
    }

    let backing: Backing

    /// A tracker handing every event to `pipeline`.
    ///
    /// - Parameter pipeline: The pipeline each tracked event goes into.
    public init(_ pipeline: Pipeline) {
        backing = .pipeline(pipeline)
    }

    private init(backing: Backing) {
        self.backing = backing
    }

    /// A tracker that drops every event, logging each one at debug level.
    public static let noOp = Tracker(backing: .none)

    /// The tracker bound to the current task by the nearest enclosing `withTracker`, or
    /// ``noOp`` when none is.
    public static var current: Tracker {
        bound ?? .noOp
    }

    @TaskLocal static var bound: Tracker?

    private static let logger = Logger(label: "Trackers.Tracker")

    /// Tracks `event` with the caller's source location.
    ///
    /// Returns at once. A ``noOp`` tracker drops the event and logs it at debug level, so a missing
    /// `withTracker` shows up in the logs rather than passing silently.
    ///
    /// - Parameters:
    ///   - event: The event to track.
    ///   - file: The caller's file; leave it to its default.
    ///   - fileID: The caller's module and file name; leave it to its default.
    ///   - function: The caller's enclosing declaration; leave it to its default.
    ///   - line: The caller's line; leave it to its default.
    ///   - column: The caller's column; leave it to its default.
    public func track<E: Event>(
        _ event: E,
        file: String = #file,
        fileID: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        switch backing {
        case .pipeline(let pipeline):
            pipeline.track(event, file: file, fileID: fileID, function: function, line: line, column: column)
        case .none:
            Self.logger.debug("Dropped \(E.name) tracked at \(fileID):\(line): no tracker is bound")
        }
    }
}
