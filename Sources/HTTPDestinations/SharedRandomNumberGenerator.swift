import Synchronization

/// One random number generator that every copy of a destination, and every request it retries at
/// once, draws from in turn.
///
/// A struct over a shared box, so Afluent's jitter, which takes a generator by value, still draws
/// from the one the destination was given.
struct SharedRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private let box: Box

    /// Draws from `generator`.
    init(_ generator: some RandomNumberGenerator & Sendable) {
        box = Box(generator)
    }

    func next() -> UInt64 {
        box.generator.withLock { $0.next() }
    }

    // A generator's state changes with every draw, and copies of a destination retry their
    // requests concurrently, so its state is shared mutable state. A Mutex rather than an actor:
    // a draw is a few instructions, called from Afluent's synchronous jitter, which can't await
    // an actor hop. Switch to an actor only if a draw ever needs to suspend.
    private final class Box: Sendable {
        let generator: Mutex<any RandomNumberGenerator & Sendable>

        init(_ generator: some RandomNumberGenerator & Sendable) {
            self.generator = Mutex(generator)
        }
    }
}
