import Events
import Foundation
import Testing

@Suite("ConsentCategory")
struct ConsentCategoryTests {
    struct Tapped: Event {
        var number: Int
    }

    struct AdClicked: Event {
        static let consentCategory = ConsentCategory.advertising
    }

    @Test("An event type that names no category is in analytics")
    func defaultCategory() {
        let expected = ConsentCategory.analytics

        let actual = Tapped.consentCategory

        #expect(actual == expected)
    }

    @Test("An event type's own category replaces the default")
    func ownCategory() {
        let expected = ConsentCategory.advertising

        let actual = AdClicked.consentCategory

        #expect(actual == expected)
    }

    @Test("A record's category is its event type's")
    func recordCategory() {
        let sut = EventRecord(event: AdClicked(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = ConsentCategory.advertising

        let actual = sut.consentCategory

        #expect(actual == expected)
    }

    @Test("Two categories with the same name are the same category; different names differ")
    func identityByName() {
        let sut = ConsentCategory("analytics")
        let other = ConsentCategory("Analytics")

        #expect(sut == .analytics)
        #expect(sut != other)
    }

    @Test("The built-in categories each have a name of their own, which describes them")
    func builtInNames() {
        let expected = ["analytics", "advertising", "functional", "personalization"]

        let actual = [ConsentCategory.analytics, .advertising, .functional, .personalization].map(\.description)

        #expect(actual == expected)
        #expect(Set(actual).count == expected.count)
    }

    @Test("A category's name is the name it was made with, even an empty one")
    func emptyName() {
        let expected = ""

        let actual = ConsentCategory("").name

        #expect(actual == expected)
    }
}
