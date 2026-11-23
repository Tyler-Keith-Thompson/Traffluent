import Events
import Foundation
import StandardContext
import Testing
import Trackers

@Suite("StandardContext: the locale", .timeLimit(.minutes(1)))
struct LocaleEnricherTests {
    struct Tapped: Event {
        var number: Int
    }

    @Test("The locale enricher sets LocaleKey to the locale it was made with, whose identifier, language and region a destination reads")
    func setsTheGivenValue() async throws {
        let expected = Locale(identifier: "fr_CA")
        let expectedLanguage = "fr"
        let expectedRegion = "CA"
        let sut = Tracker(enrichers: [.locale(expected)])

        sut.track(Tapped(number: 1))
        sut.track(Tapped(number: 2))
        await sut.finish()

        var actual: [Locale] = []
        for await record in sut.records {
            actual.append(try #require(record.context[LocaleKey.self]))
        }
        #expect(actual == [expected, expected])
        #expect(actual.first?.identifier == "fr_CA")
        #expect(actual.first?.language.languageCode?.identifier == expectedLanguage)
        #expect(actual.first?.region?.identifier == expectedRegion)
    }

    @Test("By default the locale is the user's, Locale.current")
    func defaultIsCurrent() async throws {
        let expected = Locale.current.identifier
        let sut = Tracker(enrichers: [.locale()])

        sut.track(Tapped(number: 1))
        await sut.finish()

        var records = sut.records.makeAsyncIterator()
        let actual = try #require(await records.next()).context[LocaleKey.self]?.identifier
        #expect(actual == expected)
    }
}
