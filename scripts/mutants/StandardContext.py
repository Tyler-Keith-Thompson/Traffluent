# Planted bugs for StandardContext. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/StandardContext/<file> (or `nth=` picks one), and mode="stmt" replaces whole
# statements rather than an expression. Every mutant must be caught; one that survives needs a test,
# or a note here saying why it is equivalent to the original.
#
# They cover the decisions: each enricher sets its own key; the static values are the ones read as
# the enricher was made, never read again per event; the network's connection is read per event,
# and its path mapped to a connection; and the identifier for vendor absent where the system has
# none, never made up, and carried only by its own enricher. The platform reads only an Apple
# device runs (UIKit's identifier, a device's hw.machine) get none: the Mac running the mutants
# can't reach them.

TESTS = ["StandardContextTests"]

A = "Enricher+Application.swift"
AK = "ApplicationKey+Bundle.swift"
D = "Enricher+Device.swift"
DK = "DeviceKey+Current.swift"
O = "Enricher+OperatingSystem.swift"
OK = "OperatingSystemKey+Current.swift"
L = "Enricher+Locale.swift"
N = "Enricher+Network.swift"
NK = "NetworkKey+Path.swift"
V = "Enricher+VendorIdentifier.swift"
VK = "VendorIdentifierKey.swift"

MUTANTS = [
    # Each enricher sets its own key.
    Mutant("applicationnokey", A, "            context[ApplicationKey.self] = application", "            ()", mode="stmt"),
    Mutant("devicenokey", D, "                context[DeviceKey.self] = device", "                ()", mode="stmt"),
    Mutant("operatingsystemnokey", O, "            context[OperatingSystemKey.self] = operatingSystem", "            ()", mode="stmt"),
    Mutant("localenokey", L, "            context[LocaleKey.self] = locale", "            ()", mode="stmt"),
    Mutant("networknokey", N, "                context[NetworkKey.self] = connection", "                ()", mode="stmt"),
    Mutant("vendornokey", V, "            context[VendorIdentifierKey.self] = value", "            ()", mode="stmt"),
    # The static values: the ones the enricher was made with, not read again per event.
    Mutant("applicationperevent", A, "context[ApplicationKey.self] = application", "context[ApplicationKey.self] = ApplicationKey.Value.current", mode="stmt"),
    Mutant("deviceperevent", D, "context[DeviceKey.self] = device", "context[DeviceKey.self] = DeviceKey.Value.current ?? device", mode="stmt"),
    Mutant("operatingsystemperevent", O, "context[OperatingSystemKey.self] = operatingSystem", "context[OperatingSystemKey.self] = OperatingSystemKey.Value.current", mode="stmt"),
    Mutant("localeperevent", L, "context[LocaleKey.self] = locale", "context[LocaleKey.self] = Locale(identifier: \"en_US_POSIX\")", mode="stmt"),
    # What the platform reads.
    Mutant("versionisbuild", AK, "\"CFBundleShortVersionString\"", "\"CFBundleVersion\""),
    Mutant("osversionnopatch", OK, "        return OperatingSystemKey.Value(name: name, version: \"\\(version.majorVersion).\\(version.minorVersion).\\(version.patchVersion)\")", "        return OperatingSystemKey.Value(name: name, version: \"\\(version.majorVersion).\\(version.minorVersion)\")", mode="stmt"),
    Mutant("padisphone", DK, "            self = .pad", "            self = .phone", mode="stmt"),
    # The network: read per event, and a path mapped to its connection.
    Mutant("networkonce", N, "connection()", "Optional(NetworkKey.Value.wifi)"),
    Mutant("requiresconnectionisonline", NK, "status == .satisfied", "status != .unsatisfied"),
    Mutant("cellularbeforewifi", NK, "usesInterfaceType(.wifi)", "usesInterfaceType(.cellular)"),
    # The identifier for vendor: never made up, and none on macOS.
    Mutant("vendormadeup", V, "            return Enricher { _ in }", "            return vendorIdentifier(UUID())", mode="stmt"),
    Mutant("vendoronmac", VK, "        nil", "        UUID()", mode="stmt"),
]
