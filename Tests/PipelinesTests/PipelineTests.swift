import Destinations
import Events
import Pipelines
import Synchronization
import Testing

@Suite("Pipeline", .timeLimit(.minutes(1)))
struct PipelineTests {
    struct SignedUp: Event {
        var plan: String
    }

    final class Recorder: Destination {
        let names = Mutex<[String]>([])

        func receive<E: Event>(_ event: E) async {
            names.withLock { $0.append(E.name) }
        }
    }

    @Test("A pipeline delivers each event to every destination")
    func fanOut() async {
        let first = Recorder()
        let second = Recorder()
        let sut = Pipeline(first, second)
        let expected = ["SignedUp", "SignedUp"]

        await sut.track(SignedUp(plan: "pro"))
        await sut.track(SignedUp(plan: "free"))

        #expect(first.names.withLock { $0 } == expected)
        #expect(second.names.withLock { $0 } == expected)
    }

    @Test("A pipeline with no destinations accepts events")
    func empty() async {
        let sut = Pipeline()

        await sut.track(SignedUp(plan: "pro"))
    }
}
