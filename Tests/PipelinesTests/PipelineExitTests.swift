// Exit tests, in a file of their own: each runs its body in a child process, which some platforms
// (WASI) cannot start, and those builds leave out every file holding one.

import Events
import Pipelines
import TraffluentTestSupport
import Testing

@Suite("Pipeline: traps", .timeLimit(.minutes(1)))
struct PipelineExitTests {
    @Test("Running a pipeline a second time traps", .tags(.precondition))
    func secondRunTraps() async {
        await #expect(processExitsWith: .failure) {
            let sut = Pipeline(strategy: .count(1))
            sut.finish()
            try? await sut.run().execute()
            try? await sut.run().execute()
        }
    }
}
