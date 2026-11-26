public import Events

/// The user's consent, category by category, which a tracker given it applies to every event.
///
/// The app makes one where it starts, from the decisions it saved, gives it to its tracker, and
/// updates it as the user decides:
///
/// ```swift
/// let consent = Consent([.analytics: .granted])
/// let tracker = Tracker(consent: consent)
/// // Later, from the consent prompt:
/// consent.grant(.advertising)
/// ```
///
/// Each event is gated by its type's `Event.consentCategory`, by the decisions made before it was
/// tracked:
///
/// - **Granted:** delivered as any event is, written to the tracker's store first if it has one.
/// - **Undecided:** held in memory, and not written to the store, until the category is decided.
///   Granting it delivers its held events in the order they were tracked, before any event
///   tracked after the grant; denying it drops them, reported on ``dropReports``. The hold keeps
///   at most `heldRecordLimit` events across every category and tracker: when it is full, its
///   oldest is dropped to make room, reported as it happens (merged with the overflow reports
///   not yet read). Held events are lost if the app
///   ends first.
/// - **Denied:** dropped, and not collected at all, so not reported.
///
/// Records a store recovered from an earlier run are gated again as the tracker starts, as
/// consent may have changed since. One whose category is now denied is dropped, reported and
/// forgotten by the store. One whose category is undecided is held outside the bound, still kept
/// by the store, so a full hold never drops it; if the app ends first, it is gated again on the
/// next launch. One the store drops for its own byte bound while held is reported by the store
/// and still delivered if granted in this run, as a record a delivery has already read is.
///
/// A category not given a status is undecided. Withdrawing consent is a denial: records the
/// tracker had already let through when it was granted are still delivered.
///
/// Copies share one set of decisions and one hold. A decision returns at once, from any thread:
/// it records the status, which ``status(of:)`` returns from then on, and queues the decision
/// for each tracker given the consent, whose own worker releases or drops what it held. Each
/// tracker reports its own drops.
public struct Consent: Sendable {
    /// The most records a consent holds unless it is given another bound: 1,000.
    public static let defaultHeldRecordLimit = 1_000

    let gate: ConsentGate

    /// A consent with the categories in `statuses` decided, and every other undecided, holding
    /// at most ``defaultHeldRecordLimit`` records while undecided.
    ///
    /// - Parameter statuses: Each category's status as the app last saved it.
    public init(_ statuses: [ConsentCategory: ConsentStatus] = [:]) {
        gate = ConsentGate(statuses: statuses, heldRecordLimit: Consent.defaultHeldRecordLimit)
    }

    /// A consent with the categories in `statuses` decided, and every other undecided, holding
    /// at most `heldRecordLimit` records while undecided.
    ///
    /// - Parameters:
    ///   - statuses: Each category's status as the app last saved it.
    ///   - heldRecordLimit: The most records held while undecided, across every category; 0
    ///     drops every undecided event.
    /// - Throws: ``NegativeHeldRecordLimit`` when `heldRecordLimit` is negative.
    public init(_ statuses: [ConsentCategory: ConsentStatus] = [:], heldRecordLimit: Int) throws(NegativeHeldRecordLimit) {
        guard heldRecordLimit >= 0 else { throw NegativeHeldRecordLimit() }
        gate = ConsentGate(statuses: statuses, heldRecordLimit: heldRecordLimit)
    }

    /// Grants `categories`: their held events are delivered, oldest first, and later ones as they
    /// are tracked.
    ///
    /// Returns at once, from any thread: each tracker's worker delivers what it held, writing it
    /// to its store first, off the caller's thread.
    ///
    /// - Parameter categories: The categories the user consented to.
    public func grant(_ categories: ConsentCategory...) {
        gate.decide(categories, .granted)
    }

    /// Denies `categories`: their held events are dropped, reported on ``dropReports``, and later
    /// ones are not collected.
    ///
    /// Returns at once, from any thread: each tracker's worker drops what it held.
    ///
    /// - Parameter categories: The categories the user refused.
    public func deny(_ categories: ConsentCategory...) {
        gate.decide(categories, .denied)
    }

    /// The status of `category`: undecided unless given or decided.
    ///
    /// - Parameter category: The category to look up.
    /// - Returns: Its status.
    public func status(of category: ConsentCategory) -> ConsentStatus {
        gate.status(of: category)
    }

    /// How many records are held, waiting for their category to be decided: those held in memory
    /// only and those a store recovered.
    public var heldRecordCount: Int {
        gate.heldRecordCount
    }

    /// A report of each drop of held or recovered records, in the order they happen.
    ///
    /// Reports wait until they are read. A record dropped for room is reported as it is
    /// dropped; while that report waits unread, later ones merge into it, one report counting
    /// them all across their timestamps. So the reports waiting unread hold at most one overflow
    /// report between any two others (denials and finished trackers), however many events
    /// overflow. The sequence has one
    /// consumer, and ends once the consent is gone.
    public var dropReports: AsyncStream<ConsentDropReport> {
        gate.dropReports
    }
}
