import Events
import Foundation
import LifecycleTracking
import Testing

@Suite("LifecycleBatchStrategy")
struct LifecycleBatchStrategyTests {
    struct Tapped: Event {}

    @Test("Nothing pending doesn't flush")
    func empty() {
        let sut = LifecycleBatchStrategy()

        let actual = sut.flushes(pending: [])

        #expect(!actual)
    }

    @Test("A move to the background, or an end, last among the pending records flushes them")
    func leavingLast() {
        let tapped = EventRecord(event: Tapped(), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil, context: .topLevel)
        let backgrounded = EventRecord(event: ApplicationBackgrounded(), timestamp: Date(timeIntervalSince1970: 2), sourceLocation: nil, context: .topLevel)
        let terminated = EventRecord(event: ApplicationTerminated(), timestamp: Date(timeIntervalSince1970: 2), sourceLocation: nil, context: .topLevel)
        let sut = LifecycleBatchStrategy()

        let actualBackgrounded = sut.flushes(pending: [tapped, backgrounded])
        let actualTerminated = sut.flushes(pending: [terminated])

        #expect(actualBackgrounded)
        #expect(actualTerminated)
    }

    @Test("Any other record last doesn't flush, an open or an install included, nor a move to the background before it")
    func otherLast() {
        let backgrounded = EventRecord(event: ApplicationBackgrounded(), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil, context: .topLevel)
        let tapped = EventRecord(event: Tapped(), timestamp: Date(timeIntervalSince1970: 2), sourceLocation: nil, context: .topLevel)
        let opened = EventRecord(event: ApplicationOpened(fromBackground: true), timestamp: Date(timeIntervalSince1970: 2), sourceLocation: nil, context: .topLevel)
        let installed = EventRecord(event: ApplicationInstalled(version: "1.0"), timestamp: Date(timeIntervalSince1970: 2), sourceLocation: nil, context: .topLevel)
        let sut = LifecycleBatchStrategy()

        let actual = [
            sut.flushes(pending: [backgrounded, tapped]),
            sut.flushes(pending: [opened]),
            sut.flushes(pending: [installed]),
        ]

        #expect(actual == [false, false, false])
    }
}
