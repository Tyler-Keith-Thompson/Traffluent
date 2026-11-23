// Exit tests, in a file of their own: each runs its body in a child process, which iOS, tvOS,
// watchOS and visionOS cannot start.

import Events
import Testing
import TraffluentTestSupport

@Suite("Refined and Constraint: traps", .timeLimit(.minutes(1)))
struct RefinedExitTests {
    enum PlanName: Refinement {
        static let constraints: [Constraint<String>] = [.minLength(1), .maxLength(8), .pattern("^[a-z]*$", example: "pro")]
    }

    enum Percent: Refinement {
        static let constraints: [Constraint<Double>] = [.minimum(0), .maximum(100)]
    }

    enum Tags: Refinement {
        static let constraints: [Constraint<[String]>] = [.minItems(1), .maxItems(2)]
    }

    @Test("The plain spelling traps on a string shorter than its minLength", .tags(.precondition))
    func minLengthTraps() async {
        await #expect(processExitsWith: .failure) { _ = Refined<String, PlanName>("") }
    }

    @Test("The plain spelling traps on a string longer than its maxLength", .tags(.precondition))
    func maxLengthTraps() async {
        await #expect(processExitsWith: .failure) { _ = Refined<String, PlanName>("enterprise") }
    }

    @Test("The plain spelling traps on a string its pattern doesn't match", .tags(.precondition))
    func patternTraps() async {
        await #expect(processExitsWith: .failure) { _ = Refined<String, PlanName>("Pro") }
    }

    @Test("The plain spelling traps on a number below its minimum", .tags(.precondition))
    func minimumTraps() async {
        await #expect(processExitsWith: .failure) { _ = Refined<Double, Percent>(-0.5) }
    }

    @Test("The plain spelling traps on a number above its maximum", .tags(.precondition))
    func maximumTraps() async {
        await #expect(processExitsWith: .failure) { _ = Refined<Double, Percent>(100.5) }
    }

    @Test("The plain spelling traps on an array with fewer elements than its minItems", .tags(.precondition))
    func minItemsTraps() async {
        await #expect(processExitsWith: .failure) { _ = Refined<[String], Tags>([]) }
    }

    @Test("The plain spelling traps on an array with more elements than its maxItems", .tags(.precondition))
    func maxItemsTraps() async {
        await #expect(processExitsWith: .failure) { _ = Refined<[String], Tags>(["a", "b", "c"]) }
    }

    @Test("A negative minLength traps", .tags(.precondition))
    func negativeMinLengthTraps() async {
        await #expect(processExitsWith: .failure) { _ = Constraint<String>.minLength(-1) }
    }

    @Test("A negative maxLength traps", .tags(.precondition))
    func negativeMaxLengthTraps() async {
        await #expect(processExitsWith: .failure) { _ = Constraint<String>.maxLength(-1) }
    }

    @Test("A negative minItems traps", .tags(.precondition))
    func negativeMinItemsTraps() async {
        await #expect(processExitsWith: .failure) { _ = Constraint<[Int]>.minItems(-1) }
    }

    @Test("A negative maxItems traps", .tags(.precondition))
    func negativeMaxItemsTraps() async {
        await #expect(processExitsWith: .failure) { _ = Constraint<[Int]>.maxItems(-1) }
    }

    @Test("A minimum that isn't finite traps", .tags(.precondition))
    func infiniteMinimumTraps() async {
        await #expect(processExitsWith: .failure) { _ = Constraint<Double>.minimum(.nan) }
    }

    @Test("A maximum that isn't finite traps", .tags(.precondition))
    func infiniteMaximumTraps() async {
        await #expect(processExitsWith: .failure) { _ = Constraint<Double>.maximum(.infinity) }
    }

    @Test("A pattern that isn't a regular expression traps", .tags(.precondition))
    func invalidPatternTraps() async {
        await #expect(processExitsWith: .failure) { _ = Constraint<String>.pattern("(", example: "(") }
    }

    @Test("A pattern whose example it doesn't match traps", .tags(.precondition))
    func exampleMismatchTraps() async {
        await #expect(processExitsWith: .failure) { _ = Constraint<String>.pattern("^[0-9]+$", example: "abc") }
    }
}
