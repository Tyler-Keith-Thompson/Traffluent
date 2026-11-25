# Planted bugs for Persistence; run with `just mutate Persistence`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in Sources/Persistence/<file>
# (or `nth=` picks one), and mode="stmt" replaces whole statements rather than an expression.
# Every mutant must be caught; one that survives needs a test, or a note here saying why it is
# equivalent to the original. Mutants with module= plant bugs in the code that wires a store in:
# deliver(to:)'s acknowledgement (Destinations) and track's write-through (Trackers), which the
# store's suites exercise.
#
# Known equivalent mutants (left out, as they would survive by design):
# - Leaving a synchronized segment marked as needing synchronization: the next synchronize
#   fsyncs it again, which only counting fsync calls could observe.
# - Marking a recovered undecodable record as not acknowledged: it never counts as pending, so
#   it can only change a drop report's count for a recovered segment the bound evicts while it
#   holds an undecodable record, which no test arranges.
# - count(_:elementSize:)'s check that a count fits in the bytes left: every reader of a count
#   still throws endOfData without it (a string's read checks again; an array's elements and a
#   skip run out). It only bounds the memory an array reserves for a corrupt count, which a test
#   can't observe safely.
# - find's restoring the position after a key that doesn't match in place: the search that
#   follows saves the position it is given and returns to it after a miss, so the next key in
#   place is read from the value after the key the search skipped, which no key matches; the
#   search then finds it. Only the work done differs.
# - The directory's fsync after a new segment (pending.directory, synchronizeDirectory): only a
#   power cut on Linux could observe the entry it makes durable.
# - The fsync shim's own failure path: fsync on an open regular file doesn't fail in a test.
# - The frame buffer an append takes and gives back (spareFrameBuffer), and the limit on the one
#   kept: without them each frame allocates a buffer of its own, which only counting allocations
#   could observe.
# - BinaryEncoder.makeRoom's doubling, and write(byteCount:)'s check growing a byte early: the
#   bytes written are the same, only how often the storage grows differs.
# - String(validatingUTF8Bytes:)'s ASCII check answering false: every string then takes the
#   generic validation, which reads ASCII the same.
# - String.encode's copy for a string that isn't contiguous UTF-8: only a lazily bridged NSString
#   is, on Apple platforms, which no test makes.
# - The rewrite's failure path deleting its temporary file, and its synchronizations (the file's
#   fsync, the directory's): a test can only make the temporary file's creation fail, which leaves
#   nothing to delete, and only a power cut could observe either fsync.

TESTS = ["PersistenceTests"]

F = "SegmentFormat.swift"
L = "SegmentLog.swift"
S = "SegmentStore.swift"
R = "EventRegistry.swift"
C = "StandardConformances.swift"
D = "BinaryDecoder.swift"
E = "BinaryEncoder.swift"
N = "RecordEncoding.swift"
V = "VersionMismatchCounts.swift"
K = "KeyedBinaryDecoder.swift"
KE = "KeyedBinaryEncoder.swift"

MUTANTS = [
    # Event types not in `events` (TRAF-62).
    Mutant("unlistednotreported", L, "dropReporter.yield(.notPersisted(event: record.name))", "", mode="stmt"),
    Mutant("unlistedreportedeachrecord", L, "unlistedTypes.insert(type(of: record.event))", "(unlistedTypes.insert(type(of: record.event)) || true)"),
    Mutant("unlistedtypesalwaysnew", "UnlistedEventTypes.swift", "seen.withLock { $0.insert(ObjectIdentifier(type)).inserted }", "seen.withLock { _ in true }", mode="stmt"),

    # The format.
    Mutant("headermagic", F, "[0x54, 0x52, 0x46, 0x4C, 2, 0, 0, 0]", "[0x54, 0x52, 0x46, 0x4D, 2, 0, 0, 0]"),
    Mutant("headerversion", F, "[0x54, 0x52, 0x46, 0x4C, 2, 0, 0, 0]", "[0x54, 0x52, 0x46, 0x4C, 3, 0, 0, 0]"),
    Mutant("magicnotchecked", F, "bytes[0..<4].elementsEqual(header[0..<4])", "true"),
    Mutant("newerunreadable", F, "guard version <= Self.version else { return .newerVersion(version) }", "", mode="stmt"),
    Mutant("reservednotchecked", F, "guard bytes[4..<header.count].elementsEqual(header[4...]) else { return .unreadable }", "", mode="stmt"),
    Mutant("emptyframeaccepted", F, "length >= 1", "length >= 0"),
    Mutant("lengthpastend", F, "length <= bytes.count - start", "length <= bytes.count - start + 1"),
    Mutant("checksumignored", F, "bytes.crc32(of: payload) == checksum", "true"),
    Mutant("malformedmarkaccepted", F, "guard (length - 1) % 4 == 0 else { break reading }", "", mode="stmt"),
    Mutant("validcountnotadvanced", F, "contents.validByteCount = offset", "", mode="stmt"),
    Mutant("marknotread", F, "contents.marked.insert(bytes.littleEndianUInt32(at: numberOffset))", "", mode="stmt"),
    Mutant("payloadwithkind", F, "start + 1..<payload.upperBound", "start..<payload.upperBound"),
    Mutant("filealwaysnil", N, "location.file == location.fileID", "true"),
    Mutant("filefromfileid", N, "file ?? fileID", "fileID"),
    Mutant("trailingbytesaccepted", N, "guard decoder.isAtEnd else { throw .invalidValue }", "", mode="stmt"),
    # The record's identifier, written first and given back on recovery.
    Mutant("idnotwritten", N, 'map.encode(record.id, forKey: "id")', "", mode="stmt"),
    Mutant("idnotrestored", N, "return .record(EventRecord(id: id, event: event, timestamp: timestamp, sourceLocation: location?.location))", "return .record(EventRecord(event: event, timestamp: timestamp, sourceLocation: location?.location))", mode="stmt"),
    Mutant("lengthnotwritten", F, "frame.storeBytes(of: length.littleEndian, toByteOffset: 0, as: UInt32.self)", "", mode="stmt"),
    Mutant("checksumnotwritten", F, "frame.storeBytes(of: checksum.littleEndian, toByteOffset: 4, as: UInt32.self)", "", mode="stmt"),
    Mutant("markoffbyone", F, "encoder.writeLittleEndian(index)", "encoder.writeLittleEndian(index + 1)", mode="stmt"),
    # Appending.
    Mutant("notwritten", L, "try frame.write(to: state.segments[active].file.descriptor)", "", mode="stmt"),
    Mutant("nottagged", L, "tagged.deliveryTag = DeliveryTag(acknowledger: self, position: position)", "", mode="stmt"),
    Mutant("positionwithoutindex", L, "return number << 32 | index", "return number << 32", mode="stmt"),
    Mutant("notpending", L, "        pendingCount += 1", "", mode="stmt"),
    Mutant("lognotcounted", L, "state.byteCount += frame.byteCount", "", mode="stmt"),
    Mutant("segmentnotcounted", L, "        byteCount += frameByteCount", "", mode="stmt"),
    Mutant("rollsearly", L, "active.byteCount + frameByteCount > segmentByteCount", "active.byteCount + frameByteCount >= segmentByteCount"),
    Mutant("boundoffbyone", L, "state.byteCount + frameByteCount + (state.hasActive ? 0 : SegmentFormat.header.count) > byteBound", "state.byteCount + frameByteCount + (state.hasActive ? 0 : SegmentFormat.header.count) >= byteBound"),
    # After boundoffbyone, its condition holds two copies; the second is the original's.
    Mutant("headernotbounded", L, "(state.hasActive ? 0 : SegmentFormat.header.count)", "0", nth=1),
    Mutant("fullignored", L, "guard state.byteCount + frameByteCount + (state.hasActive ? 0 : SegmentFormat.header.count) <= byteBound else { return .full }", "", mode="stmt"),
    Mutant("writefailurenotreported", L, "dropReporter.yield(.writeFailed(recordCount: 1, timestamps: record.timestamp...record.timestamp))", "", mode="stmt", nth=0),
    Mutant("fullnotreported", L, "dropReporter.yield(.writeFailed(recordCount: 1, timestamps: record.timestamp...record.timestamp))", "", mode="stmt", nth=1),
    Mutant("partialwritekept", L, "try? state.segments[active].file.descriptor.resize(to: Int64(state.segments[active].byteCount))", "", mode="stmt"),
    Mutant("partialheaderkept", L, "try? path.removeFile()", "", mode="stmt"),
    Mutant("undeletedforgotten", L, "state.undeleted.insert(segment.number)", "", mode="stmt"),
    Mutant("undeletedsubtracted", L, "state.undeleted.insert(segment.number)", "state.undeleted.insert(segment.number)\nstate.byteCount -= segment.byteCount", mode="stmt"),
    Mutant("largestrejected", L, "frameByteCount <= byteBound - SegmentFormat.header.count", "frameByteCount < byteBound - SegmentFormat.header.count"),
    Mutant("evictsnewest", L, "Self.delete(state.segments.removeFirst(), from: &state, reports: &reports)", "Self.delete(state.segments.removeLast(), from: &state, reports: &reports)", mode="stmt", nth=0),
    # A drop that yields no report leaves the test waiting for it; the suite's time limit catches it.
    Mutant("recoverydropnotreported", L, "dropReporter.yield(report)", "", mode="stmt", nth=0),
    Mutant("dropnotreported", L, "dropReporter.yield(report)", "", mode="stmt", nth=1),
    Mutant("markdropnotreported", L, "dropReporter.yield(report)", "", mode="stmt", nth=2),
    Mutant("markunbounded", L, "state.byteCount + frame.count > byteBound", "false"),
    Mutant("reportcountsdelivered", L, "zip(segment.timestamps, segment.acknowledged).filter { !$0.1 }", "zip(segment.timestamps, segment.acknowledged).filter { _ in true }"),
    Mutant("reportlatestonly", L, "earliest...latest", "latest...latest"),
    Mutant("headernotwritten", L, "try withErrno { try descriptor.writeAll(SegmentFormat.header) }", "", mode="stmt"),
    Mutant("numbernotadvanced", L, "state.nextNumber += 1", "", mode="stmt"),
    # Delivery.
    Mutant("undeleteddelivered", L, "withheld.formUnion(indices.map { number << 32 | UInt64($0) })", "", mode="stmt", nth=0),
    Mutant("unmarkeddelivered", L, "withheld.formUnion(indices.map { number << 32 | UInt64($0) })", "", mode="stmt", nth=1),
    Mutant("marknotwritten", L, "try withErrno { try state.segments[segment].file.descriptor.writeAll(frame) }", "", mode="stmt"),
    Mutant("marknotcounted", L, "state.byteCount += frame.count", "", mode="stmt"),
    Mutant("acknowledgementignored", L, "state.segments[segment].acknowledged[index] = true", "", mode="stmt"),
    Mutant("pendingnotdecremented", L, "state.segments[segment].pendingCount -= 1", "", mode="stmt"),
    Mutant("acknowledgedtwice", L, "guard !state.segments[segment].acknowledged[index] else { continue }", "", mode="stmt"),
    Mutant("deliverednotdeleted", L, "Self.delete(segment, from: &state, reports: &reports)", "", mode="stmt"),
    # The third `state.hasActive = false`, after append's failure path and makeRoom's roll.
    Mutant("deletedactivekept", L, "state.hasActive = false", "", mode="stmt", nth=2),
    Mutant("groupslosefollowers", L, "groups[last].1.append(index)", "", mode="stmt"),
    Mutant("groupsloseothers", L, "groups[group].1.append(index)", "", mode="stmt"),
    # Recovery.
    Mutant("recovereduntagged", L, "record.deliveryTag = DeliveryTag(acknowledger: self, position: recovered.position)", "", mode="stmt"),
    Mutant("recoveredtakentwice", L, "state.recovered = []", "", mode="stmt"),
    Mutant("redeliveryignored", L, "record.isRedelivered = contents.marked.contains(frame.index)", "", mode="stmt"),
    Mutant("nottruncated", L, "try withErrno { try descriptor.resize(to: Int64(contents.validByteCount)) }", "", mode="stmt"),
    Mutant("corruptionnotreported", L, "reports.append(.corruption(byteCount: bytes.count - contents.validByteCount))", "", mode="stmt"),
    Mutant("unreadablereportedempty", L, "!bytes.isEmpty", "true"),
    Mutant("unreadablekept", L, "try path.removeFile()", "", mode="stmt", nth=0),
    Mutant("deliveredsegmentkept", L, "try path.removeFile()", "", mode="stmt", nth=1),
    Mutant("recoveryunbounded", L, "recovered.state.byteCount > byteBound", "false"),
    Mutant("numberingrestarts", L, "(numbers.last ?? 0) + 1", "1"),
    Mutant("undecodablenotreported", L, "reports.append(.undecodable(recordCount: undecodable))", "", mode="stmt"),
    Mutant("shortfilenames", L, 'String(repeating: "0", count: 20 - digits.count)', 'String(repeating: "0", count: 19 - digits.count)'),
    Mutant("anyfilename", L, 'guard name.hasSuffix(".segment") else { return nil }', "", mode="stmt"),
    # The store.
    Mutant("defaultbound", S, "5 * 1024 * 1024", "5 * 1000 * 1000"),
    Mutant("defaultsegment", S, "max(byteBound / 8, 1)", "max(byteBound / 4, 1)"),
    Mutant("boundatheaderallowed", S, "byteBound > SegmentFormat.header.count", "byteBound >= SegmentFormat.header.count"),
    Mutant("zerosegmentallowed", S, "$0 > 0", "$0 >= 0"),
    Mutant("duplicatenamesallowed", R, 'precondition(byName[registration.name] == nil || byType[ObjectIdentifier(type)] != nil, "Two persisted event types share the name \\(registration.name): register one type per event name, and raise its Event.schemaVersion for a new shape rather than keeping the old type beside it")', "", mode="stmt"),
    Mutant("repeatedtypetraps", R, "byName[registration.name] == nil || byType[ObjectIdentifier(type)] != nil", "byName[registration.name] == nil"),
    Mutant("notfoundbyname", R, "byName[registration.name] = registration", "", mode="stmt"),
    # The binary encoding.
    Mutant("headwidth", E, "initial | 25", "initial | 26"),
    Mutant("truebyte", C, "self ? BinarySimpleValue.true : BinarySimpleValue.false", "self ? BinarySimpleValue.false : BinarySimpleValue.true"),
    Mutant("nullbyte", C, "encoder.write(BinarySimpleValue.null)", "encoder.write(BinarySimpleValue.undefined)", mode="stmt"),
    Mutant("arraycount", C, "encoder.writeHead(.array, count: count)", "encoder.writeHead(.array, count: count + 1)", mode="stmt"),
    Mutant("datesince1970", C, "encoder.encode(timeIntervalSinceReferenceDate)", "encoder.encode(timeIntervalSince1970)", mode="stmt"),
    Mutant("doubleswapped", C, "encoder.writeBigEndian(bitPattern)", "encoder.writeBigEndian(bitPattern.byteSwapped)", mode="stmt", nth=0),
    Mutant("writebigendian", E, "value.littleEndian", "value.bigEndian", nth=0),
    Mutant("readbigendian", D, "Integer(bigEndian: raw.loadUnaligned(fromByteOffset: start - bytes.startIndex, as: Integer.self))", "Integer(littleEndian: raw.loadUnaligned(fromByteOffset: start - bytes.startIndex, as: Integer.self))"),
    # Maps: each key found by its name, in place or by a search, entries never read skipped.
    Mutant("keyprefixmatches", D, "guard key.count == count else { return .different(end: end) }", "guard key.count <= count else { return .different(end: end) }", mode="stmt"),
    Mutant("keybytesnotcompared", D, "key[index] != buffer[cursor + index]", "false"),
    Mutant("keynotwritten", KE, "encoder.writeKey(key)", "", mode="stmt", nth=0),
    Mutant("entrynotcounted", KE, "count += 1", "", mode="stmt", nth=0),
    Mutant("mapcountnotpatched", E, "storage[start] |= UInt8(map.count)", "", mode="stmt"),
    Mutant("mapheadnotwidened", E, "map.count < 24", "map.count <= 24"),
    Mutant("outofplacenotsearched", K, "return try search(key)", "return false", mode="stmt"),
    Mutant("missnotrestored", K, "decoder.position = position", "", mode="stmt", nth=1),
    # The second copy is decodeValue's; decoder(forKey:)'s, the first, serves only a record's
    # event, its last key read, so leaving it out changes nothing a caller sees.
    Mutant("readnotadvanced", K, "nextIndex += 1", "", mode="stmt", nth=1),
    Mutant("searchindexlost", K, "nextIndex = index", "nextIndex = 0", mode="stmt"),
    Mutant("mapnotskipped", D, "try skip(itemCount: 2 * count)", "try skip(itemCount: count)", mode="stmt"),
    Mutant("skipstringnotpassed", D, "cursor += Int(argument)", "", mode="stmt"),
    Mutant("skiparrayflat", D, "remaining += Int(argument)", "", mode="stmt"),
    Mutant("skipmaphalf", D, "remaining += 2 * Int(argument)", "remaining += Int(argument)", mode="stmt"),
    Mutant("skiptagalone", D, "remaining += 1", "", mode="stmt"),
    Mutant("pendingnotcounted", D, "max(buffer.count - cursor - remaining, 0)", "buffer.count - cursor"),
    Mutant("skipargumentbytes", D, "argument = argument << 8 | UInt64(buffer[index])", "argument = UInt64(buffer[index])", mode="stmt", nth=0),
    # A missing optional reads nil; a value of another type throws, so its record is dropped.
    Mutant("missingoptionalthrows", K, "guard try find(key) else { return nil }", "guard try find(key) else { throw .keyNotFound }", mode="stmt", nth=0),
    Mutant("nullnotnil", C, "self = .none", "self = .some(try decoder.decode())", mode="stmt"),
    Mutant("nestednotwrapped", C, "encoder.storage[start] == BinarySimpleValue.null", "false"),
    Mutant("arraynotwrapped", C, "encoder.storage[start] == Self.wrapperHead", "false"),
    Mutant("typenotchecked", D, "guard head.majorType == majorType else { throw .typeMismatch }", "", mode="stmt"),
    Mutant("mismatchreadaszero", C, "throw .typeMismatch", "self = Self.zero", mode="stmt", nth=0),
    Mutant("unsignedtakesnegative", C, "Self.isSigned", "true"),
    Mutant("readunchecked", D, "guard count <= remainingCount else { throw .endOfData }", "", mode="stmt", nth=0),
    Mutant("endbeforeend", D, "position == bytes.endIndex", "position >= bytes.endIndex - 1"),
    # Delivery's acknowledgement, in Destinations.
    Mutant("neveracknowledged", "Deliver.swift", "delivery.acknowledgement?.received()", "", mode="stmt", module="Destinations"),
    Mutant("acknowledgedwhencancelled", "Deliver.swift", "guard !Task.isCancelled else { return }", "", mode="stmt", module="Destinations"),
    Mutant("nowilldeliver", "Deliver.swift", "store.acknowledger.willDeliver(store.positions)", "Set<UInt64>()", module="Destinations"),
    Mutant("withheldsent", "Deliver.swift", "return !held.contains(tag.position)", "return true", mode="stmt", module="Destinations"),
    Mutant("emptybatchsent", "Deliver.swift", "guard !delivered.isEmpty else { return nil }", "", mode="stmt", module="Destinations"),
    Mutant("firstdestinationacknowledges", "Deliver.swift", "remaining = Mutex(destinationCount)", "remaining = Mutex(1)", mode="stmt", module="Destinations"),
    Mutant("nodestinationswait", "Deliver.swift", "destinationCount == 0", "destinationCount == -1", module="Destinations"),
    # Write-through, in Trackers.
    Mutant("storeignored", "RecordSink.swift", "subscription.send(store.append(record))", "subscription.send(record)", mode="stmt", module="Trackers"),
    # The worker's recovered records.
    Mutant("recoverednotsent", "Worker.swift", "admit(admitted, statuses: statuses)", "", mode="stmt", module="Trackers"),
    Mutant("recoverednotgated", "Worker.swift", "admit(admitted, statuses: statuses)", "admitted.forEach(sink.send)", mode="stmt", module="Trackers"),
    Mutant("recoveredredacted", "Worker.swift", "store.takeRecoveredRecords().map(\\.revealingSensitiveValues)", "store.takeRecoveredRecords()", module="Trackers"),
    Mutant("recoveredwrittenagain", "RecordSink.swift", "record.deliveryTag == nil", "true", module="Trackers"),
    # Consent's gating of a store's records, in Trackers.
    Mutant("droppednotforgotten", "Worker.swift", "store.acknowledger.acknowledge(store.positions)", "", mode="stmt", module="Trackers"),
    Mutant("recovereddeniednotreported", "Worker.swift", "denied.add(record)", "", mode="stmt", module="Trackers"),
    Mutant("helddeniednotforgotten", "Worker.swift", "forget(released)", "", mode="stmt", module="Trackers"),
    # The first is leave's, a substring of the hold's after it; leave's first, as the hold's
    # mutant rewrites the text.
    Mutant("finishreportsstored", "ConsentGate.swift", "record.deliveryTag == nil", "true", nth=0, module="Trackers"),
    Mutant("recoveredbounded", "ConsentGate.swift", "held.record.deliveryTag == nil", "true", module="Trackers"),
    Mutant("storedcountzero", "ConsentGate.swift", "$0.stored.count", "0", module="Trackers"),
    # The first is the recovered records'; the second, the hold's, is in Trackers.py.
    Mutant("takesotherstrackersstored", "ConsentGate.swift", "guard held.member == member, isTaken(held.record) else { return false }", "guard isTaken(held.record) else { return false }", mode="stmt", nth=0, module="Trackers"),
    # Sensitive values: only a store's coders write and read them.
    Mutant("ownencoderwrites", E, "self.init(writingSensitiveValues: false)", "self.init(writingSensitiveValues: true)", mode="stmt"),
    Mutant("owndecoderreads", D, "self.init(bytes, readingSensitiveValues: false)", "self.init(bytes, readingSensitiveValues: true)", mode="stmt"),
    Mutant("sensitivewrittenanyway", C, "encoder.writesSensitiveValues", "true"),
    # nullbyte, in Optional's encoding above Sensitive's, writes the same text first.
    Mutant("redactednotundefined", C, "encoder.write(BinarySimpleValue.undefined)", "", mode="stmt", nth=1),
    Mutant("sensitivereadanyway", C, "guard decoder.readsSensitiveValues else { throw .invalidValue }", "", mode="stmt"),
    Mutant("segmentwritesnosensitive", E, "writesSensitiveValues = true", "writesSensitiveValues = false", mode="stmt"),
    Mutant("storewritesnosensitive", N, "BinaryEncoder(writingSensitiveValues: true)", "BinaryEncoder(writingSensitiveValues: false)"),
    Mutant("storereadsnosensitive", N, "BinaryDecoder(bytes, readingSensitiveValues: true)", "BinaryDecoder(bytes, readingSensitiveValues: false)"),
    # A record's missing call site.
    Mutant("callsitenotdecoded", N, 'try map.decode(forKey: "sourceLocation")', "StoredSourceLocation?.none"),
    # Sensitive's encoding; the first copy is Optional's.
    Mutant("sensitivenotwritten", C, "encoder.encode(value)", "", mode="stmt", nth=1),
    # Refined's encoding: its value as it is, checked again as it is read.
    Mutant("refinednotwritten", C, "encoder.encode(value)", "", mode="stmt", nth=2),
    Mutant("refinedwrongerror", C, ".invalidValue", "BinaryDecodingError.endOfData", nth=5),
    # A recovered record a constraint added since rejects: dropped and forgotten by the store.
    Mutant("recoveredrejectedadmitted", "Worker.swift", "rejected.append(record)", "admitted.append(record)", mode="stmt", module="Trackers"),
    Mutant("recoveredrejectedkept", "Worker.swift", "forget(rejected)", "", mode="stmt", module="Trackers"),
    # The record's schema version (TRAF-18): written with it, checked before its event is read, and
    # each mismatch reported by event and version.
    Mutant("versionnotwritten", N, 'map.encode(registration.version, forKey: "version")', "", mode="stmt"),
    # A record without a version is read by name: defaulting it to 1 would drop it at version 2.
    Mutant("versionmissingmismatches", N, 'try map.decode(forKey: "version")', 'try map.decode(forKey: "version", default: 1)'),
    Mutant("versionnotchecked", N, "version != registration.version", "false"),
    Mutant("mismatchversionsswapped", N, ".versionMismatch(event: name, storedVersion: version, currentVersion: registration.version)", ".versionMismatch(event: name, storedVersion: registration.version, currentVersion: version)"),
    Mutant("registryversionfixed", R, "E.schemaVersion", "1"),
    Mutant("mismatchnotcounted", L, "mismatches.add(event: event, storedVersion: storedVersion, currentVersion: currentVersion)", "", mode="stmt"),
    Mutant("mismatchnotreported", L, "reports += mismatches.reports", "", mode="stmt"),
    Mutant("mismatchcountdoubled", V, "counts[Key(event: event, storedVersion: storedVersion, currentVersion: currentVersion), default: 0] += 1", "counts[Key(event: event, storedVersion: storedVersion, currentVersion: currentVersion), default: 0] += 2", mode="stmt"),
    Mutant("mismatchnameorderreversed", V, "event.utf8.lexicographicallyPrecedes(other.event.utf8)", "other.event.utf8.lexicographicallyPrecedes(event.utf8)"),
    Mutant("mismatchversionorderreversed", V, "storedVersion < other.storedVersion", "storedVersion > other.storedVersion"),
    Mutant("mismatchcurrentisstored", V, "key.currentVersion", "key.storedVersion"),
    Mutant("defaultalways", K, "        guard try find(key) else { return defaultValue }", "        return defaultValue", mode="stmt"),
    # The encoder's storage (TRAF-45): bytes written into room kept past them, which grows by
    # copying them, and is cut off where the bytes end.
    Mutant("roomnotcopied", E, "base.copyMemory(from: old.baseAddress.unsafelyUnwrapped, byteCount: written)", "", mode="stmt"),
    Mutant("writtennotcounted", E, "byteCount += count", "", mode="stmt"),
    Mutant("widennotcounted", E, "byteCount += head.byteCount - 1", "", mode="stmt"),
    Mutant("insertnotcounted", E, "        byteCount += 1", "", mode="stmt"),
    Mutant("bytesuntrimmed", E, "byteCount == storage.count ? storage : Array(storage[..<byteCount])", "storage"),
    Mutant("takenuntrimmed", E, "bytes.removeLast(bytes.count - byteCount)", "", mode="stmt"),
    Mutant("sealedwithroom", E, "UnsafeMutableRawBufferPointer(rebasing: $0[..<count])", "$0"),
    Mutant("shorttextlimit", E, "utf8.count < 24", "utf8.count <= 24"),
    Mutant("shorttexthead", E, "BinaryMajorType.textString.initialByte | UInt8(utf8.count)", "BinaryMajorType.byteString.initialByte | UInt8(utf8.count)"),
    Mutant("textwrittentwice", C, "written == nil", "true"),
    Mutant("asciiassumed", C, "utf8.allSatisfy({ $0 < 0x80 })", "true"),
    Mutant("nonasciirejected", C, "            guard let string = String(validating: utf8, as: UTF8.self) else { return nil }\n            self = string", "            return nil", mode="stmt"),
    Mutant("absentlocationnotwritten", N, 'map.encode(StoredSourceLocation?.none, forKey: "sourceLocation")', "", mode="stmt"),
    Mutant("framewrittenwithroom", F, "UnsafeRawBufferPointer(rebasing: bytes[..<byteCount])", "bytes"),
    Mutant("partialwriteaccepted", "FileSystem.swift", "        while written < bytes.count {\n            written += try withErrno { try write(UnsafeRawBufferPointer(rebasing: bytes[written...])) }\n        }", "        written += try withErrno { try write(UnsafeRawBufferPointer(rebasing: bytes[written...])) }", mode="stmt"),
    # Recovery's rewrite of a segment it drops records from (TRAF-47).
    Mutant("dropsnotrewritten", L, "keptFrames.count < contents.records.count", "keptFrames.count < 0"),
    Mutant("rewritemarksdropped", L, "SegmentFormat.compacted(bytes, keeping: frames, marking: marked)", "SegmentFormat.compacted(bytes, keeping: frames, marking: [])"),
    Mutant("rewritemarksinverted", L, "records[$0].record.isRedelivered", "!records[$0].record.isRedelivered"),
    Mutant("compactedframestart", F, "frame.payload.lowerBound - 1 - frameHeaderByteCount", "frame.payload.lowerBound - frameHeaderByteCount"),
    Mutant("compactednomark", F, "!marked.isEmpty", "marked.isEmpty"),
    Mutant("rewritenotrenamed", L, "try temporary.rename(to: segment.file.path)", "", mode="stmt"),
    Mutant("rewritekeepsolddescriptor", L, "file = SegmentFile(path: segment.file.path, descriptor: descriptor)", "file = segment.file", mode="stmt"),
    Mutant("rewritebytecount", L, "compacted.count", "segment.byteCount"),
    Mutant("rewriteoldpositions", L, "Recovered(record: records[index].record, position: segment.number << 32 | UInt64(index))", "records[index]"),
    Mutant("rewriteacknowledged", L, "Array(repeating: false, count: records.count)", "Array(repeating: true, count: records.count)"),
    Mutant("rewritetimestamps", L, "records.map(\\.record.timestamp)", "records.map { _ in Date.distantPast }"),
    Mutant("interruptedrewritekept", L, "try directory.appending(name).removeFile()", "", mode="stmt"),
    Mutant("renamenoop", "FileSystem.swift", "destination.withPlatformString { renameFile(source, $0) }", "0"),
]
