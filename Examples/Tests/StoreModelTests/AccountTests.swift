import StoreEvents
import StoreModel
import Testing
import Trackers
import TrackerTesting

@Suite("Account", .timeLimit(.minutes(1)))
struct AccountTests {
    @Test("Signing up tracks SignedUp with the plan, and the email address only as a sensitive value")
    func signUp() async throws {
        let expectedPlans = ["plus"]
        let expectedEmail = "shopper@example.com"
        let expectedDescription = "<redacted>"

        let tracked = await withRecordingTracker {
            Account.signUp(email: "shopper@example.com", plan: .plus)
        }

        let event = try #require(tracked.events(of: SignedUp.self).first)
        let record = try #require(tracked.records.first)
        #expect(tracked.events(of: SignedUp.self).map(\.plan) == expectedPlans)
        let email = event.email
        #expect(record.reveal(email) == expectedEmail)
        #expect(String(describing: email) == expectedDescription)
        #expect(tracked.value == Account(email: "shopper@example.com", plan: .plus))
    }

    @Test("SignedUp is collected for the account, not for analytics")
    func signUpCategory() {
        let expected = "functional"

        let actual = SignedUp.consentCategory.name

        #expect(actual == expected)
    }
}
