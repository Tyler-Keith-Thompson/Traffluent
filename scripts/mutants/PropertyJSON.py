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
# - BatchLimit's `sendsLargeRecordsAlone ? ... : Swift.min(...)` always taking the min: the same
#   as largealonenever's, which plants a limit that never sends alone. Its init's default of `false`
#   can't be planted (a default argument isn't a statement or a switchable expression);
#   largeRecordLeftOutByDefault pins it, and `unlimited` (largealonealways) the private init.
# - The writer's `elements.reserveCapacity(items.count)` removed: capacity only.
# - DecodingError's keyNotFound arm reading `key.stringValue` alone: the coding path is empty for a
#   property of the event itself, and the CBOR writer makes every nested value of a type the plan
#   maps, so only a type of the app's own could tell them apart.
# - The ISO 8601 parser's 12-digit cap on a year raised: a 13-digit year's day count overflows no
#   Int128, and its millisecond count, past Int64, is refused all the same.
#
# Left out because a mutant switch can't hold them: the guards that bind the map's entries and
# each key's name (`case .map(let entries)`, `case .textString(let name)`), whose bindings the
# code after them needs. NotAMap's tests in CollectorEncodingTests and PostHogEncodingTests pin the
# first. And the month lengths' `case` patterns in CivilDate.daysInMonth; the thirty-day months are
# pinned by the 04-31, 06-31, 09-31 and 11-31 cases of CollectorTimestampDecodingTests.

TESTS = ["PropertyJSONTests", "CollectorEncodingTests", "PostHogEncodingTests", "DestinationTestingTests"]

S = "EventSchema+PropertyTypes.swift"
R = "EventRecord+Properties.swift"
P = "CBORPropertyReader.swift"
SHAPE = "WrittenType+Shape.swift"
WRITER = "CBORPropertyWriter.swift"
EVENT = "Event+Properties.swift"
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
    Mutant("nesteddateunread", P, "return try .string(Self.timestamp(value))", "throw Unrepresentable()", mode="stmt", nth=1),
    Mutant("dateasnumber", SHAPE, 'if names("Date", in: ["Foundation", "FoundationEssentials"])?.isEmpty == true { return .date }', "", mode="stmt"),
    Mutant("unqualifieddateonly", SHAPE, '["Foundation", "FoundationEssentials"]', '["FoundationEssentials"]'),
    Mutant("refinedopaque", SHAPE, 'if let arguments = names("Refined", in: ["Events", "Traffluent"]), arguments.count == 2 { return .refined(arguments[0]) }', "", mode="stmt"),
    Mutant("sensitiveopaque", SHAPE, 'if let arguments = names("Sensitive", in: ["Events", "Traffluent"]), arguments.count == 1 { return .sensitive(arguments[0]) }', "", mode="stmt"),
    Mutant("floatwidened", P, "Double(number.description)", "Optional(Double(number))"),
    Mutant("negativeoffbyone", P, "~$0", "-$0"),
    Mutant("largeunsignedclamped", P, ".number(Double(magnitude))", ".number(Double(UInt64(Int64.max)))"),
    # The guard binds the number, so a non-finite one becomes null rather than the guard dropped.
    Mutant("nonfiniteaccepted", P, "JSON.number(exactly: number)", "Optional(JSON.number(exactly: number) ?? .null)"),
    # A date with no timestamp written as an empty string rather than rejected.
    Mutant("unrepresentabledateblank", P, "return try date.iso8601Timestamp", 'return (try? date.iso8601Timestamp) ?? ""', mode="stmt"),
    # The public reader.
    Mutant("readerignoresreveal", READER, "includingSensitiveValues && record.revealsSensitiveValues", "includingSensitiveValues"),
    Mutant("readerignoresrequest", READER, "includingSensitiveValues && record.revealsSensitiveValues", "record.revealsSensitiveValues"),
    Mutant("readerignoresversion", READER, "EventVersion(name: record.name, version: type(of: record.event).schemaVersion)", "EventVersion(name: record.name, version: 1)"),
    # Timestamps.
    # Foundation's ISO 8601 style, whose default Gregorian calendar turns Julian before 1582-10-15.
    Mutant("defaultcalendar", D, "String(decoding: text, as: UTF8.self)", "formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))"),
    # The epoch in place of a date with no millisecond count, rather than throwing.
    # The second copy is iso8601Timestamp's call, after its doc comment's.
    Mutant("timestampnotthrowing", D, "millisecondsSince1970()", "Int64(0)", nth=1),
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
    Mutant("largealonenever", LIMIT, "self.sendsLargeRecordsAlone = sendsLargeRecordsAlone", "self.sendsLargeRecordsAlone = false", mode="stmt"),
    Mutant("largealonealways", LIMIT, "self.sendsLargeRecordsAlone = sendsLargeRecordsAlone", "self.sendsLargeRecordsAlone = true", mode="stmt"),
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
    # A large record sent alone whatever the limit says; before splitignoresrecordlimit, whose text
    # this holds too.
    Mutant("splitignoresrequestlimit", SPLIT, "Swift.min(maximumRecordByteCount, maximumByteCount - envelope.byteCount)", "maximumRecordByteCount"),
    # Before splitignoresenvelope, whose text this holds.
    Mutant("splitignoresrecordlimit", SPLIT, "Swift.min(maximumRecordByteCount, maximumByteCount - envelope.byteCount)", "maximumByteCount - envelope.byteCount"),
    # The second copy is the original's, after splitignoresrecordlimit's.
    Mutant("splitignoresenvelope", SPLIT, "maximumByteCount - envelope.byteCount", "maximumByteCount", nth=1),
    Mutant("splitoversizedatlimit", SPLIT, "byteCount <= recordCapacity", "byteCount < recordCapacity"),
    Mutant("splitlastrequestdropped", SPLIT, "        flush()\n        return requests", "        return requests", mode="stmt"),
    Mutant("splitfailurenotreported", SPLIT, "skippedRecords.append(SkippedRecord(record, reason: error))", "", mode="stmt"),
    # Deadlines (TRAF-134).
    Mutant("splitagenotpassed", SPLIT, "RequestBuilder(limit: self, envelope: envelope, maximumAge: maximumAge)", "RequestBuilder(limit: self, envelope: envelope, maximumAge: nil)"),
    Mutant("splitdeadlinefirstrecord", SPLIT, "Swift.min($0, timestamp)", "$0"),
    Mutant("splitdeadlinelatestrecord", SPLIT, "Swift.min($0, timestamp)", "Swift.max($0, timestamp)"),
    Mutant("splitdeadlinecarried", SPLIT, "oldest = nil", "", mode="stmt"),
    Mutant("splitdeadlinewithoutage", SPLIT, "$0.addingTimeInterval(maximumAge)", "$0"),
    Mutant("splitzeroagethrows", SPLIT, "maximumAge >= .zero", "maximumAge > .zero"),
    Mutant("splitnegativeageaccepted", SPLIT, "maximumAge >= .zero", "true"),
    Mutant("splitagewholeseconds", SPLIT, "Double(components.seconds) + Double(components.attoseconds) * 1e-18", "Double(components.seconds)"),
    Mutant("splitnodeadlinespellinghasone", SPLIT, "split(batch, in: envelope, maximumAge: nil, encoding: encoding, oversized: oversized)", "split(batch, in: envelope, maximumAge: 1, encoding: encoding, oversized: oversized)"),
    Mutant("splitnonfinitetimestampignored", SPLIT, "!timestamp.timeIntervalSinceReferenceDate.isFinite", "false"),
    # No mutant drops the check that keeps a NaN oldest time: the standard library's min(x, y) is
    # `y < x ? y : x`, which keeps a NaN x, so the mutant would be equivalent today. The check
    # stays so the deadline doesn't rest on that undocumented order.
    Mutant("splitdeadlinedropped", SPLIT, "requests.append(EncodedRequest(body: envelope.body(of: elements), recordIDs: recordIDs, deadline: deadline))", "requests.append(EncodedRequest(body: envelope.body(of: elements), recordIDs: recordIDs))", mode="stmt"),
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
    # CollectorBatchDecoder's reading of properties and timestamps.
    # PropertyJSON's CBOR writer, which only the decoder reaches.
    Mutant("writerpropertydropped", WRITER, "entries[.textString(name)] = try cbor(value, as: types[name] ?? nil)", "", mode="stmt"),
    Mutant("writerpropertyunnamed", WRITER, "UndecodableProperty(property: name)", 'UndecodableProperty(property: "")'),
    Mutant("writeroptionalunwrapped", WRITER, "guard value != .null else { return .null }", "", mode="stmt"),
    Mutant("writerelementuntyped", WRITER, "elements.append(try cbor(item, as: element))", "elements.append(anyValue(item))", mode="stmt"),
    Mutant("writerdateastext", WRITER, "return .double(date.timeIntervalSinceReferenceDate)", "return .textString(text)", mode="stmt"),
    Mutant("writerfloatuntyped", WRITER, "return .double(number)", "return anyValue(value)", mode="stmt"),
    Mutant("writerzeronegative", WRITER, "integer >= 0", "integer > 0"),
    Mutant("writernegativeoffbyone", WRITER, "UInt64(~integer)", "UInt64(-integer)"),
    Mutant("writerlargeasdouble", WRITER, "UInt64(exactly: number).map(CBOR.unsignedInt) ?? .double(number)", "CBOR.double(number)"),
    Mutant("writerobjectempty", WRITER, "entries[.textString(name)] = anyValue(item)", "", mode="stmt"),
    Mutant("floatuntyped", SHAPE, '["Double", "Float", "Float64", "Float32"]', '["Double"]'),
    Mutant("decodingconcealed", EVENT, "true", "false"),
    Mutant("decodingmissingunnamed", EVENT, "(context.codingPath.first ?? key).stringValue", '""'),
    Mutant("decodingmismatchunnamed", EVENT, 'context.codingPath.first?.stringValue ?? ""', '""'),
    # PropertyJSON's ISO 8601 parser.
    Mutant("parsenegativeignored", D, "isNegative ? -magnitude : magnitude", "magnitude"),
    Mutant("parsenegativezero", D, "!isNegative || magnitude > 0", "true"),
    Mutant("parseleadingzero", D, 'yearDigits == 4 || text[yearStart] != UInt8(ascii: "0")', "true"),
    Mutant("parseshortyear", D, "yearDigits >= 4", "yearDigits >= 3"),
    Mutant("parselengthloose", D, "rest.count == 20", "rest.count >= 20"),
    Mutant("parseseparatorsunchecked", D, "rest[rest.startIndex + offset] != UInt8(ascii: byte)", "false"),
    Mutant("parsedigitsignored", D, 'value * 10 + Int64(digit - UInt8(ascii: "0"))', "value * 10"),
    Mutant("parsemonthunchecked", D, "(1 ... 12).contains(month)", "true"),
    Mutant("parsedaythirtyone", D, "(1 ... date.daysInMonth).contains(day)", "(1 ... 31).contains(day)"),
    Mutant("parsedayzero", D, "(1 ... date.daysInMonth).contains(day)", "(0 ... date.daysInMonth).contains(day)"),
    Mutant("parsehour24", D, "hour < 24", "hour <= 24"),
    Mutant("parseminute60", D, "minute < 60", "minute <= 60"),
    Mutant("parsesecond60", D, "second < 60", "second <= 60"),
    Mutant("parsemillisecondsignored", D, "((hour * 60 + minute) * 60 + second) * 1000 + millisecond", "((hour * 60 + minute) * 60 + second) * 1000"),
    Mutant("leapeveryyear", D, "year % 4 == 0", "true"),
    Mutant("leapcenturies", D, "year % 100 != 0 || year % 400 == 0", "true"),
    Mutant("leapnofourhundred", D, "year % 400 == 0", "false"),
    Mutant("civilmarchyear", D, "month <= 2 ? year - 1 : year", "year"),
    Mutant("civileratruncated", D, "marchYear >= 0 ? marchYear : marchYear - 399", "marchYear"),
    Mutant("civilmonthfrommarch", D, "month > 2 ? month - 3 : month + 9", "month - 3"),
    # The second copy is days_from_civil's; the first civil_from_days'.
    Mutant("civilnocenturyrule", D, "yearOfEra / 100", "0", nth=1),
    # The parse's search for a Date in the millisecond.
    Mutant("parsenearestonly", D, "lowest < milliseconds", "false"),
    Mutant("parsenearestdropped", D, "actual != milliseconds", "false"),
    Mutant("parselowabove", D, "actual < milliseconds ? nearest : nearest - width", "nearest"),
    Mutant("parsehighbelow", D, "actual < milliseconds ? nearest + width : nearest", "nearest"),
    Mutant("parsewidthonems", D, "Swift.max(0.002, 2 * nearest.ulp)", "0.001"),
    Mutant("parsebisectreversed", D, "reached < milliseconds", "reached >= milliseconds"),
    Mutant("parsebisectnone", D, "low.nextUp < high", "false"),
    Mutant("parsereferencefrom1970", D, "Int128(Self.millisecondsBetween1970AndReferenceDate)", "Int128(0)"),
    Mutant("parselastunchecked", D, "guard Self.milliseconds(atReferenceSeconds: high) == milliseconds else { return nil }", "", mode="stmt"),
]
