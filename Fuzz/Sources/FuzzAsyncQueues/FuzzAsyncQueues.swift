// An AsyncQueue against a model of a plain array, through the public owner that makes one,
// InMemoryDestination's deliveries: a sequence of choices receives a batch, reads one, or lets go
// of the reader holding the turn and reads through a new one, with a buffer of the newest 1 to 4
// batches or of every batch. After every read the batch read is the model's oldest, and once every
// copy of the destination is gone the rest are the model's, in order, then nothing. Each batch is
// one record of its number, so a batch read out of order or twice shows.

import AsyncQueues
import Destinations
import Events
import Foundation
import FuzzSupport
import Synchronization

struct Numbered: Event {
    var number: Int
}

/// One choice: receive the next batch, read one, or read on through a new reader.
enum Operation: Sendable {
    case receive
    case read
    case newReader
}

/// A value a task sets for a caller blocked on it.
final class Shared<Value: Sendable>: Sendable {
    let value: Mutex<Value>

    init(_ value: Value) {
        self.value = Mutex(value)
    }
}

/// What `body` returns, waiting for it: the fuzzer's callback can't await.
func blocking<Value: Sendable>(_ body: @escaping @Sendable () async -> Value) -> Value {
    let result = Shared<Value?>(nil)
    let done = DispatchSemaphore(value: 0)
    Task {
        let value = await body()
        result.value.withLock { $0 = value }
        done.signal()
    }
    done.wait()
    // The task set it before signalling.
    return result.value.withLock { $0! }
}

/// The batch's number: its one record's.
func number(of batch: [EventRecord]) -> Int {
    (batch.first?.event as? Numbered)?.number ?? -1
}

/// Runs `operations` on a destination keeping the newest `bound` batches (every one for 0), and
/// returns the first difference from the model, if any.
func run(_ operations: [Operation], bound: Int) async -> String? {
    var destination: InMemoryDestination? = bound == 0 ? .unbounded() : try? InMemoryDestination(capacity: bound)
    guard let deliveries = destination?.deliveries else {
        return "InMemoryDestination refused the capacity \(bound)"
    }
    var model: [Int] = []
    var next = 0
    var reader = deliveries.makeAsyncIterator()
    for operation in operations {
        switch operation {
        case .receive:
            await destination?.receive([EventRecord(event: Numbered(number: next), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)])
            model.append(next)
            next += 1
            if bound > 0, model.count > bound {
                model.removeFirst()
            }
        case .read:
            // Only while a batch waits, so the read never waits for ever.
            guard !model.isEmpty else { continue }
            let actual = await reader.next().map(number(of:))
            let expected = model.removeFirst()
            if actual != expected {
                return "read \(String(describing: actual)), model \(expected)"
            }
        case .newReader:
            // The old reader is released as it is replaced, handing on the turn.
            reader = deliveries.makeAsyncIterator()
        }
    }
    destination = nil
    var rest: [Int] = []
    while let batch = await reader.next() {
        rest.append(number(of: batch))
    }
    return rest == model ? nil : "read \(rest) after the end, model \(model)"
}

@main
enum FuzzAsyncQueues {
    static func main() {
        runFuzzer { input in
            let bound = input.int(in: 0 ... 4)
            var operations: [Operation] = []
            while operations.count < 64, !input.isEmpty {
                operations.append([.receive, .read, .newReader][input.int(below: 3)])
            }
            let failure = blocking { [operations] in await run(operations, bound: bound) }
            check(failure == nil, failure ?? "")
        }
    }
}
