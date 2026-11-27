# Planted bugs for Events; run with `just mutate Events`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in Sources/Events/<file>
# (or `nth=` picks one), and mode="stmt" replaces whole statements rather than an expression.
# Every mutant must be caught; one that survives needs a test, or a note here saying why it is
# equivalent to the original.
#
# Known equivalent mutants (they survive by design):
# - Dropping `hasher.combine(keyword)` from Constraint's hash: equal constraints still hash
#   alike, which is all Hashable asks; only a hash-quality measurement could tell.
# - Event's default `constraintViolation()` returning a violation: its text, `{ nil }`, isn't
#   unique in the file to plant; EventConstraintTests pins the default.
# - A pattern check's fallback when the pattern doesn't compile: the factory compiled it already,
#   so the fallback can't run.
# - Discovery's ELF reader (`sections()` under `#if objectFormat(ELF)`) and `placeholderRecord` have
#   no mutants: mutation runs on the Mac, which compiles the Mach-O reader alone, so a mutant there
#   would never be built. The placeholder is load-bearing on ELF: without a record in the section,
#   the linker defines no `__start_trfl_events`/`__stop_trfl_events` and a program with no events
#   fails to link. The Linux CI run of EventDiscoveryTests covers both.
# - Discovery's skip of the shared cache's images (`MH_DYLIB_IN_CACHE`): those system images hold
#   no events section, so reading them finds nothing either; only the walk's time differs.
# - Discovery's `size > 0` guard: an empty section is an empty buffer, which holds no records.

# EventDiscoveryTests, then EventDiscoveryDuplicateTests, reach discovery (EventDiscovery.swift,
# DiscoveredEvent.swift) and the list-free spellings it feeds in Persistence, GRDBPersistence and
# TrackingPlans (module=).
TESTS = ["EventsTests", "EventDiscoveryTests", "EventDiscoveryDuplicateTests"]

L = "SourceLocation.swift"
R = "EventRecord.swift"
E = "Event.swift"
K = "ConsentCategory.swift"
V = "Sensitive.swift"
S = "EventSchema.swift"

C = "Constraint.swift"
RF = "Refined.swift"
VK = "ValidationKeyword.swift"
CV = "ConstraintViolation.swift"

MUTANTS = [
    Mutant("modulewholefileid", L, 'String(fileID.prefix { $0 != "/" })', "fileID"),
    Mutant("modulestopsatdot", L, '$0 != "/"', '$0 != "."'),
    Mutant("filefromfileid", L, "self.file = file", "self.file = fileID", mode="stmt"),
    Mutant("fileidfromfile", L, "self.fileID = fileID", "self.fileID = file", mode="stmt"),
    Mutant("functionempty", L, "self.function = function", 'self.function = ""', mode="stmt"),
    Mutant("linefromcolumn", L, "self.line = line", "self.line = column", mode="stmt"),
    Mutant("columnfromline", L, "self.column = column", "self.column = line", mode="stmt"),
    Mutant("recordnamefixed", R, "type(of: event).name", '"Event"'),
    Mutant("recordtimestampfixed", R, "self.timestamp = timestamp", "self.timestamp = Date(timeIntervalSince1970: 0)", mode="stmt"),
    Mutant("recordcontextdropped", R, "self.context = context", "self.context = .topLevel", mode="stmt"),
    Mutant("redeliveredforced", R, "self.isRedelivered = isRedelivered", "self.isRedelivered = true", mode="stmt"),
    Mutant("redeliveredignored", R, "self.isRedelivered = isRedelivered", "self.isRedelivered = false", mode="stmt"),
    Mutant("tagdropped", R, "self.deliveryTag = deliveryTag", "self.deliveryTag = nil", mode="stmt"),
    # The record's identifier: kept as given, and random by default.
    Mutant("idignored", R, "self.id = id", "self.id = UUID(uuid: (1, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 0))", mode="stmt"),
    Mutant("constantdefaultid", R, "UUID()", "UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 0))"),
    # The default, after the `false`s of the doc comments before it.
    Mutant("defaultredelivered", R, "false", "true", nth=2),
    Mutant("tagpositionzero", "DeliveryTag.swift", "self.position = position", "self.position = 0", mode="stmt"),
    Mutant("defaultnamelowercased", E, "String(describing: Self.self)", "String(describing: Self.self).lowercased()"),
    Mutant("defaultcategory", E, ".analytics", ".advertising"),
    Mutant("recordcategoryfixed", R, "type(of: event).consentCategory", ".analytics"),
    Mutant("revealsredacted", R, "revealsSensitiveValues ? sensitive.value : nil", "sensitive.value"),
    Mutant("recordreveals", R, "revealsSensitiveValues = false", "revealsSensitiveValues = true", mode="stmt"),
    Mutant("categoryunnamed", K, "self.name = name", 'self.name = ""', mode="stmt"),
    Mutant("advertisingnamed", K, 'ConsentCategory("advertising")', 'ConsentCategory("analytics")'),
    Mutant("descriptionreveals", V, '"<redacted>"', '"\\(value)"', nth=0),
    Mutant("debugdescriptionreveals", V, '"Sensitive(<redacted>)"', '"Sensitive(\\(value))"'),
    Mutant("mirrorreveals", V, "Mirror(self, children: [], displayStyle: .struct)", 'Mirror(self, children: ["value": value], displayStyle: .struct)'),
    Mutant("propertyunnamed", S, "            self.name = name", '            self.name = ""', mode="stmt"),
    Mutant("propertytypeunnamed", S, "            self.typeName = typeName", '            self.typeName = ""', mode="stmt"),
    Mutant("propertyneveroptional", S, "            self.isOptional = isOptional", "            self.isOptional = false", mode="stmt"),
    # The schema's own `self.name = name`, after the property's, which holds the text too.
    Mutant("schemaunnamed", S, "        self.name = name", '        self.name = ""', mode="stmt", nth=1),
    Mutant("schemaversionzero", S, "        self.version = version", "        self.version = 0", mode="stmt"),
    Mutant("schemaconsentfixed", S, "        self.consentCategory = consentCategory", "        self.consentCategory = .analytics", mode="stmt"),
    Mutant("schemanoproperties", S, "        self.properties = properties", "        self.properties = []", mode="stmt"),
    # Constraint: each keyword's check, its bound included, and the errors of its arguments.
    Mutant("minlengthexclusive", C, "$0.unicodeScalars.count >= length", "$0.unicodeScalars.count > length"),
    Mutant("minlengthcharacters", C, "$0.unicodeScalars.count >= length", "$0.count >= length"),
    Mutant("maxlengthexclusive", C, "$0.unicodeScalars.count <= length", "$0.unicodeScalars.count < length"),
    Mutant("maxlengthcharacters", C, "$0.unicodeScalars.count <= length", "$0.count <= length"),
    Mutant("negativeminlength", C, "length >= 0", "length >= -1", nth=0),
    Mutant("negativemaxlength", C, "length >= 0", "length >= -1", nth=1),
    Mutant("patternalwaysmatches", C, "return value.contains(regex)", "return true", mode="stmt"),
    Mutant("exampleunchecked", C, "guard example.contains(regex) else { throw .exampleMismatch }", "", mode="stmt"),
    # The guard binds the regex, so its error is swapped rather than the statement dropped.
    Mutant("invalidpatternmisnamed", C, "throw .invalidPattern", "throw .exampleMismatch", mode="stmt"),
    # The integer bounds come first in the file, then the floating-point ones.
    Mutant("integerminimumexclusive", C, "$0 >= bound", "$0 > bound", nth=0),
    Mutant("floatminimumexclusive", C, "$0 >= bound", "$0 > bound", nth=1),
    Mutant("integermaximumexclusive", C, "$0 <= bound", "$0 < bound", nth=0),
    Mutant("floatmaximumexclusive", C, "$0 <= bound", "$0 < bound", nth=1),
    Mutant("integerminimumkeyword", C, ".minimum(exact)", ".maximum(exact)"),
    # An integer bound rounded to the nearest Double, rather than refused, for each of the two.
    # Float and Double bounds are always exact once finite, so exactFiniteDouble's
    # Double(exactly:) has no mutant that a test could catch.
    Mutant("inexactminimumaccepted", C, "Double(exactly: bound)", "Optional(Double(bound))", nth=0),
    Mutant("inexactmaximumaccepted", C, "Double(exactly: bound)", "Optional(Double(bound))", nth=1),
    # Infinity is exact, so without the guard it is accepted; NaN would still throw, as inexact.
    Mutant("nonfiniteaccepted", C, "guard isFinite else { throw .nonFiniteBound }", "", mode="stmt"),
    Mutant("minitemsexclusive", C, "$0.count >= count", "$0.count > count"),
    Mutant("maxitemsexclusive", C, "$0.count <= count", "$0.count < count"),
    Mutant("negativeminitems", C, "count >= 0", "count >= -1", nth=0),
    Mutant("negativemaxitems", C, "count >= 0", "count >= -1", nth=1),
    Mutant("constraintsallequal", C, "lhs.keyword == rhs.keyword", "true"),
    # Refined: the initializer's errors, and the conformances.
    Mutant("unsatisfiednotthrown", RF, "throw broken.keyword.unsatisfied", "", mode="stmt"),
    Mutant("lastbroken", RF, "constraints.first(where: { !$0.isSatisfied(by: value) })", "constraints.last(where: { !$0.isSatisfied(by: value) })"),
    Mutant("invalidconstraintnotthrown", RF, "            throw .invalidConstraint", "            constraints = []", mode="stmt"),
    Mutant("comparereversed", RF, "lhs.value < rhs.value", "lhs.value > rhs.value"),
    Mutant("refineddescriptionempty", RF, "String(describing: value)", '""'),
    Mutant("refinedkeywordsnone", RF, "Rule.constraints.map(\\.keyword)", "[]"),
    # ValidationKeyword: the keywords of a type, forwarded through Optional and Sensitive.
    Mutant("ruleflaginverted", RF, "(try? Rule.constraints) == nil", "(try? Rule.constraints) != nil"),
    Mutant("keypathnotflagged", VK, "(Value.self as? any RefinedKeywords.Type)?.hasInvalidConstraint ?? false", "false"),
    Mutant("optionalflagnotforwarded", VK, "Wrapped.hasInvalidConstraint", "false"),
    Mutant("sensitiveflagnotforwarded", VK, "Value.hasInvalidConstraint", "false"),
    Mutant("floatboundwidened", C, "return Double(String(describing: self)) ?? Double(self)", "return Double(self)", mode="stmt"),
    Mutant("keywordsofnone", VK, "(type as? any RefinedKeywords.Type)?.keywords ?? []", "[]"),
    Mutant("keypathkeywordsnone", VK, "keywords(of: Value.self)", "[]"),
    Mutant("optionalnotforwarded", VK, "Wrapped.keywords", "[]"),
    Mutant("sensitivenotforwarded", VK, "Value.keywords", "[]"),
    Mutant("minlengthdescribed", VK, '"minLength \\(length)"', '"maxLength \\(length)"'),
    Mutant("patterndescribed", VK, '"pattern \\(pattern)"', '"pattern \\(pattern)$"'),
    Mutant("wholeboundfraction", VK, "return String(Int64(self))", "return description", mode="stmt"),
    Mutant("hugeboundinteger", VK, "abs(self) <= 9_007_199_254_740_992", "true"),
    Mutant("violationunnamed", CV, "self.property = property", 'self.property = ""', mode="stmt", nth=0),
    Mutant("invalidviolationunnamed", CV, "self.property = property", 'self.property = ""', mode="stmt", nth=1),
    Mutant("violationkeywordfixed", CV, "cause = .unsatisfied(keyword)", "cause = .unsatisfied(.minLength(0))", mode="stmt"),
    Mutant("invaliderrorfixed", CV, "cause = .invalidConstraint(declaration: declaration, error: error)", "cause = .invalidConstraint(declaration: declaration, error: .nonFiniteBound)", mode="stmt"),
    Mutant("invaliddescribed", CV, '"\\"\\(property)\\"\'s \\(declaration) can\'t be built (\\(error))"', '"\\"\\(property)\\" breaks \\(declaration)"'),
    Mutant("violationdescribed", CV, '"\\"\\(property)\\" breaks \\(keyword)"', '"\\(property) breaks \\(keyword)"'),
    Mutant("schemakeywordsdropped", S, "            self.keywords = keywords", "            self.keywords = []", mode="stmt"),
    # The schema version's default and a property's default value (TRAF-18). The sixth `1` in
    # Event.swift is schemaVersion's body: the doc comments hold three, and the switches of the
    # two mutants before it, __mutant(17) and __mutant(18), two more.
    Mutant("defaultschemaversiontwo", E, "1", "2", nth=5),
    Mutant("defaultvaluedropped", S, "            self.hasDefaultValue = hasDefaultValue", "            self.hasDefaultValue = false", mode="stmt"),
    # Enricher (moved from Trackers' spec with the type).
    Mutant("enricherinert", "Enricher.swift", "enrich(&record.context)", "", mode="stmt"),
    Mutant("contextaddsrecords", "Enricher.swift", "addsRecords = false", "addsRecords = true", mode="stmt"),
    # After contextaddsrecords', the text holds two copies; the second is the original's.
    Mutant("recordsaddnone", "Enricher.swift", "addsRecords = true", "addsRecords = false", nth=1, mode="stmt"),
    # EventSchema.Enumeration (TRAF-91): a raw-value enum's raw values, given or read at run time.
    Mutant("enumanyrawtype", "EventSchema+Enumeration.swift", "Enumeration.mapsRawValue(of: Case.self)", "true"),
    Mutant("enumtypenamefixed", "EventSchema+Enumeration.swift", "typeName = String(describing: Case.self)", 'typeName = "Case"', mode="stmt"),
    Mutant("enumrawtypenamefixed", "EventSchema+Enumeration.swift", "rawTypeName = String(describing: Case.RawValue.self)", 'rawTypeName = "String"', mode="stmt"),
    Mutant("enumnocasesempty", "EventSchema+Enumeration.swift", "values.isEmpty || converted.contains(nil)", "converted.contains(nil)"),
    Mutant("enumoverflowignored", "EventSchema+Enumeration.swift", "values.isEmpty || converted.contains(nil)", "values.isEmpty"),
    Mutant("enumrepeated", "EventSchema+Enumeration.swift", "converted.compactMap { $0 }.filter { seen.insert($0).inserted }", "converted.compactMap { $0 }"),
    Mutant("enumwrapperignored", "EventSchema+Enumeration.swift", "if let wrapper = type as? any EnumerationWrapper.Type {\n                return enumeration(of: wrapper.wrappedType)\n            }", "", mode="stmt"),
    Mutant("enumcasesignored", "EventSchema+Enumeration.swift", "if let iterable = type as? any (RawRepresentable & CaseIterable).Type {\n                return listing(iterable)\n            }", "", mode="stmt"),
    Mutant("enumoptionalopaque", "EnumerationWrapper.swift", "Wrapped.self", "Int.self"),
    Mutant("enumsensitiveopaque", "EnumerationWrapper.swift", "Value.self", "Int.self"),
    Mutant("enumarrayopaque", "EnumerationWrapper.swift", "Element.self", "Int.self"),
    Mutant("enumunknownlisted", "EventSchema+Enumeration.swift", "$0.rawValues == nil ? nil : $0", "$0"),
    Mutant("enumstringlost", "EventSchema+Enumeration.swift", "self = .string(string)", 'self = .string("")', mode="stmt"),
    Mutant("enumintegerlost", "EventSchema+Enumeration.swift", "self = .integer(exact)", "self = .integer(0)", mode="stmt"),
    Mutant("schemaenumerationdropped", S, "self.enumeration = enumeration", "self.enumeration = nil", mode="stmt"),
    # Discovery: the records read, their order, and the list-free spellings built on them.
    Mutant("discoverykindignored", "EventDiscovery.swift", "$0.kind == kind", "true"),
    Mutant("discoverytypeunchecked", "EventDiscovery.swift", "expectedType.load(as: Any.Type.self) == DiscoveredEvent.self", "true"),
    Mutant("discoverynamesreversed", "DiscoveredEvent.swift", "name.utf8.lexicographicallyPrecedes(otherName.utf8)", "otherName.utf8.lexicographicallyPrecedes(name.utf8)"),
    Mutant("discoveryversionsreversed", "DiscoveredEvent.swift", "type.schemaVersion < other.type.schemaVersion", "type.schemaVersion > other.type.schemaVersion"),
    Mutant("discoverytypenamesreversed", "DiscoveredEvent.swift", "typeNames.0.utf8.lexicographicallyPrecedes(typeNames.1.utf8)", "typeNames.1.utf8.lexicographicallyPrecedes(typeNames.0.utf8)"),
    Mutant("segmentstorediscoversnone", "SegmentStore.swift", "try self.init(events: DiscoveredEvent.all.map(\\.type), directory: directory, byteBound: byteBound, segmentByteCount: segmentByteCount)", "try self.init(events: [], directory: directory, byteBound: byteBound, segmentByteCount: segmentByteCount)", mode="stmt", module="Persistence"),
    Mutant("databasestorediscoversnone", "DatabaseStore.swift", "try self.init(events: DiscoveredEvent.all.map(\\.type), database: database, table: table, byteBound: byteBound)", "try self.init(events: [], database: database, table: table, byteBound: byteBound)", mode="stmt", module="GRDBPersistence"),
    Mutant("plandiscoversnone", "TrackingPlan.swift", "try self.init(events: DiscoveredEvent.all.map { (schema: $0.schema, typeName: String(reflecting: $0.type)) })", "try self.init(events: [])", mode="stmt", module="TrackingPlans"),
    Mutant("plantypesunnamed", "TrackingPlan.swift", "String(reflecting: $0.type)", "nil", module="TrackingPlans"),
    Mutant("plantiesreversed", "TrackingPlan.swift", "$0.offset < $1.offset", "$0.offset > $1.offset", module="TrackingPlans"),
    Mutant("discoveryrepeated", "DiscoveredEvent.swift", "seen.insert(ObjectIdentifier($0.type)).inserted", "true"),
]
