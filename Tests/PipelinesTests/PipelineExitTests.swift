// Exit tests, in a file of their own: each runs its body in a child process, which some platforms
// (WASI) cannot start, and those builds leave out every file holding one.

import Afluent
import Events
import Pipelines
import TraffluentTestSupport
import Testing

@Suite("Pipeline: traps", .timeLimit(.minutes(1)))
struct PipelineExitTests {
    @Test("Running a pipeline while another run is in progress traps", .tags(.precondition))
    func concurrentRunsTrap() async {
        await #expect(processExitsWith: .failure) {
            // Never finished, so the first run keeps reading; the strategy's start shows it has
            // the subscription before the second run asks for it.
            let started = SingleValueSubject<Void>()
            let sut = Pipeline(strategy: .either(.count(1), StartGate(started: started)))
            let first = sut.run()
            let running = Task { try await first.execute() }
            try? await started.execute()

            try? await sut.run().execute()
            running.cancel()
        }
    }

    @Test("A batch buffer limit below 1 traps", .tags(.precondition))
    func zeroBufferLimitTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = Pipeline(strategy: .count(1), batchBufferLimit: 0)
        }
    }
}

/// Never flushes; sends `started` when a run starts it.
struct StartGate<Element>: BatchStrategy {
    let started: SingleValueSubject<Void>

    func run(_ flusher: BatchFlusher) async throws {
        try? started.send()
    }
}
