# Planted bugs for GRDBPersistence; run with `just mutate GRDBPersistence`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/GRDBPersistence/<file> (or `nth=` picks one), and mode="stmt" replaces whole statements
# rather than an expression. Every mutant must be caught; one that survives needs a test, or a
# note here saying why it is equivalent to the original. The record encoding and the event
# registry the store shares with SegmentStore are Persistence's, and planted there.
#
# Known equivalent mutants (left out, as they would survive by design):
# - Evicting when the excess is 0 as well (`excess >= 0`): oldestRows(holding: 0) takes no row,
#   so nothing is deleted or reported.
# - Dropping the savepoint around an acknowledgement or a mark: a failure there fails the first
#   statement, before anything is written, as SQLite's query_only does; only a failure partway
#   through a batch, which no test can cause, would tell them apart.

TESTS = ["PersistenceTests"]

L = "DatabaseLog.swift"
S = "DatabaseStore.swift"

MUTANTS = [
    # Event types not in `events` (TRAF-62).
    # The drop reports left open once the store is gone.
    Mutant("reportsneverend", L, "dropReports.finish()", "", mode="stmt"),
    Mutant("unlistednotreported", L, "dropReports.enqueue(.notPersisted(event: record.name))", "", mode="stmt"),
    Mutant("unlistedreportedeachrecord", L, "unlistedTypes.insert(type(of: record.event))", "(unlistedTypes.insert(type(of: record.event)) || true)"),

    # The table.
    Mutant("migrationsharedbytables", L, '"Traffluent.DatabaseStore.\\(table).v1"', '"Traffluent.DatabaseStore.v1"'),
    Mutant("newrowsmarked", L, "false", "true"),
    # Appending.
    Mutant("payloadnotwritten", L, "Data(payload)", "Data()"),
    Mutant("timestampsince1970", L, "record.timestamp.timeIntervalSinceReferenceDate", "record.timestamp.timeIntervalSince1970"),
    Mutant("nottagged", L, "tagged.deliveryTag = DeliveryTag(acknowledger: self, position: UInt64(position))", "", mode="stmt"),
    Mutant("positionlost", L, "UInt64(position)", "UInt64(0)"),
    Mutant("largestrejected", L, "payload.count <= byteBound", "payload.count < byteBound"),
    Mutant("unbounded", L, "excess > 0", "false"),
    Mutant("excessoffbyone", L, "state.withLock { $0.byteCount } + payload.count - byteBound", "state.withLock { $0.byteCount } + payload.count - byteBound + 1"),
    Mutant("evictsnewest", L, '"SELECT position, timestamp, length(payload) FROM \\(table.quotedDatabaseIdentifier) ORDER BY position"', '"SELECT position, timestamp, length(payload) FROM \\(table.quotedDatabaseIdentifier) ORDER BY position DESC"'),
    Mutant("evictsonemore", L, "eviction.byteCount < byteCount", "eviction.byteCount <= byteCount"),
    Mutant("evictionnotdeleted", L, 'try db.execute(sql: "DELETE FROM \\(table.quotedDatabaseIdentifier) WHERE position <= ?", arguments: [last])', "", mode="stmt", nth=0),
    Mutant("evictionnotsubtracted", L, "payload.count - eviction.byteCount", "payload.count"),
    Mutant("evictionnotuncounted", L, "1 - eviction.recordCount", "1"),
    Mutant("earliestnotwidened", L, "min($0.lowerBound, timestamp)", "$0.lowerBound"),
    Mutant("latestnotwidened", L, "max($0.upperBound, timestamp)", "timestamp"),
    Mutant("deletesonlyfirst", L, "lastPosition = position", "lastPosition = lastPosition ?? position", mode="stmt"),
    # The first report is an event whose encode(to:) throws (TRAF-83), the second a failed write's.
    Mutant("encodefailurenotreported", L, "dropReports.enqueue(.writeFailed(recordCount: 1, timestamps: record.timestamp...record.timestamp))", "", mode="stmt", nth=0),
    Mutant("writefailurenotreported", L, "dropReports.enqueue(.writeFailed(recordCount: 1, timestamps: record.timestamp...record.timestamp))", "", mode="stmt", nth=1),
    # A drop that yields no report leaves the test waiting for it; the suite's time limit catches it.
    Mutant("recoverydropnotreported", L, "dropReports.enqueue(report)", "", mode="stmt", nth=0),
    Mutant("dropnotreported", L, "dropReports.enqueue(report)", "", mode="stmt", nth=1),
    # Delivery.
    Mutant("marknotwritten", L, "try statement.execute(arguments: [Int64(truncatingIfNeeded: position)])", "", mode="stmt"),
    Mutant("markclears", L, '"UPDATE \\(table.quotedDatabaseIdentifier) SET isBeingDelivered = 1 WHERE position = ?"', '"UPDATE \\(table.quotedDatabaseIdentifier) SET isBeingDelivered = 0 WHERE position = ?"'),
    Mutant("failedmarkdelivered", L, "return Set(positions)", "return []", mode="stmt"),
    Mutant("acknowledgednotdeleted", L, '"DELETE FROM \\(table.quotedDatabaseIdentifier) WHERE position = ? RETURNING length(payload)"', '"SELECT length(payload) FROM \\(table.quotedDatabaseIdentifier) WHERE position = ?"'),
    Mutant("acknowledgedbytesnotsubtracted", L, "state.byteCount -= deleted.byteCount", "", mode="stmt"),
    Mutant("acknowledgedpendingnotsubtracted", L, "state.pendingCount -= deleted.recordCount", "", mode="stmt"),
    Mutant("nocheckpoint", L, "_ = try db.checkpoint(.passive)", "", mode="stmt"),
    # Recovery.
    Mutant("recoveredpendingzero", L, "recovered.records.count", "0"),
    Mutant("recovereduntagged", L, "record.deliveryTag = DeliveryTag(acknowledger: self, position: UInt64(recovered.position))", "", mode="stmt"),
    Mutant("recoveredtakentwice", L, "state.recovered = []", "", mode="stmt"),
    Mutant("redeliveryignored", L, "record.isRedelivered = row[2]", "", mode="stmt"),
    Mutant("recoveredbytesnotcounted", L, "recovery.byteCount += payload.count", "", mode="stmt"),
    Mutant("undecodablekept", L, "try statement.execute(arguments: [position])", "", mode="stmt"),
    Mutant("undecodablenotreported", L, "reports.append(.undecodable(recordCount: undecodable.count))", "", mode="stmt"),
    Mutant("recoveryunbounded", L, "recovery.byteCount > byteBound", "false"),
    Mutant("recoveryevictionnotdeleted", L, 'try db.execute(sql: "DELETE FROM \\(table.quotedDatabaseIdentifier) WHERE position <= ?", arguments: [last])', "", mode="stmt", nth=1),
    # The store.
    Mutant("defaultbound", S, "5 * 1024 * 1024", "5 * 1000 * 1000"),
    Mutant("defaulttable", S, '"traffluentRecord"', '"traffluentRecords"'),
    Mutant("zeroboundallowed", S, "byteBound > 0", "byteBound >= 0"),
    Mutant("duplicatenamesmisnamed", S, "throw .duplicateEventName(error.name, firstType: error.firstType, secondType: error.secondType)", "throw .nonPositiveByteBound", mode="stmt"),
    Mutant("duplicatetypesswapped", S, "error.firstType", "error.secondType"),
    # Rows stored at another schema version (TRAF-18): deleted and reported.
    Mutant("mismatchedkept", L, "undecodable + mismatched", "undecodable"),
    Mutant("mismatchonlynotdeleted", L, "!undecodable.isEmpty || !mismatched.isEmpty", "!undecodable.isEmpty"),
    Mutant("mismatchnotcounted", L, "mismatches.add(event: event, storedVersion: storedVersion, currentVersion: currentVersion)", "", mode="stmt"),
    Mutant("mismatchnotreported", L, "reports += mismatches.reports", "", mode="stmt"),
    # Reading rows back for a destination whose full buffer dropped them (TRAF-66).
    Mutant("readbackwrongposition", L, "DeliveryTag(acknowledger: self, position: position)", "DeliveryTag(acknowledger: self, position: position + 1)"),
    Mutant("readbacknothing", L, "records.append(record)", "", mode="stmt"),
    Mutant("readbackwrongrow", L, '"SELECT payload FROM \\(table.quotedDatabaseIdentifier) WHERE position = ?"', '"SELECT payload FROM \\(table.quotedDatabaseIdentifier) WHERE position = ? + 1"'),
]
