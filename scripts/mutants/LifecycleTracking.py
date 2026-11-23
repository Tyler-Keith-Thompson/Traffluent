# Planted bugs for LifecycleTracking. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/LifecycleTracking/<file> (or `nth=` picks one), and mode="stmt" replaces whole
# statements rather than an expression. Every mutant must be caught; one that survives needs a test,
# or a note here saying why it is equivalent to the original.
#
# They cover the decisions: install, update or neither; each event once per transition; the store
# synchronized, after the tracker's flush, on leaving the foreground; each kind turned off; and the
# batch strategy's flush. The notification table and the background time are platform glue, which
# the macOS tests reach through NSApplication's names only.

TESTS = ["LifecycleTrackingTests"]

C = "VersionChange.swift"
W = "LifecycleWorker.swift"
S = "LifecycleBatchStrategy.swift"

MUTANTS = [
    # Install, update or neither.
    Mutant("sameupdated", C, "            self = .unchanged", "            self = .updated(previousVersion: current)", mode="stmt"),
    Mutant("nilunchanged", C, "            self = .installed", "            self = .unchanged", mode="stmt"),
    Mutant("updatedfromcurrent", C, "self = .updated(previousVersion: previous)", "self = .updated(previousVersion: current)", mode="stmt"),
    Mutant("notsaved", W, "                try versionStore.save(version)", "                ()", mode="stmt"),
    Mutant("savedunchanged", W, "change != .unchanged", "true"),
    # Once per transition.
    Mutant("foregroundtwice", W, "                guard phase == .background else { continue }", "                ()", mode="stmt"),
    Mutant("backgroundtwice", W, "                guard phase == .foreground else { continue }", "                ()", mode="stmt"),
    Mutant("staysforeground", W, "                phase = .background", "                ()", mode="stmt"),
    Mutant("terminatedtwice", W, "                guard phase != .terminated else { continue }", "                ()", mode="stmt"),
    Mutant("finishafterterminated", W, "                guard phase != .terminated else { return }", "                ()", mode="stmt"),
    # Synchronize after flushing.
    Mutant("nosynchronize", W, "        tracker.store?.synchronize()", "        ()", mode="stmt"),
    Mutant("noflush", W, "        await tracker.flush()", "        ()", mode="stmt"),
    Mutant("backgroundnotdurable", W, "                await makeRecordsDurable()", "                ()", mode="stmt", nth=1),
    # Each kind turned off.
    Mutant("kindignored", W, "        guard kinds.contains(kind) else { return }", "        ()", mode="stmt"),
    # The batch strategy.
    Mutant("terminatednoflush", S, "event is ApplicationBackgrounded || event is ApplicationTerminated", "event is ApplicationBackgrounded"),
    Mutant("backgroundednoflush", S, "event is ApplicationBackgrounded || event is ApplicationTerminated", "event is ApplicationTerminated"),
    Mutant("firstpending", S, "pending.last?.event", "pending.first?.event"),
]
