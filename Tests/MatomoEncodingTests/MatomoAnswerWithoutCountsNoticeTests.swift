import DestinationTesting
import EventMacros
import Foundation
import HTTPDestinations
import HTTPTypes
import MatomoEncoding
import Testing
import TrackingPlans

// The notice a Matomo destination logs the first time a 2xx answer isn't a bulk answer with its
// counts, as QueuedTracking's GIF isn't. Tests don't pin logs, so each reads how many times the
// encoder, which the destination's copies share, has logged it: through the destination
// (answerWithoutCountsNoticeCount) where a destination sends, through the encoder where a test
// asks it directly.

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("Matomo: the notice of an answer without tracking counts", .timeLimit(.minutes(1)))
private struct MatomoAnswerWithoutCountsNoticeTests {
    @Event(name: "app_opened")
    struct AppOpened {}

    @Test("With QueuedTracking on, the recorded GIF answer logs the destination's notice once, and a second GIF answer to the same destination is delivered and logs none")
    func queueOnGIFLogsOnce() async throws {
        let headersURL = try #require(Bundle.module.url(forResource: "valid", withExtension: "headers", subdirectory: "Fixtures/RecordedAnswers/queue-on"))
        let bodyURL = try #require(Bundle.module.url(forResource: "valid", withExtension: "body", subdirectory: "Fixtures/RecordedAnswers/queue-on"))
        let statusLine = String(decoding: try Data(contentsOf: headersURL), as: UTF8.self).prefix { $0 != "\r" }
        let code = try #require(statusLine.split(separator: " ").dropFirst().first.flatMap { Int($0) })
        let gif = ScriptedTransport.Answer.response(HTTPResponse.Status(code: code), body: try Data(contentsOf: bodyURL))
        let url = try #require(URL(string: "https://analytics.example.com"))
        let transport = ScriptedTransport([gif, gif, .status(.badRequest)])
        let sut = try HTTPDestination.matomo(url: url, siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [AppOpened.schema]), transport: transport, now: { Date(timeIntervalSince1970: 1_795_868_273) })
        let first = [EventRecord(event: AppOpened(), timestamp: Date(timeIntervalSince1970: 1_795_868_243), sourceLocation: nil)]
        let second = [EventRecord(event: AppOpened(), timestamp: Date(timeIntervalSince1970: 1_795_868_253), sourceLocation: nil)]
        let refused = [EventRecord(event: AppOpened(), timestamp: Date(timeIntervalSince1970: 1_795_868_263), sourceLocation: nil)]
        // The 400 to the third batch is the first report, so neither GIF answer was reported.
        let expectedReport = HTTPDropReport<MatomoEncodingError>.rejected(status: .badRequest, recordIDs: refused.map(\.id))
        let expectedRequestCount = 3
        let expectedCountBefore = 0
        let expectedCountAfterFirst = 1
        let expectedCountAfterSecond = 1
        let countBefore = sut.answerWithoutCountsNoticeCount

        await sut.receive(first)
        let countAfterFirst = sut.answerWithoutCountsNoticeCount
        await sut.receive(second)
        let countAfterSecond = sut.answerWithoutCountsNoticeCount
        await sut.receive(refused)

        var reports = sut.dropReports.makeAsyncIterator()
        let actualReport = await reports.next()
        #expect(countBefore == expectedCountBefore)
        #expect(countAfterFirst == expectedCountAfterFirst)
        #expect(countAfterSecond == expectedCountAfterSecond)
        #expect(actualReport == expectedReport)
        #expect(transport.requests.count == expectedRequestCount)
    }

    @Test(
        "With QueuedTracking off, each recorded 2xx bulk answer logs no notice, and its outcome is the encoder's for that answer",
        arguments: [
            ("queue-off", "valid", ResponseOutcome.delivered),
            ("queue-off", "unknown-site", ResponseOutcome.rejected(reason: "Matomo refused all 3 of the request's tracking requests as invalid, as it does for a site ID of no site")),
            ("queue-off", "mixed-sites", ResponseOutcome.delivered),
            ("queue-off", "stale-timestamp", ResponseOutcome.rejected(reason: "Matomo refused all 1 of the request's tracking requests as invalid, as it does for a site ID of no site")),
            ("queue-off", "bad-token", ResponseOutcome.delivered),
            ("queue-off-record-statistics-0", "valid", ResponseOutcome.transient(reason: "Matomo counted 0 tracked and 0 invalid of the request's 3 tracking requests, and skipped the rest")),
        ])
    func queueOffBulkAnswerLogsNothing(directory: String, name: String, expected: ResponseOutcome) throws {
        let requestURL = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/RecordedAnswers/requests"))
        let headersURL = try #require(Bundle.module.url(forResource: name, withExtension: "headers", subdirectory: "Fixtures/RecordedAnswers/\(directory)"))
        let bodyURL = try #require(Bundle.module.url(forResource: name, withExtension: "body", subdirectory: "Fixtures/RecordedAnswers/\(directory)"))
        let sent = try JSONDecoder().decode(Request.self, from: Data(contentsOf: requestURL))
        let statusLine = String(decoding: try Data(contentsOf: headersURL), as: UTF8.self).prefix { $0 != "\r" }
        let code = try #require(statusLine.split(separator: " ").dropFirst().first.flatMap { Int($0) })
        let request = EncodedRequest(body: EncodedBatch(body: try Data(contentsOf: requestURL), contentType: "application/json"), recordIDs: sent.requests.map { _ in UUID() })
        let response = HTTPTransportResponse(head: HTTPResponse(status: HTTPResponse.Status(code: code)), body: try Data(contentsOf: bodyURL))
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [AppOpened.schema]))
        let expectedCount = 0

        sut.didReceive(response, for: request)
        let actual = MatomoBatchEncoder.outcome(of: response, for: request)

        #expect(sut.answerWithoutCountsNoticeCount == expectedCount)
        #expect(actual == expected)
    }

    @Test("With QueuedTracking off, the recorded bulk answer to three valid tracking requests, through a destination, is delivered and logs no notice")
    func queueOffDestinationLogsNothing() async throws {
        let headersURL = try #require(Bundle.module.url(forResource: "valid", withExtension: "headers", subdirectory: "Fixtures/RecordedAnswers/queue-off"))
        let bodyURL = try #require(Bundle.module.url(forResource: "valid", withExtension: "body", subdirectory: "Fixtures/RecordedAnswers/queue-off"))
        let statusLine = String(decoding: try Data(contentsOf: headersURL), as: UTF8.self).prefix { $0 != "\r" }
        let code = try #require(statusLine.split(separator: " ").dropFirst().first.flatMap { Int($0) })
        let url = try #require(URL(string: "https://analytics.example.com"))
        let transport = ScriptedTransport([.response(HTTPResponse.Status(code: code), body: try Data(contentsOf: bodyURL)), .status(.badRequest)])
        let sut = try HTTPDestination.matomo(url: url, siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [AppOpened.schema]), transport: transport, now: { Date(timeIntervalSince1970: 1_795_868_273) })
        // The recorded answer counts three tracked, so the batch has three records, as the
        // recorded request did.
        let batch = [1_795_868_243, 1_795_868_253, 1_795_868_263].map { EventRecord(event: AppOpened(), timestamp: Date(timeIntervalSince1970: $0), sourceLocation: nil) }
        let refused = [EventRecord(event: AppOpened(), timestamp: Date(timeIntervalSince1970: 1_795_868_270), sourceLocation: nil)]
        let expectedReport = HTTPDropReport<MatomoEncodingError>.rejected(status: .badRequest, recordIDs: refused.map(\.id))
        let expectedRequestCount = 2
        let expectedCount = 0

        await sut.receive(batch)
        await sut.receive(refused)

        var reports = sut.dropReports.makeAsyncIterator()
        let actualReport = await reports.next()
        #expect(sut.answerWithoutCountsNoticeCount == expectedCount)
        #expect(actualReport == expectedReport)
        #expect(transport.requests.count == expectedRequestCount)
    }

    @Test("Two destinations made by HTTPDestination.matomo each log their own notice: the first one's GIF answer leaves the second's unlogged, and its own GIF answer logs it once")
    func factoryDestinationsLogTheirOwn() async throws {
        let headersURL = try #require(Bundle.module.url(forResource: "valid", withExtension: "headers", subdirectory: "Fixtures/RecordedAnswers/queue-on"))
        let bodyURL = try #require(Bundle.module.url(forResource: "valid", withExtension: "body", subdirectory: "Fixtures/RecordedAnswers/queue-on"))
        let statusLine = String(decoding: try Data(contentsOf: headersURL), as: UTF8.self).prefix { $0 != "\r" }
        let code = try #require(statusLine.split(separator: " ").dropFirst().first.flatMap { Int($0) })
        let gif = ScriptedTransport.Answer.response(HTTPResponse.Status(code: code), body: try Data(contentsOf: bodyURL))
        let url = try #require(URL(string: "https://analytics.example.com"))
        let plan = try TrackingPlan(schemas: [AppOpened.schema])
        let first = try HTTPDestination.matomo(url: url, siteID: 1, dimensions: [:], category: "Shop", plan: plan, transport: ScriptedTransport([gif]), now: { Date(timeIntervalSince1970: 1_795_868_273) })
        let second = try HTTPDestination.matomo(url: url, siteID: 1, dimensions: [:], category: "Shop", plan: plan, transport: ScriptedTransport([gif]), now: { Date(timeIntervalSince1970: 1_795_868_273) })
        let batch = [EventRecord(event: AppOpened(), timestamp: Date(timeIntervalSince1970: 1_795_868_243), sourceLocation: nil)]
        let expectedFirstCount = 1
        let expectedSecondCountAfterFirst = 0
        let expectedSecondCount = 1

        await first.receive(batch)
        let secondCountAfterFirst = second.answerWithoutCountsNoticeCount
        await second.receive(batch)

        #expect(first.answerWithoutCountsNoticeCount == expectedFirstCount)
        #expect(secondCountAfterFirst == expectedSecondCountAfterFirst)
        #expect(second.answerWithoutCountsNoticeCount == expectedSecondCount)
    }

    @Test("Two encoders, as HTTPDestination.matomo makes one for each destination, each log their own notice")
    func encodersLogTheirOwn() throws {
        let request = EncodedRequest(body: EncodedBatch(body: Data(#"{"requests":["?idsite=1"]}"#.utf8), contentType: "application/json"), recordIDs: [UUID()])
        let response = HTTPTransportResponse(head: HTTPResponse(status: .ok), body: Data("GIF89a".utf8))
        let plan = try TrackingPlan(schemas: [AppOpened.schema])
        let first = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: plan)
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: plan)
        let expectedCountAfterFirst = 0
        let expectedCount = 1

        first.didReceive(response, for: request)
        let countAfterFirst = sut.answerWithoutCountsNoticeCount
        sut.didReceive(response, for: request)

        #expect(countAfterFirst == expectedCountAfterFirst)
        #expect(sut.answerWithoutCountsNoticeCount == expectedCount)
    }

    @Test("A copy of a Matomo destination shares its notice: a GIF answer to the copy and one to the original log it once between them")
    func copySharesTheNotice() async throws {
        let headersURL = try #require(Bundle.module.url(forResource: "valid", withExtension: "headers", subdirectory: "Fixtures/RecordedAnswers/queue-on"))
        let bodyURL = try #require(Bundle.module.url(forResource: "valid", withExtension: "body", subdirectory: "Fixtures/RecordedAnswers/queue-on"))
        let statusLine = String(decoding: try Data(contentsOf: headersURL), as: UTF8.self).prefix { $0 != "\r" }
        let code = try #require(statusLine.split(separator: " ").dropFirst().first.flatMap { Int($0) })
        let url = try #require(URL(string: "https://analytics.example.com"))
        let transport = ScriptedTransport([.response(HTTPResponse.Status(code: code), body: try Data(contentsOf: bodyURL))])
        let original = try HTTPDestination.matomo(url: url, siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [AppOpened.schema]), transport: transport, now: { Date(timeIntervalSince1970: 1_795_868_273) })
        let sut = original
        let first = [EventRecord(event: AppOpened(), timestamp: Date(timeIntervalSince1970: 1_795_868_243), sourceLocation: nil)]
        let second = [EventRecord(event: AppOpened(), timestamp: Date(timeIntervalSince1970: 1_795_868_253), sourceLocation: nil)]
        let expectedCount = 1
        let expectedRequestCount = 2

        await sut.receive(first)
        await original.receive(second)

        #expect(sut.answerWithoutCountsNoticeCount == expectedCount)
        #expect(original.answerWithoutCountsNoticeCount == expectedCount)
        #expect(transport.requests.count == expectedRequestCount)
    }

    @Test("With QueuedTracking on, Matomo's 400 with a GIF body to a malformed request is dropped and logs no notice, which only a 2xx answer can")
    func queueOnMalformedLogsNothing() async throws {
        let headersURL = try #require(Bundle.module.url(forResource: "malformed", withExtension: "headers", subdirectory: "Fixtures/RecordedAnswers/queue-on"))
        let bodyURL = try #require(Bundle.module.url(forResource: "malformed", withExtension: "body", subdirectory: "Fixtures/RecordedAnswers/queue-on"))
        let statusLine = String(decoding: try Data(contentsOf: headersURL), as: UTF8.self).prefix { $0 != "\r" }
        let code = try #require(statusLine.split(separator: " ").dropFirst().first.flatMap { Int($0) })
        let url = try #require(URL(string: "https://analytics.example.com"))
        let sut = try HTTPDestination.matomo(url: url, siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [AppOpened.schema]), transport: ScriptedTransport([.response(HTTPResponse.Status(code: code), body: try Data(contentsOf: bodyURL))]), now: { Date(timeIntervalSince1970: 1_795_868_273) })
        let batch = [EventRecord(event: AppOpened(), timestamp: Date(timeIntervalSince1970: 1_795_868_243), sourceLocation: nil)]
        let expectedReport = HTTPDropReport<MatomoEncodingError>.rejected(status: .badRequest, recordIDs: batch.map(\.id))
        let expectedCount = 0

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actualReport = await reports.next()
        #expect(actualReport == expectedReport)
        #expect(sut.answerWithoutCountsNoticeCount == expectedCount)
    }

    @Test(
        "A 2xx body that isn't a bulk answer logs the notice once and is delivered: an empty body, JSON without the counts, a negative count and an HTML page",
        arguments: [
            "",
            #"{"status":"success"}"#,
            #"{"status":"success","tracked":3}"#,
            #"{"status":"success","tracked":-1,"invalid":0}"#,
            "<html><body>Bad gateway</body></html>",
        ])
    func notABulkAnswerLogs(body: String) throws {
        let request = EncodedRequest(body: EncodedBatch(body: Data(#"{"requests":["?idsite=1"]}"#.utf8), contentType: "application/json"), recordIDs: [UUID()])
        let response = HTTPTransportResponse(head: HTTPResponse(status: .ok), body: Data(body.utf8))
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [AppOpened.schema]))
        let expected = ResponseOutcome.delivered
        let expectedCount = 1

        sut.didReceive(response, for: request)
        sut.didReceive(response, for: request)
        let actual = MatomoBatchEncoder.outcome(of: response, for: request)

        #expect(sut.answerWithoutCountsNoticeCount == expectedCount)
        #expect(actual == expected)
    }

    @Test("A bulk answer with both counts 0 is a bulk answer: it logs no notice")
    func zeroCountsLogNothing() throws {
        let request = EncodedRequest(body: EncodedBatch(body: Data(#"{"requests":["?idsite=1"]}"#.utf8), contentType: "application/json"), recordIDs: [UUID()])
        let response = HTTPTransportResponse(head: HTTPResponse(status: .ok), body: Data(#"{"status":"success","tracked":0,"invalid":0}"#.utf8))
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [AppOpened.schema]))
        let expectedCount = 0

        sut.didReceive(response, for: request)

        #expect(sut.answerWithoutCountsNoticeCount == expectedCount)
    }

    /// A recorded request's body: its tracking requests, and any other member ignored.
    struct Request: Decodable {
        var requests: [String]
    }
}
