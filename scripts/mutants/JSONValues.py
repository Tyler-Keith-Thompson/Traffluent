# Planted bugs for JSONValues; run with `just mutate JSONValues`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in Sources/JSONValues/<file>
# (or `nth=` picks one), and mode="stmt" replaces whole statements rather than an expression.
# Every mutant must be caught; one that survives needs a test, or a note here saying why it is
# equivalent to the original.
#
# Known equivalent mutants (left out, as they would survive by design):
# - Trying Int64 before Bool in JSON's decoding: JSONDecoder reads no integer from `true` or `false`
#   on any platform, so the order picks the same case.

TESTS = ["JSONValuesTests"]

J = "JSON.swift"

MUTANTS = [
    # The rendering. The keys are sorted three times: nth=0 is the compact form's, nth=1 the
    # minified form's, nth=2 the rendered form's.
    Mutant("emptyarraymultiline", J, "!elements.isEmpty", "true"),
    Mutant("emptyobjectmultiline", J, "!members.isEmpty", "true"),
    Mutant("arrayindentwide", J, 'indentation + "  "', 'indentation + "    "', nth=0),
    Mutant("objectindentwide", J, 'indentation + "  "', 'indentation + "    "', nth=1),
    Mutant("arraytrailingcomma", J, 'offset == elements.count - 1 ? "\\n" : ",\\n"', '",\\n"'),
    Mutant("objecttrailingcomma", J, 'offset == sorted.count - 1 ? "\\n" : ",\\n"', '",\\n"'),
    Mutant("keysreversed", J, "$0.key.utf8.lexicographicallyPrecedes($1.key.utf8)", "$1.key.utf8.lexicographicallyPrecedes($0.key.utf8)", nth=2),
    Mutant("colonspaced", J, '": "', '" : "', nth=1),
    Mutant("booleanalwaystrue", J, 'boolean ? "true" : "false"', '"true"'),
    Mutant("quoteunescaped", J, r'"\\\""', r'"\""'),
    Mutant("nonfinitenumberwritten", J, "!number.isFinite", "false"),
    Mutant("backslashunescaped", J, r'"\\\\"', r'"\\"'),
    Mutant("newlineraw", J, r'"\\n"', r'"\n"'),
    Mutant("controlnotpadded", J, "4 - hex.count", "2 - hex.count"),
    Mutant("controllowercase", J, "String(scalar.value, radix: 16, uppercase: true)", "String(scalar.value, radix: 16, uppercase: false)"),
    # The first copy is .null's, the second a non-finite number's.
    Mutant("nullrendered", J, 'text += "null"', 'text += "nil"', mode="stmt", nth=0),
    # The minified form.
    Mutant("minifiedunsorted", J, "$0.key.utf8.lexicographicallyPrecedes($1.key.utf8)", "$1.key.utf8.lexicographicallyPrecedes($0.key.utf8)", nth=1),
    Mutant("minifiedcolonspaced", J, '":"', '": "'),
    Mutant("minifiedarrayspaced", J, '","', '", "', nth=0),
    Mutant("minifiedobjectspaced", J, '","', '", "', nth=1),
    # Reading and the one-line form.
    Mutant("nullunread", J, "container.decodeNil()", "false"),
    Mutant("compactarrayunspaced", J, '", "', '","', nth=0),
    Mutant("compactobjectunspaced", J, '", "', '","', nth=1),
    Mutant("compactcolon", J, 'JSON.string($0.key).compact + ": "', 'JSON.string($0.key).compact + ":"'),
    Mutant("compactunsorted", J, "$0.key.utf8.lexicographicallyPrecedes($1.key.utf8)", "$1.key.utf8.lexicographicallyPrecedes($0.key.utf8)", nth=0),
    # Numbers.
    Mutant("wholenumberfractional", J, "return .integer(Int64(value))", "return .number(value)", mode="stmt"),
    Mutant("fractionnotdecoded", J, "self = json", "self = .null", mode="stmt"),
    Mutant("hugenumberinteger", J, "value < 9_223_372_036_854_775_808", "true"),
]
