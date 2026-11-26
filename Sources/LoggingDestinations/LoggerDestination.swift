public import Destinations
public import Events
import Foundation
public import Logging

/// A destination that writes each event to a swift-log `Logger`.
///
/// Each record becomes one log entry whose message is the event's name. The entry's metadata
/// holds the event's description under `event`, the time it was tracked under `event.timestamp`,
/// its call site under OpenTelemetry's `code.*` names, and every value of its `ServiceContext`
/// under the value's key name. The entry's own file, function and line are the event's call site
/// too, so a handler that prints them points at the `track` call.
public struct LoggerDestination: Destination {
    private let logger: Logger
    private let level: Logger.Level

    /// A destination that writes to `logger` at `level`.
    ///
    /// - Parameters:
    ///   - logger: Where each event is written.
    ///   - level: The level each event is written at; `info` by default.
    public init(logger: Logger, level: Logger.Level = .info) {
        self.logger = logger
        self.level = level
    }

    /// Writes each record in `batch` as a log entry, in order.
    ///
    /// - Parameter batch: The records to write.
    public func receive(_ batch: [EventRecord]) async {
        batch.forEach(write)
    }

    private func write(_ record: EventRecord) {
        // A record whose call site was dropped is logged with empty names and line 0 rather
        // than this file's, which would point at the wrong code. So is a negative line, which
        // no source has and `UInt` can't hold.
        let location = record.sourceLocation
        logger.log(
            level: level,
            "\(record.name)",
            metadata: record.metadata,
            source: location?.moduleName,
            file: location?.fileID ?? "",
            function: location?.function ?? "",
            line: location.flatMap { UInt(exactly: $0.line) } ?? 0)
    }
}

extension EventRecord {
    /// What ``LoggerDestination`` writes beside the event's name.
    fileprivate var metadata: Logger.Metadata {
        var metadata: Logger.Metadata = [:]
        // Context first, so a context key that happens to share a name with one of the fixed keys
        // below can't hide the event or its call site.
        context.forEach { key, value in
            metadata[key.name] = .string(String(describing: value))
        }
        metadata["event"] = .string(String(describing: event))
        metadata["event.timestamp"] = .string(timestamp.formatted(.iso8601))
        if let sourceLocation {
            metadata["code.filepath"] = .string(sourceLocation.fileID)
            metadata["code.function"] = .string(sourceLocation.function)
            metadata["code.lineno"] = .string(String(sourceLocation.line))
            metadata["code.column"] = .string(String(sourceLocation.column))
        }
        return metadata
    }
}
