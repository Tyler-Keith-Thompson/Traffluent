# Judging a speed change

Judge a speed change by `just bench-simulated-compare --target <Module>Benchmarks`: its
instruction, cache-miss and branch counts don't move when the machine is busy, as wall clock
does. Allocation counts and absolute times still come from `just bench`, on a quiet machine.
Re-record the `simulated` baseline for the targets a change touches
(`just bench-simulated --target X`) and commit it with the change. Its `results.json` is
pretty-printed with sorted keys, one benchmark's entry on lines of its own, and a benchmark
whose instruction and malloc counts moved less than compare's 5% threshold keeps its recorded
entry. So the file changes only where a benchmark did, and pull requests that change different
benchmarks of one target merge without a conflict. Resolve a conflict by re-recording after
the merge, never by hand. A benchmark whose mallocs drop to zero, or that was measured over a
different number of iterations, counts as moved. Harness options (`--iterations`, `--filter`)
measure uncached and write the same format, keeping the entries that didn't move. A `--filter`
or `--skip` run also keeps every entry it didn't measure; with `--fresh`, the file holds only
what it measured. Quote a regex that holds a space
(`--filter "BASELINE raw write"`): the recipes pass it on as one argument. A second
`just bench-simulated` on unchanged code is a cache hit and measures nothing, so to check that
a baseline reproduces, re-record with `--remeasure` (`just bench-simulated --target X
--remeasure`): the harness measures again, uncached, and the file shouldn't change. To rewrite
every entry (a change aimed at cache misses alone), delete the file first.

## Ending the window after dispatched work drains

A benchmark that starts work on a dispatch queue, a thread of its own or a dispatch-backed
`TaskExecutor` (Afluent's `QueueExecutor` through `Task.detached(executorPreference:)`) must wait
for that work inside its measured window. The simulated instruction counts leave such work out,
but the counted metrics (`mallocCountTotal`, `retainCount` and the other non-time metrics in
`Benchmark.defaultConfiguration.metrics`) come from a second, native run that counts every thread
at real timing. A window that returns before the work finishes gets a malloc count that changes
from run to run while its instructions hold, and the two describe different work. So the last
thing each iteration does is wait for what joins the work. Build the queue and the group
outside the loop, so their setup stays out of the window:

```swift
let queue = DispatchQueue(label: "benchmarks.greetings")
let group = DispatchGroup()

Benchmark("Greetings: interpolation on a queue") { benchmark in
    for _ in benchmark.scaledIterations {
        for name in names {
            queue.async(group: group) {
                blackHole("Good day, \(name)!")
            }
        }
        group.wait()
    }
}
```

`group.wait()` blocks, which Swift allows only in a synchronous closure like this one. When the
work belongs to a type of your own, the closure is async and its last step awaits the call that
joins the work instead: a `flush()` the type defines, or a task group's `waitForAll()`.
BenchmarkHarness states the rule in `docs/HowItWorks.md`, under "Counted metrics".
