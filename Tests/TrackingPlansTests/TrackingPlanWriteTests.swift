// Writing a plan into a directory, as the plugin's runner does, and the command that runs it.

import Events
import Foundation
import Testing
import TrackingPlans

@Suite("TrackingPlan: writing")
struct TrackingPlanWriteTests {
    struct ExampleCommand: TrackingPlanCommand {
        static var trackingPlan: TrackingPlan {
            get throws(TrackingPlanError) {
                try TrackingPlan(schemas: [
                    EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
                        EventSchema.Property(name: "plan", typeName: "String", isOptional: false),
                    ]),
                ])
            }
        }
    }

    @Test("Writing creates the directory and writes every file's bytes")
    func writes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("plan")
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let sut = try ExampleCommand.trackingPlan
        let expected = sut.files.map { Data($0.contents) }

        try sut.write(to: directory)

        let actual = sut.files.map { FileManager.default.contents(atPath: directory.appendingPathComponent($0.path).path) }
        #expect(actual == expected)
    }

    @Test("Writing deletes the documents and examples the plan no longer holds and leaves other files alone")
    func removesStale() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stale = directory.appendingPathComponent("signed_in.v1.schema.json")
        let staleExample = directory.appendingPathComponent("signed_in.v1.example.json")
        let kept = directory.appendingPathComponent("README.md")
        #expect(FileManager.default.createFile(atPath: stale.path, contents: Data("{}".utf8)))
        #expect(FileManager.default.createFile(atPath: staleExample.path, contents: Data("{}".utf8)))
        #expect(FileManager.default.createFile(atPath: kept.path, contents: Data("notes".utf8)))
        let expected = ["README.md", "signed_up.v1.example.json", "signed_up.v1.schema.json", "tracking-plan.json"]
        let sut = try ExampleCommand.trackingPlan

        try sut.write(to: directory)

        let actual = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(actual == expected)
    }

    @Test("Writing a plan again leaves its files untouched")
    func unchanged() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sut = try ExampleCommand.trackingPlan
        try sut.write(to: directory)
        let paths = sut.files.map { directory.appendingPathComponent($0.path).path }
        let expected = Date(timeIntervalSince1970: 1_000_000_000)
        for path in paths {
            try FileManager.default.setAttributes([.modificationDate: expected], ofItemAtPath: path)
        }

        try sut.write(to: directory)

        let actual = try paths.map { try FileManager.default.attributesOfItem(atPath: $0)[.modificationDate] as? Date }
        #expect(actual == [expected, expected, expected])
    }

    @Test("Writing a plan again rewrites a file whose bytes changed")
    func changed() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sut = try ExampleCommand.trackingPlan
        try sut.write(to: directory)
        let document = directory.appendingPathComponent("signed_up.v1.schema.json")
        try Data("{}".utf8).write(to: document)
        let expected = sut.files.first { $0.path == "signed_up.v1.schema.json" }.map { Data($0.contents) }

        try sut.write(to: directory)

        #expect(FileManager.default.contents(atPath: document.path) == expected)
    }

    @Test("Writing into a path that is a file throws a CocoaError")
    func writeFails() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(FileManager.default.createFile(atPath: file.path, contents: Data("not a directory".utf8)))
        let sut = try ExampleCommand.trackingPlan

        #expect(throws: CocoaError.self) {
            try sut.write(to: file)
        }
    }

    @Test("The command writes its plan into the directory it is given and exits 0")
    func command() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let expectedStatus: Int32 = 0
        let expectedIndex = try ExampleCommand.trackingPlan.files.first.map { Data($0.contents) }

        let actual = ExampleCommand.run(arguments: [directory.path]).status

        #expect(actual == expectedStatus)
        #expect(FileManager.default.contents(atPath: directory.appendingPathComponent("tracking-plan.json").path) == expectedIndex)
    }

    // Paths under /dev/null, which no file can be written to, so a command that wrongly takes the
    // first of two arguments fails rather than writing into the working directory.
    @Test("The command exits 64 unless it is given exactly one argument or check and one", arguments: [[], ["/dev/null/a", "/dev/null/b"]])
    func usage(arguments: [String]) {
        let expected: Int32 = 64

        let actual = ExampleCommand.run(arguments: arguments).status

        #expect(actual == expected)
    }

    struct InvalidCommand: TrackingPlanCommand {
        static var trackingPlan: TrackingPlan {
            get throws(TrackingPlanError) {
                try TrackingPlan(schemas: [EventSchema(name: "", version: 1, consentCategory: .analytics, properties: [])])
            }
        }
    }

    @Test("The command exits 65 and writes nothing when its plan throws, whether writing or checking")
    func invalidPlan() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let expected: Int32 = 65

        let written = InvalidCommand.run(arguments: [directory.path]).status
        let checked = InvalidCommand.run(arguments: ["check", directory.path]).status

        #expect(written == expected)
        #expect(checked == expected)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("The command exits 73 when it can't write the plan")
    func commandFails() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(FileManager.default.createFile(atPath: file.path, contents: Data("not a directory".utf8)))
        let expected: Int32 = 73

        let actual = ExampleCommand.run(arguments: [file.path]).status

        #expect(actual == expected)
    }
}
