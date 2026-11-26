/// What a run of a ``TrackingPlanCommand`` ends with: the status it exits with and what it prints.
///
/// The command's work returns one, and ``TrackingPlanCommand/main()`` prints it and exits, so what
/// a run prints is a value rather than writes to the process's streams.
package struct TrackingPlanCommandResult: Sendable, Hashable {
    /// The status the process exits with.
    package let status: Int32
    /// What the run prints to standard output, without a final newline; empty when it prints
    /// nothing there.
    package let standardOutput: String
    /// What the run prints to standard error, without a final newline; empty when it prints
    /// nothing there.
    package let standardError: String

    /// A run that exits with `status`, printing `standardOutput` and `standardError`.
    package init(status: Int32, standardOutput: String = "", standardError: String = "") {
        self.status = status
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}
