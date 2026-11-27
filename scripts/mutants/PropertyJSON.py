# Planted bugs for PropertyJSON; run with `just mutate PropertyJSON`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/PropertyJSON/<file> (or `nth=` picks one), and mode="stmt" replaces whole statements
# rather than an expression. Every mutant must be caught; one that survives needs a test, or a note
# here saying why it is equivalent.
#
# The reader came from CollectorEncoding, whose tests still pin most of its cases through the
# collector's format, so they are among TESTS beside the module's own and PostHog's.
#
# Known equivalent mutants (left out, as they would survive by design):
# - The byte-string, other-tag and undefined arms of `anyValue()`: no standard type's `Encodable`
#   conformance writes them through the CBOR package, so no test can reach them.
#
# Left out because a mutant switch can't hold them: the guards that bind the map's entries and
# each key's name (`case .map(let entries)`, `case .textString(let name)`), whose bindings the
# code after them needs. NotAMap's tests in CollectorEncodingTests and PostHogEncodingTests pin the
# first.

TESTS = ["PropertyJSONTests", "CollectorEncodingTests", "PostHogEncodingTests", "DestinationTestingTests"]

S = "EventSchema+PropertyTypes.swift"
R = "EventRecord+Properties.swift"
P = "CBORPropertyReader.swift"
D = "Date+Timestamps.swift"
READER = "PropertyReader.swift"
LIMIT = "BatchLimit.swift"
SPLIT = "BatchLimit+Requests.swift"
ENVELOPE = "JSONEnvelope.swift"
FLAT = "Dictionary+Flattened.swift"
IDENTITY = "EventRecord+Identity.swift"
CONTEXT = "EventRecord+StandardContext.swift"

MUTANTS = [
    Mutant("optionalignored", "EventSchema+PropertyTypes.swift", 'guard property.isOptional else { return (property.name, type) }', 'return (property.name, type)', mode="stmt"),
    # The first copy is the doc comment's, the second the parameter's, the third the encoding's.
    Mutant("alwayswrites", R, "writingSensitiveValues", "true", nth=2),
    Mutant("neverwrites", R, "writingSensitiveValues", "false", nth=2),
    Mutant("readernotredacting", R, "!writingSensitiveValues", "false"),
    Mutant("encodingfailurepropagates", R, "throw .unrepresentableValue(event: name, property: \"\")", "throw .notEncodable(name: name)", mode="stmt"),
    # Properties.
    Mutant("redactedpropertynull", P, "members[name] = try json(value, as: types[name] ?? nil)", "members[name] = try json(value, as: types[name] ?? nil) ?? .null", mode="stmt"),
    Mutant("missingoptionalnotnull", P, "                members[name] = .null", "", mode="stmt"),
    Mutant("unparsedoptionalnotoptional", "EventSchema+PropertyTypes.swift", 'return (property.name, .optional(type ?? .named([property.typeName], [])))', 'return (property.name, type.map(WrittenType.optional))', mode="stmt"),
    Mutant("presentoptionalnulled", P, "entries[.textString(name)] == nil", "true"),
    Mutant("redactedoptionalnull", P, "if redactsSensitiveValues, case .sensitive = wrapped.shape { return nil }", "", mode="stmt"),
    Mutant("sensitivenotredacted", P, "guard !redactsSensitiveValues else { return nil }", "", mode="stmt"),
    Mutant("redactedelementdropped", P, "elements.append(try json(item, as: element) ?? .null)", "if let element = try json(item, as: element) { elements.append(element) }", mode="stmt"),
    Mutant("datesince1970", P, "date = Date(timeIntervalSinceReferenceDate: seconds)", "date = Date(timeIntervalSince1970: seconds)", mode="stmt"),
    # After datesince1970, its text occurs twice; the second is the original's.
    Mutant("tagdatesince2001", P, "date = Date(timeIntervalSince1970: seconds)", "date = Date(timeIntervalSinceReferenceDate: seconds)", mode="stmt", nth=1),
    # The second copy is anyValue()'s, for a Date in a type the plan can't map.
    Mutant("nesteddateunread", P, "return try .string(Self.date(value).iso8601Timestamp)", "throw Unrepresentable()", mode="stmt", nth=1),
    Mutant("dateasnumber", P, 'if names("Date", in: ["Foundation", "FoundationEssentials"])?.isEmpty == true { return .date }', "", mode="stmt"),
    Mutant("unqualifieddateonly", P, '["Foundation", "FoundationEssentials"]', '["FoundationEssentials"]'),
    Mutant("refinedopaque", P, 'if let arguments = names("Refined", in: ["Events", "Traffluent"]), arguments.count == 2 { return .refined(arguments[0]) }', "", mode="stmt"),
    Mutant("sensitiveopaque", P, 'if let arguments = names("Sensitive", in: ["Events", "Traffluent"]), arguments.count == 1 { return .sensitive(arguments[0]) }', "", mode="stmt"),
    Mutant("floatwidened", P, "Double(number.description)", "Optional(Double(number))"),
    Mutant("negativeoffbyone", P, "~$0", "-$0"),
    Mutant("largeunsignedclamped", P, ".number(Double(magnitude))", ".number(Double(UInt64(Int64.max)))"),
    # The guard binds the number, so a non-finite one becomes null rather than the guard dropped.
    Mutant("nonfiniteaccepted", P, "JSON.number(exactly: number)", "Optional(JSON.number(exactly: number) ?? .null)"),
    Mutant("nonfinitedateaccepted", P, "guard date.timeIntervalSinceReferenceDate.isFinite else { throw Unrepresentable() }", "", mode="stmt"),
    # The public reader.
    Mutant("readerignoresreveal", READER, "includingSensitiveValues && record.revealsSensitiveValues", "includingSensitiveValues"),
    Mutant("readerignoresrequest", READER, "includingSensitiveValues && record.revealsSensitiveValues", "record.revealsSensitiveValues"),
    Mutant("readerignoresversion", READER, "EventVersion(name: record.name, version: type(of: record.event).schemaVersion)", "EventVersion(name: record.name, version: 1)"),
    # Timestamps.
    # Foundation's ISO 8601 style, whose default Gregorian calendar turns Julian before 1582-10-15.
    Mutant("defaultcalendar", D, "String(decoding: text, as: UTF8.self)", "formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))"),
    Mutant("clampsswapped", D, "timeIntervalSince1970 > 0 ? .max : .min", "timeIntervalSince1970 > 0 ? .min : .max"),
    Mutant("remaindernotfloored", D, "remainder < 0 ? (quotient - 1, remainder + divisor) : (quotient, remainder)", "(quotient, remainder)"),
    Mutant("eratruncated", D, "shifted >= 0 ? shifted : shifted - 146_096", "shifted"),
    Mutant("nocenturyrule", D, "dayOfEra / 36_524", "0"),
    Mutant("februaryinyear", D, "month <= 2 ? 1 : 0", "month < 2 ? 1 : 0"),
    Mutant("nominussign", D, 'text.append(UInt8(ascii: "-"))', "", mode="stmt", nth=0),
    Mutant("yearunpadded", D, "text.appendDecimal(date.year.magnitude, digits: 4)", "text.appendDecimal(date.year.magnitude, digits: 1)", mode="stmt"),
    Mutant("longyearcut", D, "Swift.max(digits, count)", "digits"),
    Mutant("millisecondsrounded", D, "(timeIntervalSince1970 * 1000).rounded(.down)", "(timeIntervalSince1970 * 1000).rounded()"),
    Mutant("millisecondstruncated", D, "(timeIntervalSince1970 * 1000).rounded(.down)", "(timeIntervalSince1970 * 1000).rounded(.towardZero)"),
    Mutant("millisecondsasseconds", D, "(timeIntervalSince1970 * 1000).rounded(.down)", "timeIntervalSince1970.rounded(.down)"),
    # Identity.
    Mutant("identityalwaysrecord", IDENTITY, "context[SessionKey.self]", "context[SessionKey.self].flatMap { _ in Optional<SessionKey.Value>.none }"),
    Mutant("deduplicationuppercase", IDENTITY, "id.uuidString.lowercased()", "id.uuidString"),
    # Limits.
    Mutant("limitallowszerocount", LIMIT, "maximumRecordCount >= 1", "maximumRecordCount >= 0"),
    Mutant("limitallowszerobytes", LIMIT, "maximumByteCount >= 1", "maximumByteCount >= 0"),
    Mutant("limitallowszerorecordbytes", LIMIT, "maximumRecordByteCount >= 1", "maximumRecordByteCount >= 0"),
    # Envelope.
    Mutant("envelopeunsorted", ENVELOPE, "$0.key.utf8.lexicographicallyPrecedes(arrayMember.utf8)", "true"),
    Mutant("envelopebytesprefixonly", ENVELOPE, "prefix.utf8.count + suffix.utf8.count", "prefix.utf8.count"),
    # Re-planted from PostHog's spec, where these lived before the envelope, identity and skipped
    # records moved here.
    Mutant("envelopeafterunfiltered", ENVELOPE, "arrayMember.utf8.lexicographicallyPrecedes($0.key.utf8)", "true"),
    Mutant("textcontenttype", ENVELOPE, '"application/json"', '"text/plain"'),
    Mutant("freshfallback", IDENTITY, "return .record(id)", "return .record(type(of: id).init())", mode="stmt"),
    Mutant("skipversionignored", SPLIT, "type(of: record.event).schemaVersion", "1"),
    # Splitting.
    Mutant("splitcountoffbyone", SPLIT, "elements.count < limit.maximumRecordCount", "elements.count <= limit.maximumRecordCount"),
    Mutant("splitbytesoffbyone", SPLIT, "recordByteCount < limit.maximumByteCount - byteCount", "recordByteCount <= limit.maximumByteCount - byteCount"),
    Mutant("splitnocomma", SPLIT, "elements.isEmpty ? recordByteCount : recordByteCount + 1", "recordByteCount"),
    # Before splitignoresenvelope, whose text this holds.
    Mutant("splitignoresrecordlimit", SPLIT, "Swift.min(maximumRecordByteCount, maximumByteCount - envelope.byteCount)", "maximumByteCount - envelope.byteCount"),
    # The second copy is the original's, after splitignoresrecordlimit's.
    Mutant("splitignoresenvelope", SPLIT, "maximumByteCount - envelope.byteCount", "maximumByteCount", nth=1),
    Mutant("splitoversizedatlimit", SPLIT, "byteCount <= recordCapacity", "byteCount < recordCapacity"),
    Mutant("splitlastrequestdropped", SPLIT, "        flush()\n        return requests", "        return requests", mode="stmt"),
    Mutant("splitfailurenotreported", SPLIT, "skippedRecords.append(SkippedRecord(record, reason: error))", "", mode="stmt"),
    # Flattening.
    Mutant("flattencollisionreplaces", FLAT, "            guard flattened.updateValue(self, forKey: key) == nil else {\n                throw FlattenedKeyCollision(key: key)\n            }", "flattened[key] = self", mode="stmt"),
    Mutant("flattenseparatorignored", FLAT, "name.map { $0 + separator + key } ?? key", "name.map { $0 + \".\" + key } ?? key"),
    Mutant("flattenarrayfromone", FLAT, "String(offset)", "String(offset + 1)", nth=0),
    # Standard context.
    Mutant("contextnolocale", CONTEXT, 'members["locale"] = .string(locale.identifier(.bcp47))', "", mode="stmt"),
    Mutant("contextlocaleunderscore", CONTEXT, "locale.identifier(.bcp47)", "locale.identifier"),
    Mutant("contextnilapplicationnull", CONTEXT, "application.bundleIdentifier.map(JSON.string)", "Optional(application.bundleIdentifier.map(JSON.string) ?? .null)"),
    Mutant("contextpadasphone", CONTEXT, '"pad"', '"phone"'),
    Mutant("contextofflineasother", CONTEXT, '"offline"', '"other"'),
]
