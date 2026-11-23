// The suites that mustn't run alongside each other, nested here so they run one at a time:
// TrackerCancellationTests runs every job in the process on the main serial executor while it
// runs, and TrackerWorkerTests blocks a worker's thread at a gate, which on that executor would
// block every job, the one that opens the gate included. WASI builds leave both out.
#if !os(WASI)
    import Testing

    @Suite(.serialized)
    enum SerializedSuites {}
#endif
