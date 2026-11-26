public import Events

extension Enricher {
    /// An enricher that puts every event in a session: it sets each record's ``SessionKey`` to its
    /// session's identifier, and starts a new session when an event comes `timeout` or more after
    /// the one before it, tracking ``SessionEnded`` and ``SessionStarted`` before that event.
    ///
    /// Nothing is put in a session until the app turns it on, among the enrichers it builds its
    /// tracker with, so every event the tracker tracks carries the key, through any copy of it:
    ///
    /// ```swift
    /// let tracker = Tracker(enrichers: [.sessions()])
    /// ```
    ///
    /// Inactivity is measured between records' timestamps, the time each event was tracked, and
    /// not when the tracker's worker reaches it. So the app returning from the background past the
    /// timeout starts a new session with its first event, such as `ApplicationOpened` (module
    /// `LifecycleTracking`), and one returning sooner goes on with the same.
    ///
    /// The first event the tracker tracks starts the first session: ``SessionStarted`` comes
    /// before it, stamped with its time. A session ends only when an event comes after the
    /// timeout: ``SessionEnded``, stamped with the time of the session's last event, then
    /// ``SessionStarted``, stamped with the new event's, come before that event. So a run's last
    /// session ends with no ``SessionEnded``: a destination takes its end from its last event. Each
    /// session event carries the key of the session it starts or ends, and the context the event
    /// that ended the session had when this enricher reached it; the enrichers after this one run
    /// on them too. Their call site is this call's.
    ///
    /// A session's identifier is a version 7 UUID: the session's start in Unix milliseconds, then
    /// random bits, never derived from the device, the user or another identifier. It is held in
    /// this enricher's memory and nowhere else: neither a store nor anything else writes it to disk,
    /// and a new enricher, as on the next launch, starts with a new session. Records a store
    /// kept from an earlier run aren't enriched again, so they carry no key.
    ///
    /// The enricher's sessions are its own, created by this call: give each tracker its own call.
    ///
    /// - Parameters:
    ///   - timeout: The inactivity after which the next event starts a new session; 30 minutes by
    ///     default.
    ///   - kinds: The session events to track; both by default. Leaving one out, or both, tracks
    ///     none of that kind, and every record still carries its session's key.
    ///   - file: The caller's file; leave it to its default.
    ///   - fileID: The caller's module and file name; leave it to its default.
    ///   - function: The caller's enclosing declaration; leave it to its default.
    ///   - line: The caller's line; leave it to its default.
    ///   - column: The caller's column; leave it to its default.
    /// - Returns: The enricher, which runs on the tracker's worker like any other.
    /// - Precondition: `timeout` is more than zero.
    public static func sessions(
        timeout: Duration = .seconds(30 * 60),
        kinds: Set<SessionEventKind> = Set(SessionEventKind.allCases),
        file: String = #file,
        fileID: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) -> Enricher {
        precondition(timeout > .zero, "A session's timeout must be more than zero, not \(timeout)")
        let rotation = SessionRotation(
            timeout: timeout,
            kinds: kinds,
            callSite: SourceLocation(file: file, fileID: fileID, function: function, line: line, column: column)
        )
        return Enricher(records: rotation.enrich)
    }

    /// An enricher that puts every event in a session, as `sessions(timeout:kinds:)` does,
    /// throwing rather than trapping for a timeout of zero or less.
    ///
    /// - Parameters:
    ///   - checkedTimeout: The inactivity after which the next event starts a new session.
    ///   - kinds: The session events to track; both by default.
    ///   - file: The caller's file; leave it to its default.
    ///   - fileID: The caller's module and file name; leave it to its default.
    ///   - function: The caller's enclosing declaration; leave it to its default.
    ///   - line: The caller's line; leave it to its default.
    ///   - column: The caller's column; leave it to its default.
    /// - Returns: The enricher.
    /// - Throws: ``NonPositiveSessionTimeout`` when `checkedTimeout` is zero or less.
    public static func sessions(
        checkedTimeout: Duration,
        kinds: Set<SessionEventKind> = Set(SessionEventKind.allCases),
        file: String = #file,
        fileID: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) throws(NonPositiveSessionTimeout) -> Enricher {
        guard checkedTimeout > .zero else { throw NonPositiveSessionTimeout() }
        return sessions(timeout: checkedTimeout, kinds: kinds, file: file, fileID: fileID, function: function, line: line, column: column)
    }
}
