// The suites that run every job in the process on the main serial executor while they run, nested
// here so they run one at a time: withMainSerialExecutor saves and restores a global flag, so two
// suites running it at once could turn it off under each other.
import Testing

@Suite(.serialized)
enum SerializedSuites {}
