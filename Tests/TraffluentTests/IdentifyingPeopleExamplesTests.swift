// The examples of the "Identifying People" article
// (Sources/Traffluent/Traffluent.docc/IdentifyingPeople.md), verbatim, so they keep compiling.

import Foundation
import Instrumentation
import Synchronization
import Testing
import Traffluent

extension ConsentCategory {
    static let identification = ConsentCategory("identification")
}

enum AccountKey: ServiceContextKey {
    typealias Value = Sensitive<String>
}

final class SignedInAccount: Sendable {
    private let identifier = Mutex<String?>(nil)

    var current: String? {
        identifier.withLock { $0 }
    }

    func signIn(as id: String) {
        identifier.withLock { $0 = id }  // and save it to the Keychain
    }

    func signOut() {
        identifier.withLock { $0 = nil }  // and delete it from the Keychain
    }
}

@Suite("Identifying people examples", .timeLimit(.minutes(1)))
struct IdentifyingPeopleExamplesTests {
    @Event
    struct CheckoutStarted {
        var itemCount: Int
    }

    @Test("An app's own identifier lands on each record while signed in, and not after sign-out")
    func identifierUntilSignOut() async throws {
        let ownBackend = InMemoryDestination()
        let vendor = InMemoryDestination()
        let consent = Consent([.analytics: .granted, .identification: .granted])
        let account = SignedInAccount()
        let accountIdentifier = Enricher { context in
            guard consent.status(of: .identification) == .granted, let id = account.current else { return }
            context[AccountKey.self] = Sensitive(id)
        }
        let tracker = Tracker(consent: consent, enrichers: [.sessions(), accountIdentifier])
        let delivery = tracker.records.batch().deliver(
            to: ownBackend,
            vendor.redactingSensitiveValues()
        )

        account.signIn(as: "account-42")
        tracker.track(CheckoutStarted(itemCount: 3))  // carries AccountKey and SessionKey

        await tracker.flush()
        account.signOut()
        tracker.track(CheckoutStarted(itemCount: 1))  // carries SessionKey only
        await tracker.finish()
        try await delivery.execute()

        let checkouts = ownBackend.records.filter { $0.event is CheckoutStarted }
        let vendorCheckouts = vendor.records.filter { $0.event is CheckoutStarted }
        try #require(checkouts.count == 2)
        try #require(vendorCheckouts.count == 2)
        let expectedIdentifier: String? = "account-42"
        let actual = checkouts.map { record in
            let accountID = record.context[AccountKey.self].flatMap(record.reveal)  // nil for the vendor
            return accountID
        }
        let actualForVendor = vendorCheckouts.map { record in
            let accountID = record.context[AccountKey.self].flatMap(record.reveal)  // nil for the vendor
            return accountID
        }
        let actualSessions = checkouts.map { $0.context[SessionKey.self] }
        #expect(actual == [expectedIdentifier, nil])
        #expect(actualForVendor == [nil, nil])
        #expect(actualSessions.allSatisfy { $0 != nil })
    }

    @Test("The enricher adds no identifier once its consent category is denied")
    func noIdentifierWithoutConsent() async throws {
        let ownBackend = InMemoryDestination()
        let consent = Consent([.analytics: .granted, .identification: .granted])
        let account = SignedInAccount()
        let accountIdentifier = Enricher { context in
            guard consent.status(of: .identification) == .granted, let id = account.current else { return }
            context[AccountKey.self] = Sensitive(id)
        }
        let tracker = Tracker(consent: consent, enrichers: [.sessions(), accountIdentifier])
        let delivery = tracker.records.batch().deliver(to: ownBackend)
        account.signIn(as: "account-42")
        consent.deny(.identification)

        tracker.track(CheckoutStarted(itemCount: 3))
        await tracker.finish()
        try await delivery.execute()

        let checkouts = ownBackend.records.filter { $0.event is CheckoutStarted }
        try #require(checkouts.count == 1)
        let actual = checkouts[0].context[AccountKey.self]
        let actualSession = checkouts[0].context[SessionKey.self]
        #expect(actual == nil)
        #expect(actualSession != nil)
    }
}
