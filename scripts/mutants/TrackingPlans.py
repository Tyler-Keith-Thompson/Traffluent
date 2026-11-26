# Planted bugs for TrackingPlans; run with `just mutate TrackingPlans`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in Sources/TrackingPlans/<file>
# (or `nth=` picks one), and mode="stmt" replaces whole statements rather than an expression.
# Every mutant must be caught; one that survives needs a test, or a note here saying why it is
# equivalent to the original.
#
# Known equivalent mutants (left out, as they would survive by design):
# - Ordering names with String's `<` rather than by UTF-8 bytes: Swift compares strings by their
#   normalized scalars, the same order as their bytes for the NFC text every test can write.
# - The fallback CocoaError in `cocoa(_:)`: every error Foundation's file calls throw is a CocoaError
#   already, so no test can reach it.
# - Trying Int64 before Bool in JSON's decoding: JSONDecoder reads no integer from `true` or `false`
#   on any platform, so the order picks the same case.
# - Dropping `filter(TrackingPlan.isPlanFile)` in `check(againstDirectory:)`: `check(against:)`
#   filters the files again; the first filter only saves reading files a plan doesn't write.
# - `$0.version > event.version` as `>=` when finding a later version: an equal version is the
#   committed event's own key, matched before the search.
# - `.first { $0 != "null" }` as `.last` in an example's type: a plan writes `null` last.
# - Dropping the guard that skips a pattern already written: a Refinement or @Constrained that
#   lists one pattern twice is the only way to reach it, and an allOf repeating the pattern accepts
#   the same payloads; only the bytes would differ.

TESTS = ["TrackingPlansTests"]

T = "TrackingPlan.swift"
J = "JSON.swift"
D = "EventSchema+Document.swift"
W = "WrittenType.swift"
F = "TrackingPlan+Write.swift"
C = "TrackingPlanCommand.swift"
E = "EventSchema+Example.swift"
K = "TrackingPlan+Check.swift"
R = "TrackingPlanCheck.swift"
X = "TrackingPlanDifference.swift"

MUTANTS = [
    # TrackingPlan: the rules, the order and the index.
    Mutant("emptynameallowed", T, "!schema.name.isEmpty", "true"),
    Mutant("duplicatepropertyallowed", T, "schema.hasDistinctPropertyNames", "true"),
    Mutant("duplicateeventallowed", T, "fileNames.insert(schema.fileName.lowercased()).inserted", "true"),
    Mutant("casesensitive", T, "schema.fileName.lowercased()", "schema.fileName"),
    Mutant("unsorted", T, "schemas.sorted(by: EventSchema.precedesInPlan)", "schemas"),
    Mutant("versionsreversed", T, "first.version < second.version", "first.version > second.version"),
    Mutant("namesreversed", T, "first.name.utf8.lexicographicallyPrecedes(second.name.utf8)", "second.name.utf8.lexicographicallyPrecedes(first.name.utf8)"),
    Mutant("noindex", T, "[File(path: TrackingPlan.indexFileName, json: index)]", "[]"),
    Mutant("indexrenamed", T, '"tracking-plan.json"', '"index.json"', nth=1),
    Mutant("indexversionfixed", T, ".integer(Int64(version))", ".integer(1)"),
    Mutant("indexcategoryfixed", T, '.string(consentCategory.name)', '.string("analytics")'),
    Mutant("indexschemaname", T, ".string(fileName)", ".string(name)"),
    Mutant("notrailingnewline", T, 'json.rendered + "\\n"', "json.rendered"),
    Mutant("noexamples", T, "[File(path: schema.fileName, json: document), File(path: schema.exampleFileName, json: schema.example)]", "[File(path: schema.fileName, json: document)]"),
    Mutant("indexexampleisdocument", T, '.string(exampleFileName)', '.string(fileName)'),
    # JSON: the rendering.
    Mutant("emptyarraymultiline", J, "!elements.isEmpty", "true"),
    Mutant("emptyobjectmultiline", J, "!members.isEmpty", "true"),
    Mutant("arrayindentwide", J, 'indentation + "  "', 'indentation + "    "', nth=0),
    Mutant("objectindentwide", J, 'indentation + "  "', 'indentation + "    "', nth=1),
    Mutant("arraytrailingcomma", J, 'offset == elements.count - 1 ? "\\n" : ",\\n"', '",\\n"'),
    Mutant("objecttrailingcomma", J, 'offset == sorted.count - 1 ? "\\n" : ",\\n"', '",\\n"'),
    Mutant("keysreversed", J, "$0.key.utf8.lexicographicallyPrecedes($1.key.utf8)", "$1.key.utf8.lexicographicallyPrecedes($0.key.utf8)", nth=1),
    Mutant("colonspaced", J, '": "', '" : "', nth=1),
    Mutant("booleanalwaystrue", J, 'boolean ? "true" : "false"', '"true"'),
    Mutant("quoteunescaped", J, r'"\\\""', r'"\""'),
    Mutant("backslashunescaped", J, r'"\\\\"', r'"\\"'),
    Mutant("newlineraw", J, r'"\\n"', r'"\n"'),
    Mutant("controlnotpadded", J, "4 - hex.count", "2 - hex.count"),
    Mutant("controllowercase", J, "String(scalar.value, radix: 16, uppercase: true)", "String(scalar.value, radix: 16, uppercase: false)"),
    # EventSchema+Document: file names and documents.
    Mutant("everybyteunreserved", D, "byte.isUnreserved", "true"),
    Mutant("hexnotpadded", D, '(hex.count == 1 ? "0" : "")', '""'),
    Mutant("hexlowercase", D, "String(byte, radix: 16, uppercase: true)", "String(byte, radix: 16, uppercase: false)"),
    Mutant("noversioninfilename", D, '"\\(encoded).v\\(version)"', '"\\(encoded)"'),
    Mutant("examplefilename", D, '"\\(fileStem).example.json"', '"\\(fileStem).sample.json"'),
    Mutant("idisname", D, ".string(fileName)", ".string(name)"),
    Mutant("titlerenamed", D, '"title"', '"name"'),
    Mutant("requiredinverted", D, r"properties.filter(\.isRequired)", "properties.filter { !$0.isRequired }"),
    Mutant("additionalallowed", D, ".boolean(false)", ".boolean(true)"),
    Mutant("documentversionfixed", D, ".integer(Int64(version))", ".integer(1)"),
    Mutant("documentcategoryfixed", D, ".string(consentCategory.name)", '.string("analytics")'),
    # One narrowing serves a mapped type and one the plan can't map, so keywordsignored covers both.
    Mutant("keywordsignored", D, "return schema.narrowed(by: keywords)", "return schema", mode="stmt"),
    Mutant("optionalnotnullable", D, "WrittenType(parsing: typeName)?.schema(isNullable: isOptional)", "WrittenType(parsing: typeName)?.schema(isNullable: false)"),
    Mutant("unparsedunnamed", D, '["x-traffluent-swift-type": .string(typeName)]', '["x-traffluent-swift-type": .string("")]'),
    Mutant("wrappednotnullable", D, "wrapped.schema(isNullable: true)", "wrapped.schema(isNullable: false)"),
    Mutant("optionalgenericnotnullable", D, "arguments[0].schema(isNullable: true)", "arguments[0].schema(isNullable: false)"),
    Mutant("optionalunqualified", D, 'names("Optional", in: ["Swift"])', 'names("Optional", in: [])'),
    Mutant("sensitiveunmarked", D, '"x-traffluent-sensitive"', '"x-traffluent-secret"', nth=1),
    Mutant("sensitivetraffluentmodule", D, '["Events", "Traffluent"]', '["Events"]', nth=1),
    Mutant("sensitivedropsnull", D, "arguments[0].schema(isNullable: isNullable)", "arguments[0].schema(isNullable: false)", nth=1),
    Mutant("arraynotnullable", D, '.type("array", isNullable: isNullable)', '.type("array", isNullable: false)'),
    Mutant("itemsnullable", D, "element.schema(isNullable: element.isSensitive)", "element.schema(isNullable: true)"),
    Mutant("arraygenericignored", D, 'names("Array", in: ["Swift"])', 'names("List", in: ["Swift"])'),
    Mutant("scalargenericaccepted", D, "arguments.isEmpty", "true"),
    Mutant("unknownunnamed", D, '["x-traffluent-swift-type": .string(source)]', '["x-traffluent-swift-type": .string("")]'),
    Mutant("floatinteger", D, 'Scalar(name: "Float", modules: ["Swift"], type: "number")', 'Scalar(name: "Float", modules: ["Swift"], type: "integer")'),
    Mutant("int32unbounded", D, "bounds(Int64(Int32.min), Int64(Int32.max))", "[:]"),
    Mutant("uintsigned", D, 'Scalar(name: "UInt", modules: ["Swift"], type: "integer", keywords: ["minimum": .integer(0)])', 'Scalar(name: "UInt", modules: ["Swift"], type: "integer")'),
    Mutant("uint8bounds16", D, 'bounds(0, Int64(UInt8.max))', 'bounds(0, Int64(UInt16.max))'),
    Mutant("dateformatless", D, '["format": .string("date-time")]', '[:]'),
    Mutant("uuidformatless", D, '["format": .string("uuid")]', '[:]'),
    Mutant("foundationessentialsunknown", D, '["Foundation", "FoundationEssentials"]', '["Foundation"]', nth=1),
    Mutant("nullnotadded", D, "isNullable ? .array([.string(name), .string(\"null\")]) : .string(name)", ".string(name)"),
    Mutant("underscorereserved", D, "self == 0x5F", "false"),
    Mutant("hyphenreserved", D, "self == 0x2D", "false"),
    # WrittenType: the parser.
    Mutant("anymodule", W, "modules.contains(components[0])", "true"),
    Mutant("deepqualified", W, "components.count", "min(components.count, 2)"),
    Mutant("trailingtextignored", W, "parser.isAtEnd", "true"),
    Mutant("bangnotoptional", W, 'consume("?") || consume("!")', 'consume("?")'),
    Mutant("unclosedarray", W, 'consume("]")', "true"),
    Mutant("onegenericargument", W, 'consume(",")', "false"),
    Mutant("unclosedgeneric", W, 'consume(">")', "true"),
    Mutant("whitespacesignificant", W, "characters[position].isWhitespace", "false"),
    Mutant("argumentsunspaced", W, 'arguments.map(\\.source).joined(separator: ", ")', 'arguments.map(\\.source).joined(separator: ",")'),
    Mutant("optionalsourcedropped", W, 'wrapped.source + "?"', "wrapped.source"),
    Mutant("arraysourcebare", W, '"[" + element.source + "]"', "element.source"),
    Mutant("underscorenotidentifier", W, 'isLetter || isNumber || self == "_"', "isLetter || isNumber"),
    Mutant("digitnotidentifier", W, 'isLetter || isNumber || self == "_"', 'isLetter || self == "_"', nth=0),
    # Writing and the command. nointermediatedirectories comes first: the file's only `true`, before
    # the mutants below write more.
    Mutant("nointermediatedirectories", F, "true", "false"),
    Mutant("deletesall", F, 'TrackingPlan.isPlanFile($0) && !paths.contains($0)', '!paths.contains($0)'),
    Mutant("deletesplanfiles", F, 'TrackingPlan.isPlanFile($0) && !paths.contains($0)', 'TrackingPlan.isPlanFile($0)'),
    Mutant("indexnotplanfile", F, 'path == indexFileName', 'false'),
    Mutant("examplesnotplanfiles", F, 'path.hasSuffix(".example.json")', 'false'),
    Mutant("rewritesunchanged", F, "fileManager.contents(atPath: url.path) != contents", "true"),
    # The check's statuses come before the ones below, whose replacements write `return 1`.
    # checkalonewrites writes the plan into ./check of the directory the tests run in, the run's own
# directory that scripts/mutate.py removes afterwards.
    Mutant("checkalonewrites", C, 'arguments[0] != "check"', "true"),
    Mutant("anytwochecks", C, 'arguments[0] == "check"', "true"),
    Mutant("checkchecksfirst", C, "check(against: arguments[1])", "check(against: arguments[0])"),
    Mutant("matchstatus", C, "            return 0", "            return 7", mode="stmt", nth=1),
    Mutant("breakingstatus", C, "            return 1", "            return 9", mode="stmt"),
    Mutant("outofdatestatus", C, "            return 2", "            return 8", mode="stmt"),
    Mutant("usagestatus", C, "            return 64", "            return 1", mode="stmt"),
    Mutant("writefailurestatus", C, "            return 73", "            return 1", mode="stmt"),
    Mutant("successstatus", C, "            return 0", "            return 1", mode="stmt", nth=0),
    # Examples. stringexample comes first, before the mutants below write `.string(...)`.
    Mutant("stringexample", E, '.string(textExample)', '.string("")'),
    Mutant("dateexample", E, '.string("2001-01-01T00:00:00Z")', '.string("example")'),
    Mutant("uuidexample", E, '.string("00000000-0000-0000-0000-000000000000")', '.string("example")'),
    Mutant("integerexample", E, 'self["minimum"]?.double.map { Swift.max(0, $0.rounded(.up)) } ?? 0', "1"),
    Mutant("booleanexample", E, ".boolean(false)", ".boolean(true)"),
    Mutant("arrayexampleempty", E, "itemCount", "0", nth=0),
    Mutant("unknownexample", E, ".null", '.string("")', nth=1),
    Mutant("nullexampletype", E, '$0 != "null"', '$0 == "null"'),
    Mutant("nopropertyexamples", E, "(property.name, property.schema.example)", "(property.name, JSON.null)"),
    # JSON: reading and one-line rendering.
    Mutant("nullunread", J, "container.decodeNil()", "false"),
    Mutant("nullrendered", J, 'text += "null"', 'text += "nil"', mode="stmt"),
    Mutant("compactarrayunspaced", J, '", "', '","', nth=0),
    Mutant("compactobjectunspaced", J, '", "', '","', nth=1),
    Mutant("compactcolon", J, 'JSON.string($0.key).compact + ": "', 'JSON.string($0.key).compact + ":"'),
    Mutant("compactunsorted", J, "$0.key.utf8.lexicographicallyPrecedes($1.key.utf8)", "$1.key.utf8.lexicographicallyPrecedes($0.key.utf8)", nth=0),
    # Checking: what is compared.
    Mutant("bytesfirst", K, "differences.isEmpty", "true"),
    Mutant("bytesignored", K, "committedFiles[$0] != currentFiles[$0]", "false"),
    Mutant("otherfilescompared", K, "committed.filter { TrackingPlan.isPlanFile($0.path) }", "committed"),
    Mutant("indexentryunchecked", K, "paths.count == events.count ? paths : nil", "paths"),
    Mutant("unreadablenamedindex", K, ".unreadableFile(path: path)", ".unreadableFile(path: TrackingPlan.indexFileName)"),
    Mutant("versionfromboolean", K, 'members["x-traffluent-version"]?.integer', 'members["x-traffluent-version"]?.integer ?? 2'),
    Mutant("requiredunchecked", K, "required.count == requiredNames.count", "true"),
    Mutant("propertyschemaunchecked", K, "schema.object", "schema.object ?? [:]", nth=0),
    Mutant("nextversionlatest", K, "laterVersions.min()", "laterVersions.max()"),
    Mutant("lowerversionraises", K, "$0.version > event.version", "$0.version < event.version"),
    Mutant("supersededadded", K, "!superseding.contains(event.key)", "true"),
    Mutant("committedadded", K, "!committedKeys.contains(event.key)", "true"),
    Mutant("consentignored", K, "consentCategory != current.consentCategory", "false"),
    Mutant("retypeignored", K, "before.type != after.type", "false"),
    Mutant("maderequiredignored", K, "before.isNullable && !after.isNullable", "false", nth=1),  # the first is inside the default value comparison
    Mutant("madeoptionalignored", K, "!before.isNullable && after.isNullable", "false"),
    Mutant("sensitivityignored", K, "before.isSensitive != after.isSensitive", "false"),
    Mutant("sensitivityinverted", K, "after.isSensitive", "before.isSensitive", nth=2),
    Mutant("removedasoptional", K, ".propertyRemoved(event: name, version: version, property: property)", ".propertyMadeOptional(event: name, version: version, property: property)"),
    Mutant("addedalwaysrequired", K, "after.isNullable", "false", nth=3),
    Mutant("nullkept", K, 'type["type"] = type["type"]?.withoutNull', "", mode="stmt"),
    Mutant("nulltypelist", K, "named.count == 1 ? named[0] : .array(named)", ".array(named)"),
    Mutant("sensitivitykept", K, 'type["x-traffluent-sensitive"] = nil', "", mode="stmt"),
    Mutant("sensitivityunread", K, 'schema["x-traffluent-sensitive"] == .boolean(true)', "false"),
    # The check's result and report.
    Mutant("neverbreaking", R, "differences.contains(where: \\.isBreaking)", "false"),
    Mutant("nevermatches", R, "differences.isEmpty", "false"),
    Mutant("breakingunsorted", R, "differences.filter(\\.isBreaking)", "differences"),
    Mutant("alwaysalsooutofdate", R, "!others.isEmpty", "true"),
    Mutant("sensitivitywording", X, 'isSensitive ? "is now" : "is no longer"', 'isSensitive ? "is no longer" : "is now"'),
    # Constraint keywords in a property's schema.
    Mutant("minlengthloosest", D, 'schema.tighten("minLength", to: Double(length), keepingLarger: true)', 'schema.tighten("minLength", to: Double(length), keepingLarger: false)'),
    Mutant("maximumloosest", D, 'schema.tighten("maximum", to: bound, keepingLarger: false)', 'schema.tighten("maximum", to: bound, keepingLarger: true)'),
    Mutant("tighterreplaced", D, "keepingLarger ? existing >= bound : existing <= bound", "false"),
    Mutant("maxitemsdropped", D, 'schema.tighten("maxItems", to: Double(count), keepingLarger: false)', "", mode="stmt"),
    Mutant("patternexamplemissing", D, 'schema["examples"] = .array([.string(example)])', "", mode="stmt"),
    Mutant("secondpatterndropped", D, 'schema["allOf"] = .array((schema["allOf"]?.array ?? []) + [.object(["pattern": .string(pattern)])])', "", mode="stmt"),
    Mutant("refinedunmapped", D, "arguments.count == 2", "arguments.count == 3"),
    # JSON numbers.
    Mutant("wholenumberfractional", J, "return .integer(Int64(value))", "return .number(value)", mode="stmt"),
    Mutant("fractionnotdecoded", J, "self = .number(exactly: number)", "self = .null", mode="stmt"),
    Mutant("hugenumberinteger", J, "value < 9_223_372_036_854_775_808", "true"),
    # Examples that meet their keywords.
    Mutant("patternexampleignored", E, 'self["examples"]?.array?.first', "nil"),
    Mutant("minlengthignored", E, "minimum > 7", "false"),
    Mutant("maxlengthignored", E, "maximum < Int64(text.unicodeScalars.count)", "false"),
    Mutant("integerminimumignored", E, 'self["minimum"]?.double.map { Swift.max(0, $0.rounded(.up)) } ?? 0', "0"),
    Mutant("integerfractionroundeddown", E, "$0.rounded(.up)", "$0.rounded(.down)"),
    Mutant("numbermaximumignored", E, 'self["maximum"]?.double', "nil", nth=1),
    Mutant("minitemsignored", E, "Swift.max(1, minimum)", "1"),
    Mutant("maxitemsignored", E, "Swift.min(count, Int(maximum))", "count"),
    # The check's constraint keywords.
    Mutant("constraintsintype", K, "type[keyword] = nil", "", mode="stmt"),
    Mutant("lowerboundreversed", K, "isLower ? after > before : after < before", "isLower ? after < before : after > before"),
    Mutant("boundsswapped", K, "(before, after)", "(after, before)"),
    Mutant("removedpatterntightens", K, "!added.isEmpty", "!removed.isEmpty", nth=1),
    Mutant("patternsignored", K, "!added.isEmpty || !removed.isEmpty", "false"),
    Mutant("extrapatternsunread", K, '(schema["allOf"]?.array ?? []).compactMap { $0.object?["pattern"]?.string }', "[]"),
    Mutant("constraintsdespiteretype", K, "before.type != after.type", "before.type != after.type && false"),
    Mutant("tightenedwording", X, r'"\(event) v\(version): property \"\(property)\" \(TrackingPlanDifference.change(keyword, committed, current)), which is tighter"', r'"\(event) v\(version): property \"\(property)\" \(TrackingPlanDifference.change(keyword, committed, current)), which is looser"'),
    Mutant("gainedwording", X, '"gained \\(keyword) \\(current)"', '"lost \\(keyword) \\(current)"'),
    # Default values (TRAF-18): marked in the document, and compared by the check.
    Mutant("defaultunmarked", D, 'schema["x-traffluent-default"] = .boolean(true)', "", mode="stmt"),
    Mutant("defaultunread", K, 'schema["x-traffluent-default"] == .boolean(true)', "false"),
    Mutant("defaultkeptintype", K, 'type["x-traffluent-default"] = nil', "", mode="stmt"),
    Mutant("defaultedasrequired", K, ".defaultedPropertyAdded(event: name, version: version, property: property)", ".requiredPropertyAdded(event: name, version: version, property: property)"),
    Mutant("defaultchangeignored", K, "before.hasDefaultValue != after.hasDefaultValue", "false"),
    Mutant("defaultchangeinverted", K, ".defaultValueAdded(event: name, version: version, property: property)", ".defaultValueRemoved(event: name, version: version, property: property)"),
    Mutant("defaultchangeoptional", K, "!before.isNullable && !after.isNullable", "true"),
    # Defaulted properties aren't required (TRAF-18 review): an earlier release's payload lacks them.
    Mutant("defaultedrequired", D, "!isOptional && !hasDefaultValue", "!isOptional"),
    # Deprecated properties (TRAF-46): a removed property stays in its version's document, the
    # export and the check carry it forward from the committed plan, and declaring it again is
    # compared with the schema it had.
    Mutant("deprecatednotmarked", D, '$0.merging(["deprecated": .boolean(true)]) { $1 }', "$0"),
    Mutant("deprecatednotkept", D, "declared.merging(deprecated, uniquingKeysWith: { current, _ in current })", "declared"),
    Mutant("restoredkeepsdeprecated", D, "{ current, _ in current }", "{ _, deprecated in deprecated }"),
    Mutant("writenotcarried", F, "files(carryingForward: TrackingPlan.planFiles(in: directory))", "files(carryingForward: [])"),
    Mutant("checknotcarried", K, "files(carryingForward: committed)", "files"),
    Mutant("deprecatedunread", K, 'schema["deprecated"] == .boolean(true)', "false"),
    Mutant("deprecatedkeptintype", K, 'type["deprecated"] = nil', "", mode="stmt"),
    Mutant("deprecatedremovalreported", K, "!before.isDeprecated", "true", nth=1),
    Mutant("restoredrequiredignored", K, "before.isDeprecated && before.isRequiredWhenDeclared && after.isRequiredWhenDeclared", "false"),
    Mutant("unknowntypenevernullable", K, "allowsNull ?? (!isRequired && !hasDefaultValue)", "allowsNull ?? false"),
    # Sensitive properties are never required (TRAF-84): a destination that redacts one leaves it
    # out, and an array's redacted element is null. A sensitivity change can change what is
    # required, and a plan exported before this compares as the same types.
    Mutant("sensitiverequired", D, 'schema["x-traffluent-sensitive"] != .boolean(true)', "true"),
    Mutant("sensitiveitemsnotnullable", D, "element.schema(isNullable: element.isSensitive)", "element.schema(isNullable: false)"),
    Mutant("sensitiveitemstraffluentmodule", D, '["Events", "Traffluent"]', '["Events"]', nth=2),
    Mutant("sensitivemaderequiredwhennotsensitive", K, "before.isSensitive", "true", nth=0),
    Mutant("sensitivemaderequiredwhenmadesensitive", K, "!after.isSensitive", "true"),
    Mutant("sensitivemaderequiredbeforeoptional", K, "before.isRequiredWhenDeclared", "true", nth=1),
    Mutant("sensitivemaderequiredafteroptional", K, "after.isRequiredWhenDeclared", "true", nth=1),
    Mutant("sensitivemaderequiredwhendeprecated", K, "!before.isDeprecated", "true", nth=0),
    Mutant("sensitivemaderequiredwording", X, r'"\(event) v\(version): property \"\(property)\" is no longer sensitive and is now required"', r'"\(event) v\(version): property \"\(property)\" is no longer sensitive"'),
    Mutant("redactednullkept", K, "type[\"items\"] = .object(Self.withoutRedactedNull(items))", "", mode="stmt"),
    Mutant("redactednullnested", K, "items[\"items\"] = .object(withoutRedactedNull(nested))", "", mode="stmt"),
    Mutant("redactednullnotsensitive", K, 'items["x-traffluent-sensitive"] == .boolean(true)', "true"),
]
