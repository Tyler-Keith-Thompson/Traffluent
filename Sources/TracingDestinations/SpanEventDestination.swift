public import Destinations
public import Events
public import Tracing

/// A destination that adds each event to the span that was active when the event was tracked.
///
/// The span is found from the record's `ServiceContext`, which was taken when the event was
/// tracked, so a delivery that runs later, under another span or none, still adds the event to
/// the right one. Each span event is named after the event, stamped with the time it was tracked,
/// and carries the event's description under `event` and its call site under OpenTelemetry's
/// `code.*` attribute names.
///
/// A record tracked outside any span, or whose span has ended by the time it is delivered, has no
/// span to join and is left out: span events can't be added to a finished span. Batch tightly
/// enough for spans to outlive their batches, or deliver to another destination as well.
public struct SpanEventDestination<SpanTracer: Tracer>: Destination {
    private let tracer: SpanTracer

    /// A destination that adds events to the active spans of `tracer`.
    ///
    /// - Parameter tracer: The tracer whose spans the events join; usually the bootstrapped
    ///   `InstrumentationSystem.tracer`.
    public init(tracer: SpanTracer) {
        self.tracer = tracer
    }

    /// Adds each record in `batch`, in order, to the span active when it was tracked.
    ///
    /// - Parameter batch: The records to add.
    public func receive(_ batch: [EventRecord]) async {
        for record in batch {
            tracer.activeSpan(identifiedBy: record.context)?.addEvent(record.spanEvent)
        }
    }
}

extension EventRecord {
    /// The span event ``SpanEventDestination`` adds for this record.
    fileprivate var spanEvent: SpanEvent {
        var attributes = SpanAttributes()
        attributes["event"] = String(describing: event)
        if let sourceLocation {
            attributes["code.filepath"] = sourceLocation.fileID
            attributes["code.function"] = sourceLocation.function
            attributes["code.lineno"] = Int64(sourceLocation.line)
            attributes["code.column"] = Int64(sourceLocation.column)
        }
        let instant = DefaultTracerClock.Instant(nanosecondsSinceEpoch: nanosecondsSinceEpoch)
        return SpanEvent(name: name, at: instant, attributes: attributes)
    }

    /// When the event was tracked, in nanoseconds since 1970; zero for a time before 1970, or
    /// one that isn't finite.
    private var nanosecondsSinceEpoch: UInt64 {
        let seconds = timestamp.timeIntervalSince1970
        // A NaN date (a caller's clock, a decoded one) has no instant; max(NaN, 0) is NaN.
        guard seconds.isFinite else { return 0 }
        // Clamped: a tracer instant can't be before the epoch, and a Date this far out
        // (beyond the year 2554) would overflow UInt64 nanoseconds.
        return UInt64(min(max(seconds, 0), 18_446_744_073) * 1_000_000_000)
    }
}
