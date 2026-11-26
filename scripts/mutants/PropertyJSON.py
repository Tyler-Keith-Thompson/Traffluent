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

TESTS = ["PropertyJSONTests", "CollectorEncodingTests", "PostHogEncodingTests"]

S = "EventSchema+PropertyTypes.swift"
R = "EventRecord+Properties.swift"
P = "PropertyReader.swift"
D = "Date+PropertyTimestamp.swift"

MUTANTS = [
    Mutant("optionalignored", "EventSchema+PropertyTypes.swift", 'guard property.isOptional else { return (property.name, type) }', 'return (property.name, type)', mode="stmt"),
    # The first copy is the doc comment's, the second the parameter's, the third the encoding's.
    Mutant("alwayswrites", R, "writingSensitiveValues", "true", nth=2),
    Mutant("neverwrites", R, "writingSensitiveValues", "false", nth=2),
    Mutant("readernotredacting", R, "!writingSensitiveValues", "false"),
    Mutant("encodingfailurepropagates", R, "throw .unrepresentableValue(event: name, property: \"\")", "throw .notEncodable(name: name)", mode="stmt"),
    Mutant("wholeseconds", D, "true", "false"),
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
    Mutant("nesteddateunread", P, "return try .string(Self.date(value).propertyTimestamp)", "throw Unrepresentable()", mode="stmt", nth=1),
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
]
