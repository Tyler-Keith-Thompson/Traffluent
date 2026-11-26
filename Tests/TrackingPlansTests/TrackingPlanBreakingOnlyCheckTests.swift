// The command's `check --breaking-only`, which `check-tracking-plan --breaking-only` runs against
// the base branch's plan: its statuses, what it prints, and the arguments it refuses.

import Events
import Foundation
import PropertyBased
import Testing
import TrackingPlans

@Suite("TrackingPlan: breaking-only check")
struct TrackingPlanBreakingOnlyCheckTests {
    struct CheckoutCommand: TrackingPlanCommand {
        static var trackingPlan: TrackingPlan {
            get throws(TrackingPlanError) {
                try TrackingPlan(schemas: [
                    EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [
                        EventSchema.Property(name: "cartSize", typeName: "Int", isOptional: false),
                        EventSchema.Property(name: "coupon", typeName: "String", isOptional: true),
                    ]),
                ])
            }
        }
    }

    @Test("The breaking-only check exits 0 and prints nothing when the plan matches")
    func matches() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try CheckoutCommand.trackingPlan.write(to: directory)
        let expected = TrackingPlanCommandResult(status: 0)

        let actual = CheckoutCommand.run(arguments: ["check", "--breaking-only", directory.path])

        #expect(actual == expected)
    }

    @Test("The breaking-only check exits 0 for a plan that is only out of date, and prints its differences to standard output")
    func outOfDate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try TrackingPlan(schemas: [
            EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [
                EventSchema.Property(name: "cartSize", typeName: "Int", isOptional: false),
            ]),
        ]).write(to: directory)
        let expected = TrackingPlanCommandResult(
            status: 0,
            standardOutput: """
                note: \(directory.path): the events differ from this tracking plan, but no difference is breaking:
                  - \(TrackingPlanDifference.optionalPropertyAdded(event: "checkout_started", version: 2, property: "coupon"))
                """
        )

        let actual = CheckoutCommand.run(arguments: ["check", "--breaking-only", directory.path])

        #expect(actual == expected)
    }

    @Test("The breaking-only check lists every difference of an out-of-date plan, one per line")
    func outOfDateDifferences() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try TrackingPlan(schemas: [
            EventSchema(name: "checkout_started", version: 2, consentCategory: .functional, properties: [
                EventSchema.Property(name: "cartSize", typeName: "Int", isOptional: false),
                EventSchema.Property(name: "coupon", typeName: "String", isOptional: true),
                EventSchema.Property(name: "currency", typeName: "String", isOptional: false),
            ]),
        ]).write(to: directory)
        let expectedDifferences: Set<TrackingPlanDifference> = [
            .consentCategoryChanged(event: "checkout_started", version: 2, committed: "functional", current: "analytics"),
            .propertyRemoved(event: "checkout_started", version: 2, property: "currency"),
        ]
        let expectedLines = Set(expectedDifferences.map { "  - \($0)" })

        let actual = CheckoutCommand.run(arguments: ["check", "--breaking-only", directory.path])

        let lines = actual.standardOutput.split(separator: "\n").map(String.init)
        #expect(actual.status == 0)
        #expect(lines.count == 3)
        #expect(Set(lines.dropFirst()) == expectedLines)
        #expect(actual.standardError.isEmpty)
    }

    @Test("The breaking-only check exits 1 for a breaking difference and prints the check's report to standard error")
    func breaking() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try TrackingPlan(schemas: [
            EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [
                EventSchema.Property(name: "cartSize", typeName: "String", isOptional: false),
            ]),
        ]).write(to: directory)
        let report = try CheckoutCommand.trackingPlan.check(againstDirectory: directory)
        let expected = TrackingPlanCommandResult(status: 1, standardError: "error: \(directory.path): \(report)")

        let actual = CheckoutCommand.run(arguments: ["check", "--breaking-only", directory.path])

        #expect(actual == expected)
        #expect(report.differences.contains { $0.isBreaking })
        #expect(report.differences.contains { !$0.isBreaking })
    }

    @Test("The breaking-only check exits 1 when there is no plan in the directory, so a base plan that was never fetched fails")
    func noPlan() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let expected: Int32 = 1

        let actual = CheckoutCommand.run(arguments: ["check", "--breaking-only", directory.path])

        #expect(actual.status == expected)
        #expect(actual.standardOutput.isEmpty)
    }

    @Test("The check without the flag still exits 2 for a plan that is only out of date, and prints the report to standard error")
    func outOfDateWithoutFlag() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try TrackingPlan(schemas: []).write(to: directory)
        let report = try CheckoutCommand.trackingPlan.check(againstDirectory: directory)
        let expected = TrackingPlanCommandResult(status: 2, standardError: "error: \(directory.path): \(report)")

        let actual = CheckoutCommand.run(arguments: ["check", directory.path])

        #expect(actual == expected)
    }

    struct InvalidCommand: TrackingPlanCommand {
        static var trackingPlan: TrackingPlan {
            get throws(TrackingPlanError) {
                try TrackingPlan(schemas: [EventSchema(name: "", version: 1, consentCategory: .analytics, properties: [])])
            }
        }
    }

    @Test("The breaking-only check exits 65 when the command's plan throws")
    func invalidPlan() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let expected: Int32 = 65

        let actual = InvalidCommand.run(arguments: ["check", "--breaking-only", directory.path])

        #expect(actual.status == expected)
        #expect(actual.standardError.hasPrefix("error: the events' schemas can't make a tracking plan: "))
    }

    // Paths under /dev/null, which no file can be written to or read from, so a command that wrongly
    // writes or checks fails rather than touching the working directory.
    static let misuses: [[String]] = [
        ["check", "--breaking-only"],
        ["--breaking-only"],
        ["--breaking-only", "/dev/null/plan"],
        ["--breaking-only", "check", "/dev/null/plan"],
        ["checks", "--breaking-only", "/dev/null/plan"],
        ["check", "/dev/null/plan", "--breaking-only"],
        ["check", "--breaking-only", "--breaking-only", "/dev/null/plan"],
        ["check", "--breaking", "/dev/null/plan"],
        ["check", "--breaking-only=true", "/dev/null/plan"],
        ["check", "--breaking-only", "-"],
        ["check", "--breaking-only", "--plan"],
        ["check", "-p"],
        ["-p"],
    ]

    @Test("The command exits 64 and prints its usage for the flag without a directory, in any other place, misspelt, twice, or with an option for the directory", arguments: misuses)
    func usage(arguments: [String]) {
        let expectedStatus: Int32 = 64
        let expectedUsageLine = "check [--breaking-only] <plan-directory>"

        let actual = CheckoutCommand.run(arguments: arguments)

        #expect(actual.status == expectedStatus)
        #expect(actual.standardError.split(separator: "\n").last?.hasSuffix(expectedUsageLine) == true)
        #expect(actual.standardOutput.isEmpty)
    }

    // A name with a dash after its first character is a directory, not an option: the check runs,
    // and finds no plan there.
    @Test("A directory whose name has a dash after its first character is checked", arguments: [["check", "--breaking-only", "p-"], ["check", "p-"]])
    func dashInDirectory(arguments: [String]) {
        let expected: Int32 = 1

        let actual = CheckoutCommand.run(arguments: arguments)

        #expect(actual.status == expected)
    }

    @Test("Against any committed plan, the breaking-only check exits 1 when the check breaks it and 0 otherwise, and the full check 0, 1 or 2", .tags(.randomized))
    func againstReference() async throws {
        // Each committed checkout_started is one of these, as is whether signed_up is committed.
        let variants: [[EventSchema.Property]] = [
            [EventSchema.Property(name: "cartSize", typeName: "Int", isOptional: false), EventSchema.Property(name: "coupon", typeName: "String", isOptional: true)],
            [EventSchema.Property(name: "cartSize", typeName: "Int", isOptional: false)],
            [EventSchema.Property(name: "cartSize", typeName: "Int", isOptional: true), EventSchema.Property(name: "coupon", typeName: "String", isOptional: true)],
            [EventSchema.Property(name: "cartSize", typeName: "String", isOptional: false)],
            [EventSchema.Property(name: "coupon", typeName: "String", isOptional: true)],
            [],
        ]
        await propertyCheck(count: 60, input: Gen.int(in: 0 ... 6), Gen.bool, Gen.int(in: 1 ... 3)) { variant, signedUp, version in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let checkout = variants.indices.contains(variant)
                ? [EventSchema(name: "checkout_started", version: version, consentCategory: .analytics, properties: variants[variant])]
                : []
            let others = signedUp ? [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [])] : []
            try TrackingPlan(schemas: checkout + others).write(to: directory)
            let check = try CheckoutCommand.trackingPlan.check(againstDirectory: directory)
            let expectedBreakingOnly: Int32 = check.differences.contains(where: \.isBreaking) ? 1 : 0
            let expectedFull: Int32 = check.differences.contains(where: \.isBreaking) ? 1 : (check.differences.isEmpty ? 0 : 2)

            let actualBreakingOnly = CheckoutCommand.run(arguments: ["check", "--breaking-only", directory.path])
            let actualFull = CheckoutCommand.run(arguments: ["check", directory.path])

            #expect(actualBreakingOnly.status == expectedBreakingOnly)
            #expect(actualFull.status == expectedFull)
            #expect(actualBreakingOnly.standardOutput.isEmpty == (expectedBreakingOnly != 0 || check.differences.isEmpty))
        }
    }
}
