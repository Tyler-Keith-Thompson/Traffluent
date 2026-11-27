// The plan as an Iglu registry: the layout of a static repository
// (https://docs.snowplow.io/docs/api-reference/iglu/iglu-repositories/static-repo/, read on
// 2026-11-27), self-describing schemas, and new versions that supersede the published ones
// (https://docs.snowplow.io/docs/event-studio/data-structures/superseding-and-patching/).

import Events
import Foundation
import Testing
import TrackingPlans

@Suite("TrackingPlan: Iglu export")
struct TrackingPlanIgluExportTests {
    static let signedUp = EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
        EventSchema.Property(name: "plan", typeName: "String", isOptional: false),
    ])

    static let signedUpWithReferrer = EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
        EventSchema.Property(name: "plan", typeName: "String", isOptional: false),
        EventSchema.Property(name: "referrer", typeName: "String", isOptional: true),
    ])

    static let signedUpRequiringReferrer = EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
        EventSchema.Property(name: "plan", typeName: "String", isOptional: false),
        EventSchema.Property(name: "referrer", typeName: "String", isOptional: false),
    ])

    static let checkoutStarted = EventSchema(name: "checkout_started", version: 3, consentCategory: .analytics, properties: [
        EventSchema.Property(name: "cartSize", typeName: "Int", isOptional: false),
    ])

    @Test("Each event and version is a file at schemas/<vendor>/<name>/jsonschema/<version>-0-0, in the plan's order")
    func layout() throws {
        let sut = try TrackingPlan(schemas: [Self.signedUp, Self.checkoutStarted])
        let expected = sut.schemas.map { "schemas/com.acme/\($0.name)/jsonschema/\($0.version)-0-0" }

        let actual = try sut.igluFiles(vendor: "com.acme", registry: .server, carryingForward: []).map(\.path)

        #expect(actual == expected)
        #expect(Set(actual) == ["schemas/com.acme/signed_up/jsonschema/1-0-0", "schemas/com.acme/checkout_started/jsonschema/3-0-0"])
    }

    @Test("A file is the plan's document as a self-describing schema: Iglu's meta-schema, self naming it, and no $id")
    func selfDescribing() throws {
        let sut = try TrackingPlan(schemas: [Self.checkoutStarted])
        let document = try #require(sut.files.first { $0.path == "checkout_started.v3.schema.json" })
        var expected = try #require(try JSONSerialization.jsonObject(with: Data(document.contents)) as? [String: Any])
        expected["$id"] = nil
        expected["$schema"] = "http://iglucentral.com/schemas/com.snowplowanalytics.self-desc/schema/jsonschema/1-0-0#"
        expected["self"] = ["vendor": "com.acme", "name": "checkout_started", "format": "jsonschema", "version": "3-0-0"]

        let file = try #require(try sut.igluFiles(vendor: "com.acme", registry: .server, carryingForward: []).first)

        let actual = try #require(try JSONSerialization.jsonObject(with: Data(file.contents)) as? [String: Any])
        // Compared as sorted JSON: NSDictionary's equality bridges values differently on Linux.
        let actualJSON = try JSONSerialization.data(withJSONObject: actual, options: .sortedKeys)
        let expectedJSON = try JSONSerialization.data(withJSONObject: expected, options: .sortedKeys)
        #expect(actualJSON == expectedJSON)
        #expect(actual["$supersedes"] == nil)
    }

    @Test("A registry holding the version the plan would write gives it back byte for byte")
    func unchanged() throws {
        let sut = try TrackingPlan(schemas: [Self.signedUp])
        let published = try sut.igluFiles(vendor: "com.acme", registry: .server, carryingForward: [])

        let actual = try sut.igluFiles(vendor: "com.acme", registry: .server, carryingForward: published)

        #expect(actual == published)
    }

    @Test("A compatible change is the next addition, superseding every earlier one, and keeps a removed property as deprecated")
    func additions() throws {
        let first = try TrackingPlan(schemas: [Self.signedUp])
        let second = try TrackingPlan(schemas: [Self.signedUpWithReferrer])
        let published = try first.igluFiles(vendor: "com.acme", registry: .server, carryingForward: [])
        let added = try second.igluFiles(vendor: "com.acme", registry: .server, carryingForward: published)
        let expectedPaths = ["schemas/com.acme/signed_up/jsonschema/1-0-1", "schemas/com.acme/signed_up/jsonschema/1-0-2"]
        let expectedSupersedes: [[String]] = [["1-0-0"], ["1-0-0", "1-0-1"]]

        let removed = try first.igluFiles(vendor: "com.acme", registry: .server, carryingForward: published + added)

        let actual = added + removed
        #expect(actual.map(\.path) == expectedPaths)
        let documents = try actual.map { try #require(try JSONSerialization.jsonObject(with: Data($0.contents)) as? [String: Any]) }
        #expect(documents.map { $0["$supersedes"] as? [String] } == expectedSupersedes)
        #expect(documents.map { ($0["self"] as? [String: Any])?["version"] as? String } == ["1-0-1", "1-0-2"])
        let referrer = ((documents[1]["properties"] as? [String: Any])?["referrer"] as? [String: Any])
        #expect(referrer?["deprecated"] as? Bool == true)
    }

    @Test("Exporting again after a property is removed gives back the addition that keeps it as deprecated, rather than another")
    func removedThenUnchanged() throws {
        let first = try TrackingPlan(schemas: [Self.signedUp])
        let second = try TrackingPlan(schemas: [Self.signedUpWithReferrer])
        let original = try first.igluFiles(vendor: "com.acme", registry: .server, carryingForward: [])
        let added = try second.igluFiles(vendor: "com.acme", registry: .server, carryingForward: original)
        let removed = try first.igluFiles(vendor: "com.acme", registry: .server, carryingForward: original + added)

        let actual = try first.igluFiles(vendor: "com.acme", registry: .server, carryingForward: original + added + removed)

        #expect(actual == removed)
    }

    @Test("A registry whose newest version means what the plan would write gives that file back as it is, however it is formatted, for either kind of registry", arguments: [IgluRegistry.server, .staticRepository])
    func reformattedUnchanged(registry: IgluRegistry) throws {
        let sut = try TrackingPlan(schemas: [Self.signedUp])
        let published = try #require(try sut.igluFiles(vendor: "com.acme", registry: registry, carryingForward: []).first)
        // Members in another order, indented, with CRLF line endings, as an editor or a Git
        // checkout might leave it.
        let object = try JSONSerialization.jsonObject(with: Data(published.contents))
        let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
        let reformatted = Array(String(decoding: pretty, as: UTF8.self).replacingOccurrences(of: "\n", with: "\r\n").utf8)
        let expected = [TrackingPlan.File(path: published.path, contents: reformatted)]

        let actual = try sut.igluFiles(vendor: "com.acme", registry: registry, carryingForward: expected)

        #expect(reformatted != published.contents)
        #expect(actual == expected)
    }

    @Test("A compatible change is written as the next addition for Iglu Server, and a breaking one at the same version throws breakingChange")
    func breakingChange() throws {
        let published = try TrackingPlan(schemas: [Self.signedUp]).igluFiles(vendor: "com.acme", registry: .server, carryingForward: [])
        let compatible = try TrackingPlan(schemas: [Self.signedUpWithReferrer])
        let breaking = try TrackingPlan(schemas: [Self.signedUpRequiringReferrer])
        let expectedPaths = ["schemas/com.acme/signed_up/jsonschema/1-0-1"]

        let actual = try compatible.igluFiles(vendor: "com.acme", registry: .server, carryingForward: published).map(\.path)

        #expect(actual == expectedPaths)
        #expect(throws: IgluExportError.breakingChange(event: "signed_up", version: 1)) {
            try breaking.igluFiles(vendor: "com.acme", registry: .server, carryingForward: published)
        }
        #expect(throws: IgluExportError.breakingChange(event: "signed_up", version: 1)) {
            try breaking.igluFiles(vendor: "com.acme", registry: .staticRepository, carryingForward: published)
        }
    }

    @Test("For a static repository, a new event is written as N-0-0, and a compatible change at a published version throws additionNeedsNewVersion")
    func staticRepository() throws {
        let first = try TrackingPlan(schemas: [Self.signedUp])
        let second = try TrackingPlan(schemas: [Self.signedUpWithReferrer])
        let expectedPaths = ["schemas/com.acme/signed_up/jsonschema/1-0-0"]

        let published = try first.igluFiles(vendor: "com.acme", registry: .staticRepository, carryingForward: [])

        #expect(published.map(\.path) == expectedPaths)
        #expect(published == (try first.igluFiles(vendor: "com.acme", registry: .server, carryingForward: [])))
        #expect(throws: IgluExportError.additionNeedsNewVersion(event: "signed_up", version: 1)) {
            try second.igluFiles(vendor: "com.acme", registry: .staticRepository, carryingForward: published)
        }
    }

    @Test("A newest version that isn't a schema the plan wrote throws fileSystem, as a file read corrupt, naming it", arguments: ["not JSON", "{}", #"{"title":"signed_up"}"#])
    func corruptNewest(contents: String) throws {
        let sut = try TrackingPlan(schemas: [Self.signedUp])
        let committed = [TrackingPlan.File(path: "schemas/com.acme/signed_up/jsonschema/1-0-0", contents: Array(contents.utf8))]
        let expected = IgluExportError.fileSystem(CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: "schemas/com.acme/signed_up/jsonschema/1-0-0"]))

        #expect(throws: expected) {
            try sut.igluFiles(vendor: "com.acme", registry: .server, carryingForward: committed)
        }
    }

    @Test("Writing a registry where a version of an event can't be read throws fileSystem and writes nothing")
    func unreadableVersion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        // A directory where a version's file should be: it lists, but can't be read as a file.
        let unreadable = directory.appendingPathComponent("schemas/com.acme/signed_up/jsonschema/1-0-0")
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        // checkout_started first, so a write before the read fails would show.
        let sut = try TrackingPlan(schemas: [Self.checkoutStarted, Self.signedUp])

        #expect {
            try sut.writeIgluRegistry(to: directory, vendor: "com.acme", registry: .server)
        } throws: { error in
            guard let error = error as? IgluExportError, case .fileSystem = error else { return false }
            return true
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("schemas/com.acme/checkout_started").path))
    }

    @Test("Writing a registry where an event's folder can't be listed throws fileSystem and writes nothing")
    func unlistableFolder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        // A file where the event's folder should be: it exists, but can't be listed. checkout_started
        // first, so a write before the listing fails would show.
        let folder = directory.appendingPathComponent("schemas/com.acme/signed_up/jsonschema")
        try FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        #expect(FileManager.default.createFile(atPath: folder.path, contents: Data("{}".utf8)))
        let sut = try TrackingPlan(schemas: [Self.checkoutStarted, Self.signedUp])

        #expect {
            try sut.writeIgluRegistry(to: directory, vendor: "com.acme", registry: .server)
        } throws: { error in
            guard let error = error as? IgluExportError, case .fileSystem = error else { return false }
            return true
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("schemas/com.acme/checkout_started").path))
    }

    @Test("Writing a registry reads only the files of its events named as SchemaVers, so another file in an event's folder is ignored")
    func otherFilesIgnored() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = directory.appendingPathComponent("schemas/com.acme/signed_up/jsonschema")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("1-0-x"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("1-0-01"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("1-0"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("1-0-0-0"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("1--0"), withIntermediateDirectories: true)
        let sut = try TrackingPlan(schemas: [Self.signedUp])
        let expected = try #require(try sut.igluFiles(vendor: "com.acme", registry: .server, carryingForward: []).first)

        try sut.writeIgluRegistry(to: directory, vendor: "com.acme", registry: .server)

        let actual = FileManager.default.contents(atPath: directory.appendingPathComponent(expected.path).path)
        #expect(actual == Data(expected.contents))
    }

    @Test("Writing a registry again leaves a version whose bytes are unchanged untouched")
    func unchangedNotRewritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sut = try TrackingPlan(schemas: [Self.signedUp])
        let file = directory.appendingPathComponent("schemas/com.acme/signed_up/jsonschema/1-0-0")
        try sut.writeIgluRegistry(to: directory, vendor: "com.acme", registry: .server)
        let expected = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: expected], ofItemAtPath: file.path)

        try sut.writeIgluRegistry(to: directory, vendor: "com.acme", registry: .server)

        let actual = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        #expect(actual == expected)
    }

    @Test("The newest addition is the one compared, whatever order the registry lists it in, and files of other versions or names are ignored")
    func newestAddition() throws {
        let first = try TrackingPlan(schemas: [Self.signedUp])
        let second = try TrackingPlan(schemas: [Self.signedUpWithReferrer])
        let original = try first.igluFiles(vendor: "com.acme", registry: .server, carryingForward: [])
        let added = try second.igluFiles(vendor: "com.acme", registry: .server, carryingForward: original)
        let unrelated = [
            TrackingPlan.File(path: "schemas/com.acme/signed_up/jsonschema/2-0-7", contents: Array("{}".utf8)),
            TrackingPlan.File(path: "schemas/com.acme/signed_up/jsonschema/1-0-08", contents: Array("{}".utf8)),
            TrackingPlan.File(path: "schemas/com.acme/signed_up/jsonschema/1-1-0", contents: Array("{}".utf8)),
            TrackingPlan.File(path: "schemas/com.other/signed_up/jsonschema/1-0-5", contents: Array("{}".utf8)),
        ]

        let actual = try second.igluFiles(vendor: "com.acme", registry: .server, carryingForward: unrelated + added + original)

        #expect(actual == added)
    }

    @Test("The export throws invalidVendor for a vendor Iglu doesn't take", arguments: ["", "com..acme", "com acme", ".com"])
    func invalidVendor(vendor: String) throws {
        let sut = try TrackingPlan(schemas: [Self.signedUp])

        #expect(throws: IgluExportError.invalidVendor) {
            try sut.igluFiles(vendor: vendor, registry: .server, carryingForward: [])
        }
    }

    @Test("The export throws invalidSchemaKey for an event whose name Iglu doesn't take or whose version is 0, and takes letters, digits, - and _", arguments: [
        ("Order Completed", 1, true), ("order.completed", 1, true), ("café", 1, true), ("signed_up", 0, true),
        ("signed_up", 1, false), ("Signed-Up_2", 1, false), ("a", 1, false),
    ])
    func invalidSchemaKey(name: String, version: Int, throwsError: Bool) throws {
        let sut = try TrackingPlan(schemas: [EventSchema(name: name, version: version, consentCategory: .analytics, properties: [])])
        let expected: IgluExportError? = throwsError ? .invalidSchemaKey(event: name, version: version) : nil

        let actual: IgluExportError?
        do {
            _ = try sut.igluFiles(vendor: "com.acme", registry: .server, carryingForward: [])
            actual = nil
        } catch {
            actual = error
        }

        #expect(actual == expected)
    }

    @Test("The export throws allOf for a property of two patterns, which needs allOf, and takes one pattern")
    func allOf() throws {
        let one = EventSchema(name: "searched", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "query", typeName: "String", isOptional: false, keywords: [.pattern("^a", example: "ab")]),
        ])
        let two = EventSchema(name: "searched", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "query", typeName: "String", isOptional: false, keywords: [.pattern("^a", example: "ab"), .pattern("b$", example: "ab")]),
        ])
        let named = EventSchema(name: "searched", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "allOf", typeName: "String", isOptional: false),
        ])

        #expect(throws: Never.self) {
            try TrackingPlan(schemas: [one]).igluFiles(vendor: "com.acme", registry: .server, carryingForward: [])
        }
        #expect(throws: Never.self) {
            try TrackingPlan(schemas: [named]).igluFiles(vendor: "com.acme", registry: .server, carryingForward: [])
        }
        #expect(throws: IgluExportError.allOf(event: "searched", version: 1)) {
            try TrackingPlan(schemas: [two]).igluFiles(vendor: "com.acme", registry: .server, carryingForward: [])
        }
    }

    @Test("Writing a registry creates its directories, writes each new version beside the earlier ones and deletes nothing")
    func writes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let kept = directory.appendingPathComponent("schemas/com.acme/signed_in/jsonschema/1-0-0")
        try FileManager.default.createDirectory(at: kept.deletingLastPathComponent(), withIntermediateDirectories: true)
        #expect(FileManager.default.createFile(atPath: kept.path, contents: Data("{}".utf8)))
        let first = try TrackingPlan(schemas: [Self.signedUp])
        let second = try TrackingPlan(schemas: [Self.signedUpWithReferrer])
        let expectedOriginal = try first.igluFiles(vendor: "com.acme", registry: .server, carryingForward: [])
        let expected = [
            "schemas/com.acme/signed_in/jsonschema/1-0-0",
            "schemas/com.acme/signed_up/jsonschema/1-0-0",
            "schemas/com.acme/signed_up/jsonschema/1-0-1",
        ]

        try first.writeIgluRegistry(to: directory, vendor: "com.acme", registry: .server)
        try second.writeIgluRegistry(to: directory, vendor: "com.acme", registry: .server)
        try second.writeIgluRegistry(to: directory, vendor: "com.acme", registry: .server)

        let actual = try #require(FileManager.default.subpaths(atPath: directory.path)).filter { $0.hasSuffix("-0-0") || $0.hasSuffix("-0-1") || $0.hasSuffix("-0-2") }.sorted()
        #expect(actual == expected)
        #expect(FileManager.default.contents(atPath: directory.appendingPathComponent(expectedOriginal[0].path).path) == Data(expectedOriginal[0].contents))
        #expect(FileManager.default.contents(atPath: kept.path) == Data("{}".utf8))
    }

    @Test("Writing a registry where a file can't be written throws fileSystem")
    func fileSystem() throws {
        let sut = try TrackingPlan(schemas: [Self.signedUp])
        let directory = URL(fileURLWithPath: "/dev/null/registry")

        #expect {
            try sut.writeIgluRegistry(to: directory, vendor: "com.acme", registry: .server)
        } throws: { error in
            guard let error = error as? IgluExportError, case .fileSystem = error else { return false }
            return true
        }
    }

    struct ExampleCommand: TrackingPlanCommand {
        static var trackingPlan: TrackingPlan {
            get throws(TrackingPlanError) {
                try TrackingPlan(schemas: [TrackingPlanIgluExportTests.signedUp])
            }
        }
    }

    struct UnnamableCommand: TrackingPlanCommand {
        static var trackingPlan: TrackingPlan {
            get throws(TrackingPlanError) {
                try TrackingPlan(schemas: [EventSchema(name: "Order Completed", version: 1, consentCategory: .analytics, properties: [])])
            }
        }
    }

    struct TwoPatternsCommand: TrackingPlanCommand {
        static var trackingPlan: TrackingPlan {
            get throws(TrackingPlanError) {
                try TrackingPlan(schemas: [EventSchema(name: "searched", version: 1, consentCategory: .analytics, properties: [
                    EventSchema.Property(name: "query", typeName: "String", isOptional: false, keywords: [.pattern("^a", example: "ab"), .pattern("b$", example: "ab")]),
                ])])
            }
        }
    }

    @Test("The command's iglu writes the registry and exits 0")
    func command() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let expectedStatus: Int32 = 0
        let expected = try ExampleCommand.trackingPlan.igluFiles(vendor: "com.acme", registry: .server, carryingForward: []).map { Data($0.contents) }

        let actual = ExampleCommand.run(arguments: ["iglu", "com.acme", "server", directory.path])

        #expect(actual.status == expectedStatus)
        #expect(FileManager.default.contents(atPath: directory.appendingPathComponent("schemas/com.acme/signed_up/jsonschema/1-0-0").path).map { [$0] } == expected)
    }

    struct ReferrerCommand: TrackingPlanCommand {
        static var trackingPlan: TrackingPlan {
            get throws(TrackingPlanError) {
                try TrackingPlan(schemas: [TrackingPlanIgluExportTests.signedUpWithReferrer])
            }
        }
    }

    struct RequiredReferrerCommand: TrackingPlanCommand {
        static var trackingPlan: TrackingPlan {
            get throws(TrackingPlanError) {
                try TrackingPlan(schemas: [TrackingPlanIgluExportTests.signedUpRequiringReferrer])
            }
        }
    }

    @Test("The command's iglu static writes the registry, and exits 65 for a compatible change at a published version, as either kind does for a breaking one, writing nothing; iglu server then writes the change as an addition")
    func commandChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let expected: [Int32] = [0, 65, 65, 65]
        let expectedAfterServer: [Int32] = [0]
        let folder = directory.appendingPathComponent("schemas/com.acme/signed_up/jsonschema").path

        let actual = [
            ExampleCommand.run(arguments: ["iglu", "com.acme", "static", directory.path]).status,
            ReferrerCommand.run(arguments: ["iglu", "com.acme", "static", directory.path]).status,
            RequiredReferrerCommand.run(arguments: ["iglu", "com.acme", "static", directory.path]).status,
            RequiredReferrerCommand.run(arguments: ["iglu", "com.acme", "server", directory.path]).status,
        ]
        let afterStatic = try FileManager.default.contentsOfDirectory(atPath: folder)
        let actualServer = [ReferrerCommand.run(arguments: ["iglu", "com.acme", "server", directory.path]).status]

        #expect(actual == expected)
        #expect(afterStatic == ["1-0-0"])
        #expect(actualServer == expectedAfterServer)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder).sorted() == ["1-0-0", "1-0-1"])
    }

    @Test("The command's iglu exits 64 for an invalid vendor, 65 for an event Iglu can't name or one needing allOf, and 73 when it can't write, and writes nothing on 64 or 65")
    func commandFailures() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let expected: [Int32] = [64, 65, 65, 73]

        let actual = [
            ExampleCommand.run(arguments: ["iglu", "com..acme", "server", directory.path]).status,
            UnnamableCommand.run(arguments: ["iglu", "com.acme", "server", directory.path]).status,
            TwoPatternsCommand.run(arguments: ["iglu", "com.acme", "server", directory.path]).status,
            ExampleCommand.run(arguments: ["iglu", "com.acme", "server", "/dev/null/registry"]).status,
        ]

        #expect(actual == expected)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("The command exits 64 with its usage for iglu without a kind or a directory, a kind other than server or static, or an option for the vendor or the directory (iglu alone is a directory to write the plan to)", arguments: [
        ["iglu", "com.acme"], ["iglu", "com.acme", "/dev/null/registry"], ["iglu", "com.acme", "Server", "/dev/null/registry"],
        ["iglu", "com.acme", "dynamic", "/dev/null/registry"], ["iglu", "com.acme", "staticRepository", "/dev/null/registry"],
        ["iglu", "--vendor", "server", "/dev/null/registry"], ["iglu", "com.acme", "server", "--out"],
        ["iglu", "com.acme", "server", "/dev/null/a", "/dev/null/b"], ["check", "com.acme", "server", "/dev/null/registry"],
    ])
    func commandUsage(arguments: [String]) {
        let expectedStatus: Int32 = 64
        let expectedUsageLine = "iglu <vendor> server|static <registry-directory>"

        let actual = ExampleCommand.run(arguments: arguments)

        #expect(actual.status == expectedStatus)
        #expect(actual.standardError.split(separator: "\n").contains { $0.hasSuffix(expectedUsageLine) })
    }
}
