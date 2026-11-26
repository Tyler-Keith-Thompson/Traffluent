public import Foundation
import Logging
public import Trackers
public import Events

/// The shopper's consent to each purpose the store collects events for, restored from a file as
/// the app launches and saved to it with each decision.
///
/// A `Consent` keeps decisions in memory only, so an app that didn't restore them would hold every
/// event again on each launch until the shopper decided once more.
public struct ConsentPreferences: Sendable {
    /// The purposes the store asks about, in the order the privacy screen lists them.
    public static let categories: [ConsentCategory] = [.analytics, .functional, .advertising]

    /// The consent the tracker gates events with.
    public let consent: Consent
    /// Where the decisions are saved.
    public let file: URL

    private static let logger = Logger(label: "StoreAnalytics.ConsentPreferences")

    /// The preferences saved in `file`, or every category undecided when it holds none.
    ///
    /// - Parameter file: Where the decisions are saved.
    public init(file: URL) {
        self.file = file
        consent = Consent(Self.load(from: file))
    }

    /// Whether the shopper has decided about every category the store asks about.
    public var isComplete: Bool {
        Self.categories.allSatisfy { consent.status(of: $0) != .undecided }
    }

    /// What the shopper decided about `category`.
    ///
    /// - Parameter category: The purpose asked about.
    /// - Returns: Its status.
    public func status(of category: ConsentCategory) -> ConsentStatus {
        consent.status(of: category)
    }

    /// Grants `category`, delivering the events held for it, and saves the decision.
    ///
    /// - Parameter category: The purpose the shopper allowed.
    public func grant(_ category: ConsentCategory) {
        consent.grant(category)
        save()
    }

    /// Denies `category`, dropping the events held for it, and saves the decision.
    ///
    /// - Parameter category: The purpose the shopper refused.
    public func deny(_ category: ConsentCategory) {
        consent.deny(category)
        save()
    }

    private func save() {
        var saved: [String: Bool] = [:]
        for category in Self.categories {
            switch consent.status(of: category) {
            case .granted: saved[category.name] = true
            case .denied: saved[category.name] = false
            case .undecided: break
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(saved).write(to: file, options: .atomic)
        } catch {
            // The decision still holds for this launch; the next one asks again.
            Self.logger.error("Couldn't save the consent decisions: \(error)")
        }
    }

    private static func load(from file: URL) -> [ConsentCategory: ConsentStatus] {
        guard let data = try? Data(contentsOf: file),
            let saved = try? JSONDecoder().decode([String: Bool].self, from: data)
        else { return [:] }
        var statuses: [ConsentCategory: ConsentStatus] = [:]
        for (name, granted) in saved {
            statuses[ConsentCategory(name)] = granted ? .granted : .denied
        }
        return statuses
    }
}
