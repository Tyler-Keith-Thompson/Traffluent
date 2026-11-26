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
# - The byte-string and other-tag arms of `anyValue()`: no public BinaryCodable API writes them,
#   so no test can reach them.

TESTS = ["PropertyJSONTests", "CollectorEncodingTests", "PostHogEncodingTests"]

S = "EventSchema+PropertyTypes.swift"
R = "EventRecord+Properties.swift"
P = "PropertyReader.swift"
D = "Date+PropertyTimestamp.swift"

MUTANTS = [
    Mutant("optionalignored", S, "property.isOptional ? type.map(WrittenType.optional) : type", "type"),
    Mutant("alwayswrites", R, "BinaryEncoder(writingSensitiveValues: writingSensitiveValues)", "BinaryEncoder(writingSensitiveValues: true)"),
    Mutant("neverwrites", R, "BinaryEncoder(writingSensitiveValues: writingSensitiveValues)", "BinaryEncoder(writingSensitiveValues: false)"),
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
    Mutant("floatwidened", P, "Double(number.description)", "Optional(Double(number))"),
    Mutant("negativeoffbyone", P, "~$0", "-$0"),
    Mutant("largeunsignedclamped", P, "Double(head.argument)", "Double(UInt64(Int64.max))", nth=0),
    Mutant("uuidlowercased", P, "UUID(uuid: uuid).uuidString", "UUID(uuid: uuid).uuidString.lowercased()"),
    # The guard binds the number, so a non-finite one becomes null rather than the guard dropped.
    Mutant("nonfiniteaccepted", P, "JSON.number(exactly: number)", "Optional(JSON.number(exactly: number) ?? .null)"),
    Mutant("nonfinitedateaccepted", P, "guard seconds.isFinite else { throw .invalidValue }", "", mode="stmt"),
    Mutant("notamapaccepted", P, "count = try decoder.readCount(of: .map, elementSize: 2)", "count = 0", mode="stmt"),
]
