# Planted bugs for CollectorEncoding; run with `just mutate CollectorEncoding`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/CollectorEncoding/<file> (or `nth=` picks one), and mode="stmt" replaces whole
# statements rather than an expression. `module=` puts a mutant in another module's file: here
# TrackingPlans' JSON.minified, which only this module's body reaches. Every mutant must be caught;
# one that survives needs a test, or a note here saying why it is equivalent.
#
# Known equivalent mutants (left out, as they would survive by design):
# - `records.reserveCapacity(batch.count)` removed: capacity only.
# - The logger.error line in encode(_:) removed: logs are for developers, and tests don't pin them.
# - The byte-string and other-tag arms of `anyValue()`: no public BinaryCodable API writes them,
#   so no test can reach them.

TESTS = ["CollectorEncodingTests"]

B = "CollectorBatchEncoder.swift"
P = "PropertyReader.swift"
C = "EventRecord+CollectorContext.swift"
D = "Date+CollectorTimestamp.swift"

MUTANTS = [
    # The record's envelope.
    Mutant("freshid", B, "record.id.uuidString", "UUID().uuidString"),
    Mutant("neverredelivered", B, "record.isRedelivered", "false"),
    Mutant("textcontenttype", B, '"application/json"', '"text/plain"'),
    Mutant("firstrecorddropped", B, "records.append(try json(of: record))", "if record.id != batch.first?.id { records.append(try json(of: record)) }", mode="stmt"),
    # Skipped records.
    Mutant("skipnotreported", B, "skippedRecords.append(SkippedRecord(recordID: record.id, eventName: record.name, schemaVersion: type(of: record.event).schemaVersion, reason: error))", "", mode="stmt"),
    Mutant("skipversionignored", B, "type(of: record.event).schemaVersion", "1", nth=0),
    Mutant("allskippedsent", B, "!records.isEmpty || batch.isEmpty", "true"),
    Mutant("emptybatchnobody", B, "!records.isEmpty || batch.isEmpty", "!records.isEmpty"),
    Mutant("lastskipthrown", B, "throw encoded.skippedRecords[0].reason", "throw encoded.skippedRecords[encoded.skippedRecords.count - 1].reason", mode="stmt"),
    # The second: json(of:)'s plan lookup, after batch(of:)'s skipped record.
    Mutant("versionignored", B, "type(of: record.event).schemaVersion", "1", nth=1),
    Mutant("optionalignored", B, "property.isOptional ? type.map(WrittenType.optional) : type", "type"),
    Mutant("alwaysreveals", B, "BinaryEncoder(writingSensitiveValues: revealsSensitiveValues)", "BinaryEncoder(writingSensitiveValues: true)"),
    Mutant("neverreveals", B, "BinaryEncoder(writingSensitiveValues: revealsSensitiveValues)", "BinaryEncoder(writingSensitiveValues: false)"),
    Mutant("wholeseconds", D, "true", "false"),
    # Properties.
    Mutant("redactedpropertynull", P, "members[key] = try value(of: types[key] ?? nil)", "members[key] = try value(of: types[key] ?? nil) ?? .null", mode="stmt"),
    Mutant("redactednotchecked", P, """if decoder.peek() == BinarySimpleValue.undefined {
            _ = try decoder.readByte()
            return nil
        }""", "", mode="stmt"),
    # The third readByte() in the file: the one that skips an optional's wrapper.
    Mutant("wrappernotunwrapped", P, "_ = try decoder.readByte()", "", mode="stmt", nth=2),
    # The second `return nil`: anyValue()'s, for a redacted member of a type the plan can't map.
    Mutant("nestedredactednull", P, "return nil", "return .null", mode="stmt", nth=1),
    Mutant("redactedelementdropped", P, "elements.append(try value(of: element) ?? .null)", "if let element = try value(of: element) { elements.append(element) }", mode="stmt"),
    Mutant("dateasnumber", P, 'if names("Date", in: ["Foundation", "FoundationEssentials"])?.isEmpty == true { return .date }', "", mode="stmt"),
    Mutant("unqualifieddateonly", P, '["Foundation", "FoundationEssentials"]', '["FoundationEssentials"]'),
    Mutant("refinedopaque", P, 'if let arguments = names("Refined", in: ["Events", "Traffluent"]), arguments.count == 2 { return .value(arguments[0]) }', "", mode="stmt"),
    Mutant("sensitiveopaque", P, 'if let arguments = names("Sensitive", in: ["Events", "Traffluent"]), arguments.count == 1 { return .value(arguments[0]) }', "", mode="stmt"),
    Mutant("floatwidened", P, "Double(number.description)!", "Double(number)"),
    Mutant("negativeoffbyone", P, "~$0", "-$0"),
    Mutant("largeunsignedclamped", P, "Double(head.argument)", "Double(UInt64(Int64.max))", nth=0),
    Mutant("uuidlowercased", P, "UUID(uuid: uuid).uuidString", "UUID(uuid: uuid).uuidString.lowercased()"),
    Mutant("nonfiniteaccepted", P, "guard number.isFinite else { throw .invalidValue }", "", mode="stmt"),
    Mutant("nonfinitedateaccepted", P, "guard seconds.isFinite else { throw .invalidValue }", "", mode="stmt"),
    Mutant("notamapaccepted", P, "count = try decoder.readCount(of: .map, elementSize: 2)", "count = 0", mode="stmt"),
    # Context.
    Mutant("applicationabbreviated", C, '"application"', '"app"'),
    Mutant("applicationnilasnull", C, "application.build.map(JSON.string)", "Optional.some(application.build.map(JSON.string) ?? JSON.null)"),
    Mutant("padasphone", C, '"pad"', '"phone"'),
    Mutant("ethernetrenamed", C, '"wiredEthernet"', '"ethernet"'),
    Mutant("localeidentifier", C, "locale.identifier(.bcp47)", "locale.identifier"),
    Mutant("nosamplerate", C, 'members["sampleRate"] = .number(exactly: sampleRate.value)', "", mode="stmt"),
    Mutant("nosession", C, 'members["session"] = .string(session.uuidString)', "", mode="stmt"),
    Mutant("vendoridentifierunredacted", C, "context[VendorIdentifierKey.self].flatMap(reveal)", "context[VendorIdentifierKey.self]?.value"),
    Mutant("emptytrace", C, "!trace.isEmpty", "true"),
    Mutant("notrace", C, 'members["trace"] = .object(trace.mapValues(JSON.string))', "", mode="stmt"),
    # TrackingPlans' minified rendering.
    # The second "," in JSON.swift: minified's separator between an object's members.
    Mutant("minifiedspaced", "JSON.swift", '","', '", "', nth=1, module="TrackingPlans"),
    Mutant("minifiedcolonspaced", "JSON.swift", '":"', '": "', module="TrackingPlans"),
    # The second sort in JSON.swift is minified's.
    Mutant("minifiedunsorted", "JSON.swift", "$0.key.utf8.lexicographicallyPrecedes($1.key.utf8)", "$1.key.utf8.lexicographicallyPrecedes($0.key.utf8)", nth=1, module="TrackingPlans"),
]
