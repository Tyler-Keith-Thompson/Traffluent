/// The records a recovery dropped for their stored version, counted by event and version, which
/// become one ``DropReport/versionMismatch(event:storedVersion:currentVersion:recordCount:)`` each.
package struct VersionMismatchCounts: Sendable {
    fileprivate struct Key: Hashable {
        let event: String
        let storedVersion: Int
        let currentVersion: Int
    }

    private var counts: [Key: Int] = [:]

    /// No records counted.
    package init() {}

    /// Counts one record of `event` stored at `storedVersion` while its type is at
    /// `currentVersion`.
    package mutating func add(event: String, storedVersion: Int, currentVersion: Int) {
        counts[Key(event: event, storedVersion: storedVersion, currentVersion: currentVersion), default: 0] += 1
    }

    /// A report for each event and stored version, ordered by the UTF-8 bytes of the event's name
    /// and then by the stored version, so the order doesn't depend on hashing.
    package var reports: [DropReport] {
        counts.keys.sorted { $0.precedes($1) }.map { key in
            .versionMismatch(event: key.event, storedVersion: key.storedVersion, currentVersion: key.currentVersion, recordCount: counts[key, default: 0])
        }
    }
}

extension VersionMismatchCounts.Key {
    /// Whether the key's report comes before `other`'s: by the UTF-8 bytes of the event's name, then
    /// by the stored version. One event has one current version, so that order is total.
    fileprivate func precedes(_ other: Self) -> Bool {
        guard event == other.event else { return event.utf8.lexicographicallyPrecedes(other.event.utf8) }
        return storedVersion < other.storedVersion
    }
}
