# Fuzzing

Coverage-guided fuzz targets for [libFuzzer](https://llvm.org/docs/LibFuzzer.html), one per
module, in their own package so the library never links the fuzzer runtime.

| Target | Checks against |
|---|---|
| `FuzzAsyncQueues` | An `InMemoryDestination`'s `deliveries`, an `AsyncQueue` keeping the newest 1 to 4 batches or every batch, driven by received batches, reads and readers let go and replaced: every read is the oldest batch a model of a plain array holds, a new reader reads on from the next, and once the destination is gone the rest are the model's, in order, then nothing |
| `FuzzCollectorEncoding` | `CollectorBatchDecoder`, on arbitrary bytes, on batches of up to four records each broken or not (an id, event name, timestamp, out-of-range or mistyped property, or session), and on timestamps: arbitrary bytes throw `NotACollectorBatch` or decode and report as many records as `JSONSerialization` finds in `records`, each reported offset once and in order, and what decodes encodes, decodes and encodes again to the same bytes; a built batch decodes exactly its valid records, keeping their ids, timestamps, properties and sessions, and reports the rest by offset; a millisecond's timestamp parses back to that millisecond, and any text of a timestamp's characters parses to nil or to a date whose timestamp is that text |
| `FuzzPersistence` | Segment files built from records (with their version or without it), delivery marks and undecodable records (an event stored at another version among them), then damaged (a flipped bit, a cut tail, garbage appended), or arbitrary bytes: recovery never crashes, returns exactly the decodable records of the intact frames a reference reader finds (so never one whose CRC-32 fails), in order, with their redelivery marks, and cuts the file to the intact prefix or deletes it |
| `FuzzPropertyJSON` | `BatchLimit`'s split of batches of records of 0 to 12 bytes of text, or whose encoding throws, under limits of 1 to 5 records, 1 to 48 bytes and 1 to 16 bytes a record, in a bare array or an object envelope: after every batch the requests, their bodies and the records left out, with their reasons, are a naive greedy model's, and no body is over the limit |
| `FuzzTrackers` | Two trackers sharing a `Consent` with a small hold, driven by tracks of three categories, grants, denials and finishes: after every operation the consent holds as many records as a model of plain arrays, each tracker's records are the model's, in order, and the drop reports are the model's, in order |

Each target reads its input as a sequence of small choices (`FuzzInput`): an operation and its
arguments. Every byte string decodes, and a mutation of one byte changes one choice, so libFuzzer
explores operation sequences rather than parse errors.

## Running

| Command | Does |
|---|---|
| `just fuzz` | Every target for 60 s, all at once, splitting the cores between them |
| `just fuzz FuzzPersistence -t 600 -j 16` | One target for 10 minutes on 16 workers |
| `just fuzz-regress` | Replays every corpus once (seconds); run after changing a fuzzed module |
| `just fuzz-repro <target> <crash file>` | Replays a crash and writes a minimized copy beside it |

A run is bounded by wall time. New inputs that add coverage are merged into `Fuzz/Corpus/<target>/`
(local, not committed), so the next run resumes from there. Crashes are written to
`Fuzz/Crashes/<target>/`; each one becomes a test in the module's suite, and then the file is
deleted.

## Toolchain

Xcode's toolchain does not include the libFuzzer runtime (`libclang_rt.fuzzer_osx.a`); the
swift.org toolchains do. The scripts build with `swiftly run swift build +6.4.3` (override with
`<PROJECT>_FUZZ_SWIFT`, the project's name in capitals), so install it once with
`swiftly install 6.4.3`. The build may print `unknown argument: '-target-arch-variant'` while
reading a newer SDK's interfaces, then falls back and succeeds; the scripts hide it.

Targets are built in release mode with AddressSanitizer: preconditions stay on, and unsafe buffer
code is checked for out-of-bounds access.

SwiftPM links each executable against its own `main`, which conflicts with libFuzzer's, so each
target has an `@main` that calls `runFuzzer`, which starts libFuzzer through
`LLVMFuzzerRunDriver`.

## Adding a target

Add a directory `Sources/Fuzz<Module>/` with an `@main` enum calling `runFuzzer`, a line in
`Package.swift` naming the modules it imports (their SwiftPM products), and a row in the table
above. Check against a model simple enough to be obviously right, check after every operation,
keep values small so collisions and ties are common, and include a snapshot copy to catch
copy-on-write bugs.
