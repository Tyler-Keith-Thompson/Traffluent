/// Whether a ``Sensitive`` value's `Codable` conformance writes and reads the value itself, in the
/// task that encodes or decodes it.
///
/// Off unless the library's own code turns it on around an encoding or a decoding: a store's, and
/// a batch encoder's for a destination that reveals sensitive values. So code outside the library
/// can't turn a sensitive value into bytes by encoding it, or the event holding it, itself, and
/// can't recover one from bytes.
// A task-local rather than the encoder's `userInfo`: the CBOR package's encoder and decoder expose
// none, and a task-local reaches every nested value's conformance, however deep, without a
// parameter. It is read once per sensitive value, which costs less than the value's own encoding.
package enum SensitiveCoding {
    /// Whether sensitive values are written and read as themselves in this task.
    @TaskLocal package static var revealsValues = false
}
