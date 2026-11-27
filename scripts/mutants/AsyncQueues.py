# Planted bugs for AsyncQueues; run with `just mutate AsyncQueues`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in Sources/AsyncQueues/<file>
# (or `nth=` picks one), and mode="stmt" replaces whole statements rather than an expression.
# Every mutant must be caught; one that survives needs a test, or a note here saying why it is
# equivalent to the original.
#
# Known equivalent mutants (left out, as they would survive by design):
# - Dropping the warning an iterator logs as it starts to wait for its turn, or logging it at every
#   wait: tests don't pin logs.
# - The iterator's `tryAcquire` skipped, every read going through `acquire`: `acquire` grants the
#   turn at once to the reader holding it or when no one does, so only the warning differs.
# - A cancelled wait taken as the turn (`_ = await reader.acquire()` in the iterator's `next()`):
#   the read then reaches the storage, whose `next()` returns nil at once for a cancelled task, so
#   it takes nothing and the reader holding the turn is undisturbed either way.

TESTS = ["AsyncQueuesTests"]

Q = "AsyncQueue.swift"
B = "AsyncQueue+Buffering.swift"
S = "QueueStorage.swift"
L = "ReadLock.swift"
C = "AsyncQueue+Continuation.swift"

MUTANTS = [
    # The queue's elements: dropped after the end, never handed to a waiting read, lost when taken.
    Mutant("enqueuedafterfinish", S, "guard !state.isFinished else { return nil }", "", mode="stmt", nth=0),
    Mutant("waitingreadskipped", S, "read?.continuation.resume(returning: .element(element))", "", mode="stmt"),
    Mutant("waitingreadnotcleared", S, "state.read = nil", "", mode="stmt", nth=0),
    Mutant("keptelementlost", S, "return .element(state.waiting.removeFirst())", "return .end", mode="stmt"),
    Mutant("newestkeptfirst", S, "state.waiting.removeFirst()", "state.waiting.removeLast()"),
    Mutant("neverfinished", S, "state.isFinished = true", "", mode="stmt"),
    Mutant("finishleavesread", S, "read?.continuation.resume(returning: .end)", "", mode="stmt", nth=0),
    Mutant("finishedkeepswaiting", S, "guard !state.isFinished else { return .end }", "", mode="stmt"),
    # A copy of the holding iterator, reading from another task while the original waits: it ends
    # the original's turn, or replaces the original's read and leaves it waiting.
    # The whole guard first, as a later mutant's schema rewrites the text inside it.
    Mutant("concurrentreadreplaces", S, "guard state.read == nil else { return .concurrentRead }", "", mode="stmt"),
    Mutant("concurrentreadreleases", S, "return .concurrentRead", "return .end", mode="stmt"),
    # A cancelled read: one already cancelled waits, one cancelled while waiting is left waiting.
    Mutant("cancelledreadwaits", S, "guard !Task.isCancelled else { return .end }", "", mode="stmt"),
    Mutant("cancelledreadleft", S, "read?.continuation.resume(returning: .end)", "", mode="stmt", nth=1),
    Mutant("cancelledreadnotcleared", S, "state.read = nil", "", mode="stmt", nth=2),
    # Buffering.
    Mutant("unboundeddrops", B, "Buffering { element, waiting in waiting.append(element) }", "Buffering { _, _ in }", mode="stmt"),
    Mutant("newestnegativekeeps", B, "Swift.max(limit, 0)", "Swift.max(limit, 1)"),
    Mutant("newestkeepsonemore", B, "excess > 0", "excess > 1"),
    Mutant("newestkeepsoneless", B, "waiting.removeFirst(excess)", "waiting.removeFirst(Swift.min(excess + 1, waiting.count))"),
    # The iterator: the turn kept once its iteration ends.
    Mutant("endedreaderkeepsturn", Q, "reader.release()", "", mode="stmt"),
    Mutant("finishednotfinished", Q, "queue.finish()", "", mode="stmt"),
    # An app's continuation (TRAF-115): its queue bounded, its elements or its finish dropped, or
    # the queue left open once the last copy is gone.
    Mutant("continuationbounded", C, "AsyncQueue(name: name)", "AsyncQueue(name: name, buffering: .newest(1))"),
    Mutant("continuationenqueuedropped", C, "writer.queue.enqueue(element)", "", mode="stmt"),
    # The deinit's, the second occurrence; the first is finish()'s, which the next mutant plants.
    Mutant("continuationneverends", C, "queue.finish()", "", mode="stmt", nth=1),
    Mutant("continuationfinishignored", C, "writer.queue.finish()", "", mode="stmt"),
    # The turn granted while another reader holds it, so it takes the holder's elements; or not
    # granted again to the reader holding it, which then waits on itself.
    Mutant("turnalwaysgranted", L, "guard owner == nil || owner == reader else { return false }", "", mode="stmt"),
    Mutant("turnnotkept", L, "owner == nil || owner == reader", "owner == nil"),
    # A release that resumes the first waiter without making it the owner, or never resumes it.
    Mutant("turnnothandedon", L, "state.owner = next.reader", "", mode="stmt"),
    Mutant("waiternotresumed", L, "next?.continuation.resume(returning: true)", "", mode="stmt"),
    # Waiters taking the turn last in, first out.
    Mutant("waiterslifo", L, "state.waiters.removeFirst()", "state.waiters.removeLast()"),
    # A waiter cancelled while queued, or before it is queued, left waiting.
    Mutant("cancelledwaiterleft", L, "waiter?.continuation.resume(returning: false)", "", mode="stmt"),
    Mutant("cancelledbeforequeueing", L, "if Task.isCancelled { return false }", "", mode="stmt"),
    # The turn kept by a released iterator.
    Mutant("releasedreaderkeepsturn", L, "lock.release(ObjectIdentifier(self))", "", mode="stmt", nth=0),
]
