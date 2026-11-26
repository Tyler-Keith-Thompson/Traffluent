// An event's earlier versions, once exported, stay in the plan after its version is raised:
// writing keeps their documents and examples byte for byte and lists them in the index, and the
// check compares them by their bytes alone.

import Events
import Foundation
import PropertyBased
import Testing
import TrackingPlans

@Suite("TrackingPlan: earlier versions")
struct TrackingPlanEarlierVersionTests {
    @Test("Writing an event at version 2 keeps the directory's version 1 document and example byte for byte")
    func keepsEarlierVersion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let version1 = EventSchema(name: "checkout_started", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "cartSize", typeName: "Int", isOptional: false),
        ])
        let version2 = EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "cartSize", typeName: "Double", isOptional: false),
        ])
        try TrackingPlan(schemas: [version1]).write(to: directory)
        let paths = ["checkout_started.v1.schema.json", "checkout_started.v1.example.json"]
        let expected = paths.map { FileManager.default.contents(atPath: directory.appendingPathComponent($0).path) }
        let sut = try TrackingPlan(schemas: [version2])

        try sut.write(to: directory)

        let actual = paths.map { FileManager.default.contents(atPath: directory.appendingPathComponent($0).path) }
        #expect(actual.allSatisfy { $0 != nil })
        #expect(actual == expected)
    }

    @Test("The index lists a kept earlier version before the current one, with its consent category and files")
    func indexListsEarlierVersion() throws {
        let committed = try TrackingPlan(schemas: [
            EventSchema(name: "checkout_started", version: 1, consentCategory: .functional, properties: []),
            EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: []),
        ]).files
        let sut = try TrackingPlan(schemas: [
            EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: []),
            EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: []),
        ])
        let expected = """
            {
              "events": [
                {
                  "consentCategory": "functional",
                  "example": "checkout_started.v1.example.json",
                  "name": "checkout_started",
                  "schema": "checkout_started.v1.schema.json",
                  "version": 1
                },
                {
                  "consentCategory": "analytics",
                  "example": "checkout_started.v2.example.json",
                  "name": "checkout_started",
                  "schema": "checkout_started.v2.schema.json",
                  "version": 2
                },
                {
                  "consentCategory": "analytics",
                  "example": "signed_up.v1.example.json",
                  "name": "signed_up",
                  "schema": "signed_up.v1.schema.json",
                  "version": 1
                }
              ]
            }

            """

        let actual = sut.files(carryingForward: committed).first.map { String(decoding: $0.contents, as: UTF8.self) }

        #expect(actual == expected)
    }

    @Test("Writing an event at version 3 keeps its versions 1 and 2, in order after the index")
    func keepsEveryEarlierVersion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        for version in 1 ... 2 {
            try TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: version, consentCategory: .analytics, properties: [])]).write(to: directory)
        }
        let sut = try TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 3, consentCategory: .analytics, properties: [])])
        let expected = [
            "tracking-plan.json",
            "checkout_started.v1.schema.json", "checkout_started.v1.example.json",
            "checkout_started.v2.schema.json", "checkout_started.v2.example.json",
            "checkout_started.v3.schema.json", "checkout_started.v3.example.json",
        ]

        try sut.write(to: directory)

        let committed = try FileManager.default.contentsOfDirectory(atPath: directory.path).compactMap { path in
            FileManager.default.contents(atPath: directory.appendingPathComponent(path).path).map { TrackingPlan.File(path: path, contents: Array($0)) }
        }
        let actual = sut.files(carryingForward: committed).map(\.path)
        let written = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(actual == expected)
        #expect(written == expected.sorted())
    }

    @Test("Writing a plan without an event deletes its documents and examples at every version")
    func removedEventDeletesEveryVersion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        for version in 1 ... 2 {
            try TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: version, consentCategory: .analytics, properties: [])]).write(to: directory)
        }
        let sut = try TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [])])
        let expected = ["signed_up.v1.example.json", "signed_up.v1.schema.json", "tracking-plan.json"]

        try sut.write(to: directory)

        let actual = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(actual == expected)
    }

    @Test("Writing deletes the files of a version above the plan's")
    func laterVersionDeleted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        for version in [1, 3] {
            try TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: version, consentCategory: .analytics, properties: [])]).write(to: directory)
        }
        let sut = try TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [])])
        let expected = [
            "checkout_started.v1.example.json", "checkout_started.v1.schema.json",
            "checkout_started.v2.example.json", "checkout_started.v2.schema.json",
            "tracking-plan.json",
        ]

        try sut.write(to: directory)

        let actual = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(actual == expected)
    }

    @Test("An earlier version's example without its document is deleted, and a document without its example is kept and listed without one")
    func documentWithoutExample() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        for version in 1 ... 2 {
            try TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: version, consentCategory: .analytics, properties: [])]).write(to: directory)
        }
        try FileManager.default.removeItem(at: directory.appendingPathComponent("checkout_started.v1.schema.json"))
        try FileManager.default.removeItem(at: directory.appendingPathComponent("checkout_started.v2.example.json"))
        let sut = try TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 3, consentCategory: .analytics, properties: [])])
        let expectedFiles = [
            "checkout_started.v2.schema.json",
            "checkout_started.v3.example.json", "checkout_started.v3.schema.json",
            "tracking-plan.json",
        ]
        let expectedEntry: [String: String] = [
            "consentCategory": "analytics", "name": "checkout_started", "schema": "checkout_started.v2.schema.json", "version": "2",
        ]

        try sut.write(to: directory)

        let actualFiles = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        let index = try #require(FileManager.default.contents(atPath: directory.appendingPathComponent("tracking-plan.json").path))
        let events = try #require((try JSONSerialization.jsonObject(with: index) as? [String: Any])?["events"] as? [[String: Any]])
        let actualEntry = events.first?.mapValues { "\($0)" }
        #expect(actualFiles == expectedFiles)
        #expect(events.count == 2)
        #expect(actualEntry == expectedEntry)
    }

    @Test("An earlier version's document that isn't that event's is kept byte for byte but left out of the index")
    func unreadableEarlierDocument() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let expectedContents: [Data] = [
            Data("not JSON".utf8),
            Data(#"{"title": "signed_up", "x-traffluent-version": 2, "x-traffluent-consent-category": "analytics"}"#.utf8),
            Data(#"{"title": "checkout_started", "x-traffluent-version": 1, "x-traffluent-consent-category": "analytics"}"#.utf8),
            Data(#"{"title": "checkout_started", "x-traffluent-version": 4}"#.utf8),
        ]
        let paths = (1 ... 4).map { "checkout_started.v\($0).schema.json" }
        for (path, contents) in zip(paths, expectedContents) {
            #expect(FileManager.default.createFile(atPath: directory.appendingPathComponent(path).path, contents: contents))
        }
        let sut = try TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 5, consentCategory: .analytics, properties: [])])
        let expectedListed = ["checkout_started.v5.schema.json"]

        try sut.write(to: directory)

        let actualContents = paths.map { FileManager.default.contents(atPath: directory.appendingPathComponent($0).path) }
        let index = try #require(FileManager.default.contents(atPath: directory.appendingPathComponent("tracking-plan.json").path))
        let events = try #require((try JSONSerialization.jsonObject(with: index) as? [String: Any])?["events"] as? [[String: Any]])
        let actualListed = events.compactMap { $0["schema"] as? String }
        #expect(actualContents == expectedContents)
        #expect(actualListed == expectedListed)
    }

    @Test("Files only like an earlier version's, of another event or a version a plan doesn't write, are deleted, and other files are left alone")
    func otherFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let written = [
            "checkout_started.v01.schema.json", "checkout_started.v+1.schema.json", "checkout_started.v.schema.json",
            "checkout_started.vx.schema.json", "checkout.v1.schema.json", "checkout_started_v1.schema.json",
            "README.md", "checkout_started.v1.json",
        ]
        for path in written {
            #expect(FileManager.default.createFile(atPath: directory.appendingPathComponent(path).path, contents: Data("{}".utf8)))
        }
        let sut = try TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [])])
        let expected = ["README.md", "checkout_started.v1.json", "checkout_started.v2.example.json", "checkout_started.v2.schema.json", "tracking-plan.json"]

        try sut.write(to: directory)

        let actual = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(actual == expected)
    }

    @Test("A plan listing two versions of an event writes those from its schemas and keeps only the committed versions it doesn't list")
    func listedVersionsNotKept() throws {
        let committed = try TrackingPlan(schemas: [1, 2].map { EventSchema(name: "checkout_started", version: $0, consentCategory: .functional, properties: []) }).files
        let sut = try TrackingPlan(schemas: [1, 3].map { EventSchema(name: "checkout_started", version: $0, consentCategory: .analytics, properties: []) })
        let expectedPaths = [
            "tracking-plan.json",
            "checkout_started.v1.schema.json", "checkout_started.v1.example.json",
            "checkout_started.v2.schema.json", "checkout_started.v2.example.json",
            "checkout_started.v3.schema.json", "checkout_started.v3.example.json",
        ]
        let expectedVersion1 = sut.files.first { $0.path == "checkout_started.v1.schema.json" }

        let actual = sut.files(carryingForward: committed)

        #expect(actual.map(\.path) == expectedPaths)
        #expect(actual.first { $0.path == "checkout_started.v1.schema.json" } == expectedVersion1)
    }

    @Test("A committed file named like an earlier version but not ending in .schema.json is no earlier version")
    func otherSuffixIgnored() throws {
        let committed = [TrackingPlan.File(path: "checkout_started.v1.readme.json", contents: Array("{}".utf8))]
        let sut = try TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [])])
        let expected = sut.files

        let actual = sut.files(carryingForward: committed)

        #expect(actual == expected)
    }

    @Test("An event whose name needs encoding keeps its earlier version")
    func encodedName() throws {
        let committed = try TrackingPlan(schemas: [EventSchema(name: "Box<String>", version: 1, consentCategory: .analytics, properties: [])]).files
        let sut = try TrackingPlan(schemas: [EventSchema(name: "Box<String>", version: 2, consentCategory: .analytics, properties: [])])
        let expected = [
            "tracking-plan.json",
            "Box%3CString%3E.v1.schema.json", "Box%3CString%3E.v1.example.json",
            "Box%3CString%3E.v2.schema.json", "Box%3CString%3E.v2.example.json",
        ]

        let actual = sut.files(carryingForward: committed).map(\.path)

        #expect(actual == expected)
    }

    @Test("A plan written over its earlier version's checks clean against its directory")
    func checkMatchesAfterWrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "cartSize", typeName: "Int", isOptional: false),
        ])]).write(to: directory)
        let sut = try TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "cartSize", typeName: "Double", isOptional: false),
        ])])
        try sut.write(to: directory)

        let actual = sut.check(againstDirectory: directory)

        #expect(actual == .matches)
    }

    @Test("A plan whose earlier version was never committed checks clean: no export can recreate it")
    func missingEarlierVersion() throws {
        let committed = try TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [])]).files
        let sut = try TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [])])

        let actual = sut.check(against: committed)

        #expect(actual == .matches)
    }

    @Test("An earlier version's files beside an index that doesn't list them leave the index out of date")
    func unlistedEarlierVersion() throws {
        let earlier = try TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 1, consentCategory: .analytics, properties: [])]).files
        let current = try TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [])])
        let committed = current.files + earlier.dropFirst()
        let expected = TrackingPlanCheck.outOfDate([.fileOutOfDate(path: "tracking-plan.json")])

        let actual = current.check(against: committed)

        #expect(actual == expected)
    }

    @Test("Raising the version again reports only the raise from the newest committed version")
    func raisedAgain() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        for version in 1 ... 2 {
            try TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: version, consentCategory: .analytics, properties: [])]).write(to: directory)
        }
        let sut = try TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 3, consentCategory: .analytics, properties: [])])
        let expected = TrackingPlanCheck.outOfDate([.versionRaised(event: "checkout_started", committed: 2, current: 3)])

        let actual = sut.check(againstDirectory: directory)

        #expect(actual == expected)
    }

    @Test("An index listing the newer version first still marks the older one as kept: only the index's bytes differ")
    func unorderedIndex() throws {
        let sut = try TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [])])
        let documents = try TrackingPlan(schemas: [1, 2].map { EventSchema(name: "checkout_started", version: $0, consentCategory: .analytics, properties: []) }).files.dropFirst()
        let index = TrackingPlan.File(path: "tracking-plan.json", contents: Array("""
            {"events": [
              {"name": "checkout_started", "version": 2, "consentCategory": "analytics", "schema": "checkout_started.v2.schema.json"},
              {"name": "checkout_started", "version": 1, "consentCategory": "analytics", "schema": "checkout_started.v1.schema.json"}
            ]}
            """.utf8))
        let expected = TrackingPlanCheck.outOfDate([.fileOutOfDate(path: "tracking-plan.json")])

        let actual = sut.check(against: [index] + documents)

        #expect(actual == expected)
    }

    @Test("An earlier version the committed plan keeps is compared by its bytes alone, even when it differs from the plan's event")
    func earlierVersionNotCompared() throws {
        let earlier = try TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 1, consentCategory: .functional, properties: [
            EventSchema.Property(name: "cartSize", typeName: "Int", isOptional: false),
        ])]).files
        let sut = try TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [])])
        let committed = sut.files(carryingForward: earlier)

        let actual = sut.check(against: committed)

        #expect(actual == .matches)
    }

    @Test("Lowering an event's version compares it with the committed earlier version and reports the later one removed")
    func loweredVersion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        for version in 1 ... 2 {
            try TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: version, consentCategory: .analytics, properties: [])]).write(to: directory)
        }
        let sut = try TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 1, consentCategory: .functional, properties: [])])
        let expected = TrackingPlanCheck.breaking([
            .consentCategoryChanged(event: "checkout_started", version: 1, committed: "analytics", current: "functional"),
            .eventRemoved(event: "checkout_started", version: 2),
        ])

        let actual = sut.check(againstDirectory: directory)

        #expect(actual == expected)
    }

    @Test("Any plan version keeps exactly the committed versions below it, then its own", .tags(.randomized))
    func keptVersionsMatchReference() async throws {
        await propertyCheck(count: 100, input: Gen.int(in: 1 ... 8).array(of: 0 ... 8), Gen.int(in: 1 ... 8)) { committedVersions, current in
            var committed: [TrackingPlan.File] = []
            for version in committedVersions {
                committed += try TrackingPlan(schemas: [EventSchema(name: "e", version: version, consentCategory: .analytics, properties: [])]).files.dropFirst()
            }
            let expected = (Set(committedVersions.filter { $0 < current }).sorted() + [current]).flatMap { ["e.v\($0).schema.json", "e.v\($0).example.json"] }
            let sut = try TrackingPlan(schemas: [EventSchema(name: "e", version: current, consentCategory: .analytics, properties: [])])

            let actual = sut.files(carryingForward: committed).dropFirst().map(\.path)

            #expect(actual == expected)
        }
    }
}
