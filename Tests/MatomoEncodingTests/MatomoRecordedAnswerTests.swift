import DestinationTesting
import EventMacros
import Foundation
import HTTPDestinations
import HTTPTypes
import Instrumentation
import MatomoEncoding
import StandardContext
import Testing
import TrackingPlans

// Each fixture under Fixtures/RecordedAnswers is an answer a local Matomo 6.0.0 gave on
// 2026-11-28 to a request under requests/, with QueuedTracking 6.0.5 off or on: its status line
// and headers (`<case>.headers`) and its body (`<case>.body`) as received. The fixtures' README
// says how they were recorded. Each test reads the request's tracking requests and the answer's
// status and body, and asks the encoder what the answer means.

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("Matomo's recorded answers", .timeLimit(.minutes(1)))
private struct MatomoRecordedAnswerTests {
    @Event(name: "app_opened")
    struct AppOpened {}

    @Event(name: "checkout_started")
    struct CheckoutStarted {}

    @Event(name: "checkout_completed")
    struct CheckoutCompleted {}

    @Test("The recorded requests are the encoder's: three events of one session in site 1 are the recorded valid request, byte for byte")
    func recordedRequestIsTheEncoders() throws {
        let fixture = try #require(Bundle.module.url(forResource: "valid", withExtension: "json", subdirectory: "Fixtures/RecordedAnswers/requests"))
        let expected = try Data(contentsOf: fixture)
        let plan = try TrackingPlan(schemas: [AppOpened.schema, CheckoutStarted.schema, CheckoutCompleted.schema])
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        context[LocaleKey.self] = Locale(identifier: "en_US")
        let batch = [
            EventRecord(event: AppOpened(), timestamp: Date(timeIntervalSince1970: 1_795_868_243), sourceLocation: nil, context: context),
            EventRecord(event: CheckoutStarted(), timestamp: Date(timeIntervalSince1970: 1_795_868_253), sourceLocation: nil, context: context),
            EventRecord(event: CheckoutCompleted(), timestamp: Date(timeIntervalSince1970: 1_795_868_263), sourceLocation: nil, context: context),
        ]
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: plan, now: { Date(timeIntervalSince1970: 1_795_868_273) })

        let actual = sut.requests(for: batch).requests.map(\.body.body)

        #expect(actual == [expected])
    }

    // QueuedTracking off.

    @Test("With QueuedTracking off, Matomo's answer to three valid tracking requests, all tracked, is delivered")
    func queueOffValid() throws {
        let requestURL = try #require(Bundle.module.url(forResource: "valid", withExtension: "json", subdirectory: "Fixtures/RecordedAnswers/requests"))
        let headersURL = try #require(Bundle.module.url(forResource: "valid", withExtension: "headers", subdirectory: "Fixtures/RecordedAnswers/queue-off"))
        let bodyURL = try #require(Bundle.module.url(forResource: "valid", withExtension: "body", subdirectory: "Fixtures/RecordedAnswers/queue-off"))
        let sent = try JSONDecoder().decode(Request.self, from: Data(contentsOf: requestURL))
        let statusLine = String(decoding: try Data(contentsOf: headersURL), as: UTF8.self).prefix { $0 != "\r" }
        let code = try #require(statusLine.split(separator: " ").dropFirst().first.flatMap { Int($0) })
        let request = EncodedRequest(body: EncodedBatch(body: try Data(contentsOf: requestURL), contentType: "application/json"), recordIDs: sent.requests.map { _ in UUID() })
        let response = HTTPTransportResponse(head: HTTPResponse(status: HTTPResponse.Status(code: code)), body: try Data(contentsOf: bodyURL))
        let expected = ResponseOutcome.delivered

        let actual = MatomoBatchEncoder.outcome(of: response, for: request)

        #expect(actual == expected)
    }

    @Test("With QueuedTracking off, Matomo's answer to three tracking requests for a site ID of no site, all invalid, is rejected")
    func queueOffUnknownSite() throws {
        let requestURL = try #require(Bundle.module.url(forResource: "unknown-site", withExtension: "json", subdirectory: "Fixtures/RecordedAnswers/requests"))
        let headersURL = try #require(Bundle.module.url(forResource: "unknown-site", withExtension: "headers", subdirectory: "Fixtures/RecordedAnswers/queue-off"))
        let bodyURL = try #require(Bundle.module.url(forResource: "unknown-site", withExtension: "body", subdirectory: "Fixtures/RecordedAnswers/queue-off"))
        let sent = try JSONDecoder().decode(Request.self, from: Data(contentsOf: requestURL))
        let statusLine = String(decoding: try Data(contentsOf: headersURL), as: UTF8.self).prefix { $0 != "\r" }
        let code = try #require(statusLine.split(separator: " ").dropFirst().first.flatMap { Int($0) })
        let request = EncodedRequest(body: EncodedBatch(body: try Data(contentsOf: requestURL), contentType: "application/json"), recordIDs: sent.requests.map { _ in UUID() })
        let response = HTTPTransportResponse(head: HTTPResponse(status: HTTPResponse.Status(code: code)), body: try Data(contentsOf: bodyURL))
        let expected = ResponseOutcome.rejected(reason: "Matomo refused all 3 of the request's tracking requests as invalid, as it does for a site ID of no site")

        let actual = MatomoBatchEncoder.outcome(of: response, for: request)

        #expect(actual == expected)
    }

    @Test("With QueuedTracking off, Matomo's answer to a tracking request for site 1 and one for a site ID of no site, one tracked and one invalid, is delivered")
    func queueOffMixedSites() throws {
        let requestURL = try #require(Bundle.module.url(forResource: "mixed-sites", withExtension: "json", subdirectory: "Fixtures/RecordedAnswers/requests"))
        let headersURL = try #require(Bundle.module.url(forResource: "mixed-sites", withExtension: "headers", subdirectory: "Fixtures/RecordedAnswers/queue-off"))
        let bodyURL = try #require(Bundle.module.url(forResource: "mixed-sites", withExtension: "body", subdirectory: "Fixtures/RecordedAnswers/queue-off"))
        let sent = try JSONDecoder().decode(Request.self, from: Data(contentsOf: requestURL))
        let statusLine = String(decoding: try Data(contentsOf: headersURL), as: UTF8.self).prefix { $0 != "\r" }
        let code = try #require(statusLine.split(separator: " ").dropFirst().first.flatMap { Int($0) })
        let request = EncodedRequest(body: EncodedBatch(body: try Data(contentsOf: requestURL), contentType: "application/json"), recordIDs: sent.requests.map { _ in UUID() })
        let response = HTTPTransportResponse(head: HTTPResponse(status: HTTPResponse.Status(code: code)), body: try Data(contentsOf: bodyURL))
        let expected = ResponseOutcome.delivered

        let actual = MatomoBatchEncoder.outcome(of: response, for: request)

        #expect(actual == expected)
    }

    @Test("With QueuedTracking off, Matomo's answer to a tracking request whose cdt is two days old, sent without a token, invalid, is rejected")
    func queueOffStaleTimestamp() throws {
        let requestURL = try #require(Bundle.module.url(forResource: "stale-timestamp", withExtension: "json", subdirectory: "Fixtures/RecordedAnswers/requests"))
        let headersURL = try #require(Bundle.module.url(forResource: "stale-timestamp", withExtension: "headers", subdirectory: "Fixtures/RecordedAnswers/queue-off"))
        let bodyURL = try #require(Bundle.module.url(forResource: "stale-timestamp", withExtension: "body", subdirectory: "Fixtures/RecordedAnswers/queue-off"))
        let sent = try JSONDecoder().decode(Request.self, from: Data(contentsOf: requestURL))
        let statusLine = String(decoding: try Data(contentsOf: headersURL), as: UTF8.self).prefix { $0 != "\r" }
        let code = try #require(statusLine.split(separator: " ").dropFirst().first.flatMap { Int($0) })
        let request = EncodedRequest(body: EncodedBatch(body: try Data(contentsOf: requestURL), contentType: "application/json"), recordIDs: sent.requests.map { _ in UUID() })
        let response = HTTPTransportResponse(head: HTTPResponse(status: HTTPResponse.Status(code: code)), body: try Data(contentsOf: bodyURL))
        let expected = ResponseOutcome.rejected(reason: "Matomo refused all 1 of the request's tracking requests as invalid, as it does for a site ID of no site")

        let actual = MatomoBatchEncoder.outcome(of: response, for: request)

        #expect(actual == expected)
    }

    @Test("With QueuedTracking off, Matomo's answer to three valid tracking requests sent with a token_auth of no user, all tracked, is delivered")
    func queueOffBadToken() throws {
        let requestURL = try #require(Bundle.module.url(forResource: "bad-token", withExtension: "json", subdirectory: "Fixtures/RecordedAnswers/requests"))
        let headersURL = try #require(Bundle.module.url(forResource: "bad-token", withExtension: "headers", subdirectory: "Fixtures/RecordedAnswers/queue-off"))
        let bodyURL = try #require(Bundle.module.url(forResource: "bad-token", withExtension: "body", subdirectory: "Fixtures/RecordedAnswers/queue-off"))
        let sent = try JSONDecoder().decode(Request.self, from: Data(contentsOf: requestURL))
        let statusLine = String(decoding: try Data(contentsOf: headersURL), as: UTF8.self).prefix { $0 != "\r" }
        let code = try #require(statusLine.split(separator: " ").dropFirst().first.flatMap { Int($0) })
        let request = EncodedRequest(body: EncodedBatch(body: try Data(contentsOf: requestURL), contentType: "application/json"), recordIDs: sent.requests.map { _ in UUID() })
        let response = HTTPTransportResponse(head: HTTPResponse(status: HTTPResponse.Status(code: code)), body: try Data(contentsOf: bodyURL))
        let expected = ResponseOutcome.delivered

        let actual = MatomoBatchEncoder.outcome(of: response, for: request)

        #expect(actual == expected)
    }

    @Test("With QueuedTracking off and record_statistics 0, Matomo's answer to three valid tracking requests, none tracked and none invalid, is transient")
    func queueOffStatisticsOff() throws {
        let requestURL = try #require(Bundle.module.url(forResource: "valid", withExtension: "json", subdirectory: "Fixtures/RecordedAnswers/requests"))
        let headersURL = try #require(Bundle.module.url(forResource: "valid", withExtension: "headers", subdirectory: "Fixtures/RecordedAnswers/queue-off-record-statistics-0"))
        let bodyURL = try #require(Bundle.module.url(forResource: "valid", withExtension: "body", subdirectory: "Fixtures/RecordedAnswers/queue-off-record-statistics-0"))
        let sent = try JSONDecoder().decode(Request.self, from: Data(contentsOf: requestURL))
        let statusLine = String(decoding: try Data(contentsOf: headersURL), as: UTF8.self).prefix { $0 != "\r" }
        let code = try #require(statusLine.split(separator: " ").dropFirst().first.flatMap { Int($0) })
        let request = EncodedRequest(body: EncodedBatch(body: try Data(contentsOf: requestURL), contentType: "application/json"), recordIDs: sent.requests.map { _ in UUID() })
        let response = HTTPTransportResponse(head: HTTPResponse(status: HTTPResponse.Status(code: code)), body: try Data(contentsOf: bodyURL))
        let expected = ResponseOutcome.transient(reason: "Matomo counted 0 tracked and 0 invalid of the request's 3 tracking requests, and skipped the rest")

        let actual = MatomoBatchEncoder.outcome(of: response, for: request)

        #expect(actual == expected)
    }

    @Test("With QueuedTracking off, Matomo's 400 to a body whose requests isn't an array is dropped once and reported with the request's records")
    func queueOffMalformed() async throws {
        let headersURL = try #require(Bundle.module.url(forResource: "malformed", withExtension: "headers", subdirectory: "Fixtures/RecordedAnswers/queue-off"))
        let bodyURL = try #require(Bundle.module.url(forResource: "malformed", withExtension: "body", subdirectory: "Fixtures/RecordedAnswers/queue-off"))
        let statusLine = String(decoding: try Data(contentsOf: headersURL), as: UTF8.self).prefix { $0 != "\r" }
        let code = try #require(statusLine.split(separator: " ").dropFirst().first.flatMap { Int($0) })
        let status = HTTPResponse.Status(code: code)
        let url = try #require(URL(string: "https://analytics.example.com"))
        let transport = ScriptedTransport([.response(status, body: try Data(contentsOf: bodyURL))])
        let sut = try HTTPDestination.matomo(url: url, siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [AppOpened.schema]), transport: transport, now: { Date(timeIntervalSince1970: 1_795_868_273) })
        let batch = [EventRecord(event: AppOpened(), timestamp: Date(timeIntervalSince1970: 1_795_868_243), sourceLocation: nil)]
        let expected = HTTPDropReport<MatomoEncodingError>.rejected(status: .badRequest, recordIDs: batch.map(\.id))
        let expectedRequestCount = 1

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.requests.count == expectedRequestCount)
    }

    @Test("With bulk_requests_require_authentication on, Matomo's 401 to a request without a token is dropped once and reported with the request's records")
    func queueOffAuthenticationRequired() async throws {
        let headersURL = try #require(Bundle.module.url(forResource: "valid", withExtension: "headers", subdirectory: "Fixtures/RecordedAnswers/queue-off-require-authentication"))
        let bodyURL = try #require(Bundle.module.url(forResource: "valid", withExtension: "body", subdirectory: "Fixtures/RecordedAnswers/queue-off-require-authentication"))
        let statusLine = String(decoding: try Data(contentsOf: headersURL), as: UTF8.self).prefix { $0 != "\r" }
        let code = try #require(statusLine.split(separator: " ").dropFirst().first.flatMap { Int($0) })
        let status = HTTPResponse.Status(code: code)
        let url = try #require(URL(string: "https://analytics.example.com"))
        let transport = ScriptedTransport([.response(status, body: try Data(contentsOf: bodyURL))])
        let sut = try HTTPDestination.matomo(url: url, siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [AppOpened.schema]), transport: transport, now: { Date(timeIntervalSince1970: 1_795_868_273) })
        let batch = [EventRecord(event: AppOpened(), timestamp: Date(timeIntervalSince1970: 1_795_868_243), sourceLocation: nil)]
        let expected = HTTPDropReport<MatomoEncodingError>.rejected(status: .unauthorized, recordIDs: batch.map(\.id))
        let expectedRequestCount = 1

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.requests.count == expectedRequestCount)
    }

    // QueuedTracking on, MySQL backend: Matomo answers every bulk request it queues with a 1x1
    // GIF, before any is checked, so the answer says nothing of what will be stored.

    @Test("With QueuedTracking on, Matomo's GIF answer to three valid tracking requests, which it queues, is delivered")
    func queueOnValid() throws {
        let requestURL = try #require(Bundle.module.url(forResource: "valid", withExtension: "json", subdirectory: "Fixtures/RecordedAnswers/requests"))
        let headersURL = try #require(Bundle.module.url(forResource: "valid", withExtension: "headers", subdirectory: "Fixtures/RecordedAnswers/queue-on"))
        let bodyURL = try #require(Bundle.module.url(forResource: "valid", withExtension: "body", subdirectory: "Fixtures/RecordedAnswers/queue-on"))
        let sent = try JSONDecoder().decode(Request.self, from: Data(contentsOf: requestURL))
        let statusLine = String(decoding: try Data(contentsOf: headersURL), as: UTF8.self).prefix { $0 != "\r" }
        let code = try #require(statusLine.split(separator: " ").dropFirst().first.flatMap { Int($0) })
        let request = EncodedRequest(body: EncodedBatch(body: try Data(contentsOf: requestURL), contentType: "application/json"), recordIDs: sent.requests.map { _ in UUID() })
        let response = HTTPTransportResponse(head: HTTPResponse(status: HTTPResponse.Status(code: code)), body: try Data(contentsOf: bodyURL))
        let expected = ResponseOutcome.delivered

        let actual = MatomoBatchEncoder.outcome(of: response, for: request)

        #expect(actual == expected)
    }

    @Test("With QueuedTracking on, Matomo's GIF answer to three tracking requests for a site ID of no site, which its queue later drops unreported, is delivered")
    func queueOnUnknownSite() throws {
        let requestURL = try #require(Bundle.module.url(forResource: "unknown-site", withExtension: "json", subdirectory: "Fixtures/RecordedAnswers/requests"))
        let headersURL = try #require(Bundle.module.url(forResource: "unknown-site", withExtension: "headers", subdirectory: "Fixtures/RecordedAnswers/queue-on"))
        let bodyURL = try #require(Bundle.module.url(forResource: "unknown-site", withExtension: "body", subdirectory: "Fixtures/RecordedAnswers/queue-on"))
        let sent = try JSONDecoder().decode(Request.self, from: Data(contentsOf: requestURL))
        let statusLine = String(decoding: try Data(contentsOf: headersURL), as: UTF8.self).prefix { $0 != "\r" }
        let code = try #require(statusLine.split(separator: " ").dropFirst().first.flatMap { Int($0) })
        let request = EncodedRequest(body: EncodedBatch(body: try Data(contentsOf: requestURL), contentType: "application/json"), recordIDs: sent.requests.map { _ in UUID() })
        let response = HTTPTransportResponse(head: HTTPResponse(status: HTTPResponse.Status(code: code)), body: try Data(contentsOf: bodyURL))
        let expected = ResponseOutcome.delivered

        let actual = MatomoBatchEncoder.outcome(of: response, for: request)

        #expect(actual == expected)
    }

    @Test("With QueuedTracking on, Matomo's GIF answer to a tracking request for site 1 and one for a site ID of no site is delivered")
    func queueOnMixedSites() throws {
        let requestURL = try #require(Bundle.module.url(forResource: "mixed-sites", withExtension: "json", subdirectory: "Fixtures/RecordedAnswers/requests"))
        let headersURL = try #require(Bundle.module.url(forResource: "mixed-sites", withExtension: "headers", subdirectory: "Fixtures/RecordedAnswers/queue-on"))
        let bodyURL = try #require(Bundle.module.url(forResource: "mixed-sites", withExtension: "body", subdirectory: "Fixtures/RecordedAnswers/queue-on"))
        let sent = try JSONDecoder().decode(Request.self, from: Data(contentsOf: requestURL))
        let statusLine = String(decoding: try Data(contentsOf: headersURL), as: UTF8.self).prefix { $0 != "\r" }
        let code = try #require(statusLine.split(separator: " ").dropFirst().first.flatMap { Int($0) })
        let request = EncodedRequest(body: EncodedBatch(body: try Data(contentsOf: requestURL), contentType: "application/json"), recordIDs: sent.requests.map { _ in UUID() })
        let response = HTTPTransportResponse(head: HTTPResponse(status: HTTPResponse.Status(code: code)), body: try Data(contentsOf: bodyURL))
        let expected = ResponseOutcome.delivered

        let actual = MatomoBatchEncoder.outcome(of: response, for: request)

        #expect(actual == expected)
    }

    @Test("With QueuedTracking on, Matomo's GIF answer to a tracking request whose cdt is two days old, which its queue later drops unreported, is delivered")
    func queueOnStaleTimestamp() throws {
        let requestURL = try #require(Bundle.module.url(forResource: "stale-timestamp", withExtension: "json", subdirectory: "Fixtures/RecordedAnswers/requests"))
        let headersURL = try #require(Bundle.module.url(forResource: "stale-timestamp", withExtension: "headers", subdirectory: "Fixtures/RecordedAnswers/queue-on"))
        let bodyURL = try #require(Bundle.module.url(forResource: "stale-timestamp", withExtension: "body", subdirectory: "Fixtures/RecordedAnswers/queue-on"))
        let sent = try JSONDecoder().decode(Request.self, from: Data(contentsOf: requestURL))
        let statusLine = String(decoding: try Data(contentsOf: headersURL), as: UTF8.self).prefix { $0 != "\r" }
        let code = try #require(statusLine.split(separator: " ").dropFirst().first.flatMap { Int($0) })
        let request = EncodedRequest(body: EncodedBatch(body: try Data(contentsOf: requestURL), contentType: "application/json"), recordIDs: sent.requests.map { _ in UUID() })
        let response = HTTPTransportResponse(head: HTTPResponse(status: HTTPResponse.Status(code: code)), body: try Data(contentsOf: bodyURL))
        let expected = ResponseOutcome.delivered

        let actual = MatomoBatchEncoder.outcome(of: response, for: request)

        #expect(actual == expected)
    }

    @Test("With QueuedTracking on, Matomo's GIF answer to three valid tracking requests sent with a token_auth of no user is delivered")
    func queueOnBadToken() throws {
        let requestURL = try #require(Bundle.module.url(forResource: "bad-token", withExtension: "json", subdirectory: "Fixtures/RecordedAnswers/requests"))
        let headersURL = try #require(Bundle.module.url(forResource: "bad-token", withExtension: "headers", subdirectory: "Fixtures/RecordedAnswers/queue-on"))
        let bodyURL = try #require(Bundle.module.url(forResource: "bad-token", withExtension: "body", subdirectory: "Fixtures/RecordedAnswers/queue-on"))
        let sent = try JSONDecoder().decode(Request.self, from: Data(contentsOf: requestURL))
        let statusLine = String(decoding: try Data(contentsOf: headersURL), as: UTF8.self).prefix { $0 != "\r" }
        let code = try #require(statusLine.split(separator: " ").dropFirst().first.flatMap { Int($0) })
        let request = EncodedRequest(body: EncodedBatch(body: try Data(contentsOf: requestURL), contentType: "application/json"), recordIDs: sent.requests.map { _ in UUID() })
        let response = HTTPTransportResponse(head: HTTPResponse(status: HTTPResponse.Status(code: code)), body: try Data(contentsOf: bodyURL))
        let expected = ResponseOutcome.delivered

        let actual = MatomoBatchEncoder.outcome(of: response, for: request)

        #expect(actual == expected)
    }

    @Test("With QueuedTracking on, Matomo's 400 to a body whose requests isn't an array, a GIF, is dropped once and reported with the request's records")
    func queueOnMalformed() async throws {
        let headersURL = try #require(Bundle.module.url(forResource: "malformed", withExtension: "headers", subdirectory: "Fixtures/RecordedAnswers/queue-on"))
        let bodyURL = try #require(Bundle.module.url(forResource: "malformed", withExtension: "body", subdirectory: "Fixtures/RecordedAnswers/queue-on"))
        let statusLine = String(decoding: try Data(contentsOf: headersURL), as: UTF8.self).prefix { $0 != "\r" }
        let code = try #require(statusLine.split(separator: " ").dropFirst().first.flatMap { Int($0) })
        let status = HTTPResponse.Status(code: code)
        let url = try #require(URL(string: "https://analytics.example.com"))
        let transport = ScriptedTransport([.response(status, body: try Data(contentsOf: bodyURL))])
        let sut = try HTTPDestination.matomo(url: url, siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [AppOpened.schema]), transport: transport, now: { Date(timeIntervalSince1970: 1_795_868_273) })
        let batch = [EventRecord(event: AppOpened(), timestamp: Date(timeIntervalSince1970: 1_795_868_243), sourceLocation: nil)]
        let expected = HTTPDropReport<MatomoEncodingError>.rejected(status: .badRequest, recordIDs: batch.map(\.id))
        let expectedRequestCount = 1

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.requests.count == expectedRequestCount)
    }

    // QueuedTracking on, processing its queue during the tracking request (1 request to process):
    // the GIF is sent before the queue is processed.

    @Test("With QueuedTracking processing during the request, Matomo's GIF answer to three valid tracking requests, which it then stores, is delivered")
    func queueProcessingValid() throws {
        let requestURL = try #require(Bundle.module.url(forResource: "valid", withExtension: "json", subdirectory: "Fixtures/RecordedAnswers/requests"))
        let headersURL = try #require(Bundle.module.url(forResource: "valid", withExtension: "headers", subdirectory: "Fixtures/RecordedAnswers/queue-on-processing"))
        let bodyURL = try #require(Bundle.module.url(forResource: "valid", withExtension: "body", subdirectory: "Fixtures/RecordedAnswers/queue-on-processing"))
        let sent = try JSONDecoder().decode(Request.self, from: Data(contentsOf: requestURL))
        let statusLine = String(decoding: try Data(contentsOf: headersURL), as: UTF8.self).prefix { $0 != "\r" }
        let code = try #require(statusLine.split(separator: " ").dropFirst().first.flatMap { Int($0) })
        let request = EncodedRequest(body: EncodedBatch(body: try Data(contentsOf: requestURL), contentType: "application/json"), recordIDs: sent.requests.map { _ in UUID() })
        let response = HTTPTransportResponse(head: HTTPResponse(status: HTTPResponse.Status(code: code)), body: try Data(contentsOf: bodyURL))
        let expected = ResponseOutcome.delivered

        let actual = MatomoBatchEncoder.outcome(of: response, for: request)

        #expect(actual == expected)
    }

    @Test("With QueuedTracking processing during the request, Matomo's GIF answer to three tracking requests for a site ID of no site, which it then drops unreported, is delivered")
    func queueProcessingUnknownSite() throws {
        let requestURL = try #require(Bundle.module.url(forResource: "unknown-site", withExtension: "json", subdirectory: "Fixtures/RecordedAnswers/requests"))
        let headersURL = try #require(Bundle.module.url(forResource: "unknown-site", withExtension: "headers", subdirectory: "Fixtures/RecordedAnswers/queue-on-processing"))
        let bodyURL = try #require(Bundle.module.url(forResource: "unknown-site", withExtension: "body", subdirectory: "Fixtures/RecordedAnswers/queue-on-processing"))
        let sent = try JSONDecoder().decode(Request.self, from: Data(contentsOf: requestURL))
        let statusLine = String(decoding: try Data(contentsOf: headersURL), as: UTF8.self).prefix { $0 != "\r" }
        let code = try #require(statusLine.split(separator: " ").dropFirst().first.flatMap { Int($0) })
        let request = EncodedRequest(body: EncodedBatch(body: try Data(contentsOf: requestURL), contentType: "application/json"), recordIDs: sent.requests.map { _ in UUID() })
        let response = HTTPTransportResponse(head: HTTPResponse(status: HTTPResponse.Status(code: code)), body: try Data(contentsOf: bodyURL))
        let expected = ResponseOutcome.delivered

        let actual = MatomoBatchEncoder.outcome(of: response, for: request)

        #expect(actual == expected)
    }

    /// A recorded request's body: its tracking requests, and any other member ignored.
    struct Request: Decodable {
        var requests: [String]
    }
}
