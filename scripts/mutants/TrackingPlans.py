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
D = "EventSchema+Document.swift"
W = "WrittenType.swift"
F = "TrackingPlan+Write.swift"
C = "TrackingPlanCommand.swift"
E = "EventSchema+Example.swift"
K = "TrackingPlan+Check.swift"
R = "TrackingPlanCheck.swift"
X = "TrackingPlanDifference.swift"
V = "TrackingPlan+EarlierVersion.swift"
I = "TrackingPlan+Iglu.swift"
N = "String+IgluNames.swift"

MUTANTS = [
    # TrackingPlan: the rules, the order and the index.
    Mutant("emptynameallowed", T, "!schema.name.isEmpty", "true"),
    Mutant("duplicatepropertyallowed", T, "schema.hasDistinctPropertyNames", "true"),
    Mutant("duplicateeventallowed", T, "fileNames[fileName]", "nil", nth=0),
    Mutant("duplicateeventforgotten", T, "fileNames[fileName] = typeName", "", mode="stmt"),
    Mutant("duplicateversionlost", T, "throw .duplicateEvent(schema.name, version: schema.version, firstType: firstType, secondType: typeName)", "throw .duplicateEvent(schema.name, version: 0, firstType: firstType, secondType: typeName)", mode="stmt"),
    Mutant("casesensitive", T, "schema.fileName.lowercased()", "schema.fileName"),
    Mutant("unsorted", T, "EventSchema.precedesInPlan($0.element.schema, $1.element.schema) || (!EventSchema.precedesInPlan($1.element.schema, $0.element.schema) && $0.offset < $1.offset)", "$0.offset < $1.offset"),
    # nth=1: PlanEntry's index order comes first in the file, then the schemas'.
    Mutant("versionsreversed", T, "first.version < second.version", "first.version > second.version", nth=1),
    Mutant("namesreversed", T, "first.name.utf8.lexicographicallyPrecedes(second.name.utf8)", "second.name.utf8.lexicographicallyPrecedes(first.name.utf8)", nth=1),
    Mutant("noindex", T, "[File(path: TrackingPlan.indexFileName, json: index)]", "[]"),
    Mutant("indexrenamed", T, '"tracking-plan.json"', '"index.json"', nth=1),
    Mutant("indexversionfixed", T, ".integer(Int64(version))", ".integer(1)"),
    Mutant("indexcategoryfixed", T, '.string(consentCategory.name)', '.string("analytics")'),
    Mutant("indexschemaname", T, ".string(fileName)", ".string(name)"),
    Mutant("notrailingnewline", T, 'json.rendered + "\\n"', "json.rendered"),
    Mutant("noexamples", T, "[File(path: schema.fileName, json: document), File(path: schema.exampleFileName, json: schema.example)]", "[File(path: schema.fileName, json: document)]"),
    Mutant("indexexampleisdocument", T, '.string(exampleFileName)', '.string(fileName)'),
    # EventSchema+Document: file names and documents.
    Mutant("everybyteunreserved", D, "byte.isUnreserved", "true"),
    Mutant("hexnotpadded", D, '(hex.count == 1 ? "0" : "")', '""'),
    Mutant("hexlowercase", D, "String(byte, radix: 16, uppercase: true)", "String(byte, radix: 16, uppercase: false)"),
    Mutant("noversioninfilename", D, '"\\(EventSchema.encodedFileName(of: name)).v\\(version)"', '"\\(EventSchema.encodedFileName(of: name))"'),
    Mutant("examplefilename", D, '"\\(fileStem).example.json"', '"\\(fileStem).sample.json"'),
    Mutant("idisname", D, ".string(fileName)", ".string(name)"),
    Mutant("titlerenamed", D, '"title"', '"name"'),
    Mutant("requiredinverted", D, r"properties.filter(\.isRequired)", "properties.filter { !$0.isRequired }"),
    Mutant("additionalallowed", D, ".boolean(false)", ".boolean(true)"),
    Mutant("documentversionfixed", D, ".integer(Int64(version))", ".integer(1)"),
    Mutant("documentcategoryfixed", D, ".string(consentCategory.name)", '.string("analytics")'),
    # One narrowing serves a mapped type and one the plan can't map, so keywordsignored covers both.
    Mutant("keywordsignored", D, "return schema.narrowed(by: keywords)", "return schema", mode="stmt"),
    Mutant("optionalnotnullable", D, "WrittenType(parsing: typeName)?.schema(isNullable: isOptional, enumeration: enumeration)", "WrittenType(parsing: typeName)?.schema(isNullable: false, enumeration: enumeration)"),
    Mutant("unparsedunnamed", D, '["x-traffluent-swift-type": .string(typeName)]', '["x-traffluent-swift-type": .string("")]'),
    Mutant("wrappednotnullable", D, "wrapped.schema(isNullable: true, enumeration: enumeration)", "wrapped.schema(isNullable: false, enumeration: enumeration)"),
    Mutant("optionalgenericnotnullable", D, "arguments[0].schema(isNullable: true, enumeration: enumeration)", "arguments[0].schema(isNullable: false, enumeration: enumeration)"),
    Mutant("optionalunqualified", D, 'names("Optional", in: ["Swift"])', 'names("Optional", in: [])'),
    Mutant("sensitiveunmarked", D, '"x-traffluent-sensitive"', '"x-traffluent-secret"', nth=1),
    Mutant("sensitivetraffluentmodule", D, '["Events", "Traffluent"]', '["Events"]', nth=1),
    Mutant("sensitivedropsnull", D, "arguments[0].schema(isNullable: isNullable, enumeration: enumeration)", "arguments[0].schema(isNullable: false, enumeration: enumeration)"),
    Mutant("arraynotnullable", D, '.type("array", isNullable: isNullable)', '.type("array", isNullable: false)'),
    Mutant("itemsnullable", D, "element.schema(isNullable: element.isSensitive, enumeration: enumeration)", "element.schema(isNullable: true, enumeration: enumeration)"),
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
    # The command's arguments. checkalonewrites and writeoption write the plan into ./check and
    # ./-p of the directory the tests run in, the run's own directory that scripts/mutate.py
    # removes afterwards. main() isn't mutated: it prints and exits the process, which no test does.
    Mutant("checkalonewrites", C, 'arguments[0] != "check"', "true"),
    Mutant("anytwochecks", C, 'arguments[0] == "check"', "true", nth=0),
    Mutant("anythreechecks", C, 'arguments[0] == "check"', "true", nth=1),
    Mutant("anyflag", C, "arguments[1] == breakingOnlyFlag", "true"),
    Mutant("writeoption", C, "!arguments[0].isOption", "true"),
    Mutant("checkoption", C, "!arguments[1].isOption", "true", nth=0),
    Mutant("breakingonlyoption", C, "!arguments[2].isOption", "true", nth=0),
    Mutant("optiondoubledash", C, 'hasPrefix("-")', 'hasPrefix("--")'),
    Mutant("optionanydash", C, 'hasPrefix("-")', 'contains("-")'),
    Mutant("checkchecksfirst", C, "check($0, against: arguments[1])", "check($0, against: arguments[0])"),
    Mutant("breakingonlyignored", C, "checkBreakingOnly($0, against: arguments[2])", "check($0, against: arguments[2])"),
    Mutant("breakingonlychecksflag", C, "checkBreakingOnly($0, against: arguments[2])", "checkBreakingOnly($0, against: arguments[1])"),
    Mutant("invalidplanexitszero", C, "TrackingPlanCommandResult(status: 65, standardError: \"error: the events' schemas can't make a tracking plan: \\(error)\")", "TrackingPlanCommandResult(status: 0)"),
    # The keywords a plan accepts: each a constraint could state.
    Mutant("invalidkeywordaccepted", T, "guard schema.properties.allSatisfy({ !$0.hasInvalidConstraint && $0.keywords.allSatisfy(\\.isStatable) }) else { throw .invalidKeyword }", "", mode="stmt"),
    Mutant("invalidconstraintexported", T, "!$0.hasInvalidConstraint && $0.keywords.allSatisfy(\\.isStatable)", "$0.keywords.allSatisfy(\\.isStatable)"),
    Mutant("negativecountstatable", T, "count >= 0", "count >= -1"),
    Mutant("nonfiniteboundstatable", T, "bound.isFinite", "true"),
    Mutant("invalidpatternstatable", T, "(try? Regex(pattern)).map { example.contains($0) } ?? false", "(try? Regex(pattern)).map { example.contains($0) } ?? true"),
    # After invalidpatternstatable's, the text holds two copies; the second is the original's.
    Mutant("mismatchedexamplestatable", T, "example.contains($0)", "true", nth=1),
    # The command's statuses and output. `TrackingPlanCommandResult(status: 0)` is written, then
    # matched by both checks, in that order; invalidplanexitszero's replacement, before them, adds
    # one more first, so these count from 1.
    Mutant("successstatus", C, "TrackingPlanCommandResult(status: 0)", "TrackingPlanCommandResult(status: 1)", nth=1),
    Mutant("matchstatus", C, "TrackingPlanCommandResult(status: 0)", "TrackingPlanCommandResult(status: 7)", nth=2),
    Mutant("breakingonlymatchstatus", C, "TrackingPlanCommandResult(status: 0)", "TrackingPlanCommandResult(status: 7)", nth=3),
    Mutant("breakingstatus", C, 'TrackingPlanCommandResult(status: 1, standardError: "error: \\(directory): \\(check)")', 'TrackingPlanCommandResult(status: 9, standardError: "error: \\(directory): \\(check)")', nth=0),
    Mutant("breakingonlypassesbreaking", C, 'TrackingPlanCommandResult(status: 1, standardError: "error: \\(directory): \\(check)")', "TrackingPlanCommandResult(status: 0)", nth=1),
    Mutant("outofdatestatus", C, 'TrackingPlanCommandResult(status: 2, standardError: "error: \\(directory): \\(check)")', 'TrackingPlanCommandResult(status: 8, standardError: "error: \\(directory): \\(check)")'),
    Mutant("breakingonlyfailsoutofdate", C, 'TrackingPlanCommandResult(status: 0, standardOutput: lines.joined(separator: "\\n"))', 'TrackingPlanCommandResult(status: 2, standardOutput: lines.joined(separator: "\\n"))'),
    Mutant("breakingonlysilent", C, 'TrackingPlanCommandResult(status: 0, standardOutput: lines.joined(separator: "\\n"))', 'TrackingPlanCommandResult(status: 0, standardOutput: "")'),
    Mutant("breakingonlyoutofdatetostderr", C, 'TrackingPlanCommandResult(status: 0, standardOutput: lines.joined(separator: "\\n"))', 'TrackingPlanCommandResult(status: 0, standardError: lines.joined(separator: "\\n"))'),
    Mutant("breakingonlydropsdifference", C, 'differences.map { "  - \\($0)" }', 'differences.dropFirst().map { "  - \\($0)" }'),
    Mutant("usagestatus", C, "TrackingPlanCommandResult(status: 64, standardError: usage)", "TrackingPlanCommandResult(status: 1, standardError: usage)"),
    Mutant("writefailurestatus", C, "TrackingPlanCommandResult(status: 73, standardError: message)", "TrackingPlanCommandResult(status: 1, standardError: message)"),
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
    # Checking: what is compared.
    Mutant("bytesfirst", K, "differences.isEmpty", "true"),
    Mutant("bytesignored", K, "committedFiles[$0] != currentFiles[$0]", "false"),
    Mutant("otherfilescompared", K, "committed.filter { TrackingPlan.isPlanFile($0.path) }", "committed"),
    Mutant("indexentryunchecked", K, "documents.count == events.count ? documents : nil", "documents"),
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
    Mutant("boundsswapped", K, "(before, after)", "(after, before)", nth=0),
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
    Mutant("sensitiveitemsnotnullable", D, "element.schema(isNullable: element.isSensitive, enumeration: enumeration)", "element.schema(isNullable: false, enumeration: enumeration)"),
    Mutant("sensitiveitemstraffluentmodule", D, '["Events", "Traffluent"]', '["Events"]', nth=2),
    Mutant("sensitivemaderequiredwhennotsensitive", K, "before.isSensitive", "true", nth=0),
    Mutant("sensitivemaderequiredwhenmadesensitive", K, "!after.isSensitive", "true"),
    Mutant("sensitivemaderequiredbeforeoptional", K, "before.isRequiredWhenDeclared", "true", nth=1),
    Mutant("sensitivemaderequiredafteroptional", K, "after.isRequiredWhenDeclared", "true", nth=1),
    Mutant("sensitivemaderequiredwhendeprecated", K, "!before.isDeprecated", "true", nth=0),
    Mutant("sensitivemaderequiredwording", X, r'"\(event) v\(version): property \"\(property)\" is no longer sensitive and is now required"', r'"\(event) v\(version): property \"\(property)\" is no longer sensitive"'),
    Mutant("redactednullkept", K, "Self.withoutRedactedNull(items)", "items"),
    Mutant("redactednullnested", K, "items[\"items\"] = .object(withoutRedactedNull(nested))", "", mode="stmt"),
    Mutant("redactednullnotsensitive", K, 'items["x-traffluent-sensitive"] == .boolean(true)', "true"),
    # Raw-value enums (TRAF-91): the document's enum, the example and the check.
    Mutant("enumnotdocumented", D, "isNamed(enumeration.typeName)", "false"),
    Mutant("enumanyname", D, "isNamed(enumeration.typeName)", "true"),
    Mutant("enumnamewithoutarguments", D, "WrittenType.named([last], arguments).source == name", "last == name"),
    Mutant("enumnullnotlisted", D, "(isNullable ? [.null] : [])", "[]"),
    Mutant("enumintegerzero", D, ".integer(integer)", ".integer(0)"),
    Mutant("enumnooptionalthrough", D, "wrapped.schema(isNullable: true, enumeration: enumeration)", "wrapped.schema(isNullable: true)"),
    Mutant("enumnosensitivethrough", D, "arguments[0].schema(isNullable: isNullable, enumeration: enumeration)", "arguments[0].schema(isNullable: isNullable)"),
    Mutant("enumnoarraythrough", D, "element.schema(isNullable: element.isSensitive, enumeration: enumeration)", "element.schema(isNullable: element.isSensitive)"),
    Mutant("enumexampleignored", E, 'self["enum"]?.array?.first', "JSON?.none"),
    Mutant("enumintype", K, '["minLength", "maxLength", "minimum", "maximum", "minItems", "maxItems", "pattern", "allOf", "examples", "enum"]', '["minLength", "maxLength", "minimum", "maximum", "minItems", "maxItems", "pattern", "allOf", "examples"]'),
    Mutant("enumitemsenumkept", K, 'items["enum"] = nil', "", mode="stmt"),
    Mutant("enumnesteditemskept", K, 'items["items"] = .object(withoutEnumeration(nested))', "", mode="stmt"),
    Mutant("enumnullcounted", K, "Self.enumeration(in: schema)?.filter { $0 != .null }", "Self.enumeration(in: schema)"),
    Mutant("enumsamesetreported", K, "guard before != after else { return nil }", "", mode="stmt"),
    Mutant("enumaddedtightens", K, "!before.isSubset(of: after)", "before.isSubset(of: after)"),
    Mutant("enumlistedloosens", K, "before == nil", "false"),
    Mutant("enumunlistedtightens", K, "before == nil", "true"),
    Mutant("enumitemsunread", K, 'schema["items"]?.object.flatMap(enumeration(in:))', "[JSON]?.none"),
    Mutant("enumchangedropped", K, "if let change = enumerationChange(to: current.enumeration) {\n            changes.append(change)\n        }", "", mode="stmt"),
    # Earlier versions (TRAF-93): kept by writing, listed in the index, compared by bytes alone.
    Mutant("earlierversionsdropped", T, "earlierVersions(in: committedDocuments)", "earlierVersions(in: [:])"),
    Mutant("earlierindexorderreversed", T, "first.version < second.version", "first.version > second.version", nth=0),
    Mutant("earlierindexnamesreversed", T, "first.name.utf8.lexicographicallyPrecedes(second.name.utf8)", "second.name.utf8.lexicographicallyPrecedes(first.name.utf8)", nth=0),
    Mutant("earlierunlisted", T, "entries.compactMap(\\.indexEntry)", "current.compactMap(\\.indexEntry)"),
    Mutant("earliertitleunchecked", V, 'members["title"]?.string == name', "true"),
    Mutant("earlierversionunchecked", V, 'members["x-traffluent-version"]?.integer == Int64(version)', "true"),
    Mutant("earliercategoryfixed", V, ".string(consentCategory)", '.string("analytics")'),
    Mutant("earlierexampleunlisted", V, 'entry["example"] = example.map { .string($0.path) }', "", mode="stmt"),
    Mutant("earlierexampledropped", V, "example.map { [$0] } ?? []", "[]"),
    Mutant("earlierexampleunread", V, "committed[examplePath].map { File(path: examplePath, contents: $0) }", "File?.none"),
    Mutant("laterversionkept", V, "version < newest", "true"),
    Mutant("listedversionkept", V, "!versions.contains(version)", "true"),
    Mutant("versionsnotgrouped", V, "versionsByName.last?.name == schema.name", "false"),
    Mutant("otherprefixkept", V, "path.hasPrefix(stem)", "true"),
    Mutant("othersuffixkept", V, "path.hasSuffix(suffix)", "true"),
    Mutant("paddedversionkept", V, "String($0) == digits ? $0 : nil", "$0"),
    Mutant("earliercompared", K, "version >= later || listed.contains(EventContract.Key(name: name, version: version))", "true"),
    Mutant("listedearlierskipped", K, "listed.contains(EventContract.Key(name: name, version: version))", "false"),
    Mutant("newestskipped", K, "version >= later", "version > later"),
    Mutant("newestunread", K, "newest[name]", "Int?.none", nth=2),
    Mutant("indexnameunread", K, 'entry["name"]?.string', "String?.none"),
    Mutant("indexversionunread", K, 'entry["version"]?.integer.flatMap { Int(exactly: $0) }', "Int?.none"),
    Mutant("newestislast", K, "max(newest[name] ?? version, version)", "version"),

    # The Iglu registry. Left out as equivalent: igluFiles' `{ first, _ in first }`, as a registry
    # read from disk never lists a path twice; the writer's `catch { ... .fileWriteUnknown }`, as
    # Foundation's file errors are all CocoaError; igluRegistryFiles' vendor guard, which
    # igluFiles' own repeats before any file is read, and its `.filter(\.isIgluName)`, as igluFiles
    # throws invalidSchemaKey for any other name before a file is written; `committed[latestPath] ?? []`,
    # as the path is one of the keys; and `addition < .max`, as no registry holds N-0-Int.max.
    # And the empty name of isIgluName: TrackingPlan(schemas:) refuses an empty event name
    # (emptynameallowed), so no plan holds one. Unplantable: the static and server arms of the
    # registry switch and IgluRegistry(argument:)'s patterns are case patterns, and the guard of
    # JSON(parsing:) and differences(fromCommitted:) a list of conditions; their throws and returns
    # are planted below, and "A newest version that isn't a schema the plan wrote" pins the guard.
    Mutant("anyvendor", I, "guard vendor.isIgluVendor else { throw .invalidVendor }", "", mode="stmt"),
    Mutant("writeasserver", I, "igluFiles(vendor: vendor, registry: registry, carryingForward: igluRegistryFiles(in: directory, vendor: vendor))", "igluFiles(vendor: vendor, registry: .server, carryingForward: igluRegistryFiles(in: directory, vendor: vendor))"),
    # After writeasserver's, the text holds two copies; the second is the original's.
    Mutant("noregistryread", I, "igluRegistryFiles(in: directory, vendor: vendor)", "[TrackingPlan.File]()", nth=1),
    Mutant("folderunchecked", I, "guard fileManager.fileExists(atPath: folderURL.path) else { continue }", "", mode="stmt"),
    Mutant("unlistableskipped", I, "throw .fileSystem(CocoaError(error, path: folderURL.path, otherwise: .fileReadUnknown))", "return []", mode="stmt"),
    Mutant("unreadableskipped", I, "throw .fileSystem(CocoaError(error, path: url.path, otherwise: .fileReadUnknown))", "continue", mode="stmt"),
    Mutant("anyentry", I, "entry.isSchemaVer", "true"),
    Mutant("schemaverparts", I, "parts.count == 3", "parts.count >= 2"),
    Mutant("schemavernoncanonical", I, "String($0) == part", "true"),
    Mutant("anyschemakey", I, "name.hasIgluSchemaKey(version: version)", "true"),
    Mutant("folderlayout", I, '"schemas/\\(vendor)/\\(name)/jsonschema/"', '"schemas/\\(vendor)/\\(name)/"'),
    Mutant("noncanonicaladdition", I, "String(addition) == digits", "true"),
    Mutant("oldestaddition", I, "additions.max()", "additions.min()"),
    Mutant("corruptwritten", I, "throw .fileSystem(CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: latestPath]))", "return try igluFile(vendor: vendor, addition: 0, keepingRemovedFrom: nil)", mode="stmt"),
    Mutant("corruptcode", I, "CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: latestPath])", "CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: latestPath])"),
    # After corruptcode's, the text holds two copies; the second is the original's.
    Mutant("corruptpath", I, "[NSFilePathErrorKey: latestPath]", "[NSFilePathErrorKey: folder]", nth=1),
    Mutant("unchangedrewritten", I, "differences.isEmpty", "false"),
    Mutant("breakingwritten", I, "differences.contains(where: \\.isBreaking)", "false"),
    Mutant("compatiblebreaking", I, "differences.contains(where: \\.isBreaking)", "!differences.isEmpty"),
    # serverrefuses and staticsupersedes come before the mutants inside the server arm's call;
    # staticsupersedes' replacement then holds a second copy of it, after the original.
    Mutant("serverrefuses", I, "return try igluFile(vendor: vendor, addition: latest + 1, keepingRemovedFrom: latestDocument)", "throw IgluExportError.additionNeedsNewVersion(event: name, version: version)", mode="stmt"),
    Mutant("staticsupersedes", I, "throw .additionNeedsNewVersion(event: name, version: version)", "return try igluFile(vendor: vendor, addition: latest + 1, keepingRemovedFrom: latestDocument)", mode="stmt"),
    Mutant("nextkeepsnothing", I, "latestDocument", "JSON?.none", nth=2),
    Mutant("nextsameaddition", I, "latest + 1", "latest", nth=0),
    Mutant("staticasserver", I, "schema.igluFile(vendor: vendor, registry: registry, committed: committedFiles)", "schema.igluFile(vendor: vendor, registry: .server, committed: committedFiles)"),
    Mutant("allofallowed", I, "throw .allOf(event: name, version: version)", "", mode="stmt"),
    Mutant("allofanyname", I, 'members["properties"]?.object?.values.contains(where: { $0.object?["allOf"] != nil }) == true', 'members["properties"]?.object?.keys.contains("allOf") == true || members["properties"]?.object?.values.contains(where: { $0.object?["allOf"] != nil }) == true'),
    Mutant("idkept", I, 'members["$id"] = nil', "", mode="stmt"),
    Mutant("metaschema", I, '"http://iglucentral.com/schemas/com.snowplowanalytics.self-desc/schema/jsonschema/1-0-0#"', '"http://iglucentral.com/schemas/com.snowplowanalytics.self-desc/schema/jsonschema/1-0-0"'),
    Mutant("selfformat", I, '.string("jsonschema")', '.string("json")'),
    Mutant("selfvendor", I, ".string(vendor)", ".string(name)"),
    Mutant("nosupersedes", I, "addition > 0", "false"),
    Mutant("supersedesfirst", I, "addition > 0", "addition >= 0"),
    Mutant("supersedeslast", I, "0..<addition", "addition - 1..<addition"),
    Mutant("writeeverything", I, "guard fileManager.contents(atPath: url.path) != contents else { continue }", "", mode="stmt"),
    Mutant("nodirectories", I, "try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)", "", mode="stmt"),
    Mutant("igludifferencesnone", K, "EventContract.differences(from: [committed], to: [EventContract(schema: self)])", "[TrackingPlanDifference]()"),
    Mutant("vendoroption", C, "!arguments[1].isOption", "true", nth=1),
    Mutant("directoryoption", C, "!arguments[3].isOption", "true"),
    Mutant("staticasserverargument", C, "self = .staticRepository", "self = .server", mode="stmt"),
    # After staticasserverargument's, the text holds a second copy, after the original.
    Mutant("serverasstaticargument", C, "self = .server", "self = .staticRepository", nth=0, mode="stmt"),
    Mutant("anykindargument", C, "return nil", "self = .server", mode="stmt"),
    Mutant("anyiglu", C, 'arguments[0] == "iglu"', "true"),
    Mutant("igluvendorargument", C, "writeIglu($0, vendor: arguments[1], registry: registry, to: arguments[3])", "writeIglu($0, vendor: arguments[2], registry: registry, to: arguments[3])"),
    Mutant('igluvendorstatus', C, 'return TrackingPlanCommandResult(status: 64, standardError: "error: \\(vendor) is not an Iglu vendor: use reverse domain notation, labels of ASCII letters, digits, - and _ joined by . (com.acme)")', 'return TrackingPlanCommandResult(status: 65, standardError: "error: \\(vendor) is not an Iglu vendor: use reverse domain notation, labels of ASCII letters, digits, - and _ joined by . (com.acme)")', mode="stmt"),
    Mutant('iglukeystatus', C, 'return TrackingPlanCommandResult(status: 65, standardError: "error: event \\(event), version \\(version), has no Iglu schema name: a name of ASCII letters, digits, - and _, and a version of 1 or more")', 'return TrackingPlanCommandResult(status: 73, standardError: "error: event \\(event), version \\(version), has no Iglu schema name: a name of ASCII letters, digits, - and _, and a version of 1 or more")', mode="stmt"),
    Mutant('igluallofstatus', C, 'return TrackingPlanCommandResult(status: 65, standardError: "error: event \\(event), version \\(version), needs allOf, which Snowplow\'s validation doesn\'t support: constrain each property with one pattern")', 'return TrackingPlanCommandResult(status: 0, standardError: "error: event \\(event), version \\(version), needs allOf, which Snowplow\'s validation doesn\'t support: constrain each property with one pattern")', mode="stmt"),
    Mutant('iglubreakingstatus', C, 'return TrackingPlanCommandResult(status: 65, standardError: "error: event \\(event), version \\(version), changed in a way its published schema\'s payloads may fail: raise the event\'s version")', 'return TrackingPlanCommandResult(status: 0, standardError: "error: event \\(event), version \\(version), changed in a way its published schema\'s payloads may fail: raise the event\'s version")', mode="stmt"),
    Mutant('iglustaticstatus', C, 'return TrackingPlanCommandResult(status: 65, standardError: "error: event \\(event), version \\(version), changed, which a static repository can\'t publish at the same version: raise the event\'s version")', 'return TrackingPlanCommandResult(status: 0, standardError: "error: event \\(event), version \\(version), changed, which a static repository can\'t publish at the same version: raise the event\'s version")', mode="stmt"),
    Mutant('iglufilestatus', C, 'return TrackingPlanCommandResult(status: 73, standardError: "error: couldn\'t read or write the Iglu registry in \\(directory): \\(cause.localizedDescription)")', 'return TrackingPlanCommandResult(status: 65, standardError: "error: couldn\'t read or write the Iglu registry in \\(directory): \\(cause.localizedDescription)")', mode="stmt"),
]
