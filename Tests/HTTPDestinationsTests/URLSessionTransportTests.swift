import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import HTTPDestinations
import HTTPTypes
import Testing

@Suite("URLSessionTransport", .timeLimit(.minutes(1)))
struct URLSessionTransportTests {
    /// Answers every request with 200 and `{"status":0}`, without reaching the network.
    final class AnsweringProtocol: URLProtocol {
        static let body = Data(#"{"status":0}"#.utf8)

        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    @Test("A response comes back with its status and its body")
    func responseBody() async throws {
        let url = try #require(URL(string: "https://collector.example.com/batches"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnsweringProtocol.self]
        let sut = URLSessionTransport(session: URLSession(configuration: configuration))
        let expectedStatus = HTTPResponse.Status.ok
        let expectedBody = AnsweringProtocol.body

        let actual = try await sut.send(HTTPRequest(method: .post, url: url), body: Data("a".utf8))

        #expect(actual.head.status == expectedStatus)
        #expect(actual.body == expectedBody)
    }

    /// Answers every request with 204 No Content and loads no data, without reaching the network.
    final class NoContentProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 204, httpVersion: "HTTP/1.1", headerFields: [:]) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    /// Answers every request with 200 and a body of no bytes, without reaching the network.
    final class EmptyOKProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "0"]) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    @Test("A 204 that loads no data comes back with its status and an empty body")
    func noContentBody() async throws {
        let url = try #require(URL(string: "https://collector.example.com/batches"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NoContentProtocol.self]
        let sut = URLSessionTransport(session: URLSession(configuration: configuration))
        let expectedStatus = HTTPResponse.Status.noContent
        let expectedBody = Data()

        let actual = try await sut.send(HTTPRequest(method: .post, url: url), body: Data("a".utf8))

        #expect(actual.head.status == expectedStatus)
        #expect(actual.body == expectedBody)
    }

    @Test("A 200 with a body of no bytes comes back with its status and an empty body")
    func emptyOKBody() async throws {
        let url = try #require(URL(string: "https://collector.example.com/batches"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EmptyOKProtocol.self]
        let sut = URLSessionTransport(session: URLSession(configuration: configuration))
        let expectedStatus = HTTPResponse.Status.ok
        let expectedBody = Data()

        let actual = try await sut.send(HTTPRequest(method: .post, url: url), body: Data("a".utf8))

        #expect(actual.head.status == expectedStatus)
        #expect(actual.body == expectedBody)
    }

    @Test("A request no server answers throws failed")
    func noServer() async throws {
        // Port 1 on the loopback interface has no listener, so the connection is refused at
        // once, without reaching the network.
        let url = try #require(URL(string: "http://127.0.0.1:1/batches"))
        let sut = URLSessionTransport()

        let actual = await #expect(throws: HTTPTransportError.self) {
            try await sut.send(HTTPRequest(method: .post, url: url), body: Data("a".utf8))
        }

        guard case .failed = actual else {
            Issue.record("Expected failed, got \(String(describing: actual))")
            return
        }
    }

    @Test("A request of a scheme the session doesn't support throws invalidRequest, with the error's domain and code and not the URL")
    func unsupportedScheme() async throws {
        // URLSession reports unsupportedURL for a scheme it has no protocol for, on macOS and
        // Linux alike (ftp is -1 on macOS, a refused connection on Linux).
        let url = try #require(URL(string: "foo://127.0.0.1/batches?key=secret"))
        let sut = URLSessionTransport()
        let expected = HTTPTransportError.invalidRequest(reason: "\(NSURLErrorDomain) \(URLError.Code.unsupportedURL.rawValue)")

        let actual = await #expect(throws: HTTPTransportError.self) {
            try await sut.send(HTTPRequest(method: .post, url: url), body: Data("a".utf8))
        }

        #expect(actual == expected)
    }

    @Test("A failure's reason names the error's domain and code, and holds neither the endpoint's URL nor its key")
    func reasonWithoutURL() async throws {
        // Port 1 on the loopback interface has no listener, so the connection is refused at once.
        let url = try #require(URL(string: "http://127.0.0.1:1/v1?key=secret"))
        let sut = URLSessionTransport()
        let expectedDomain = NSURLErrorDomain

        let actual = await #expect(throws: HTTPTransportError.self) {
            try await sut.send(HTTPRequest(method: .post, url: url), body: Data("a".utf8))
        }

        guard case .failed(let reason) = actual else {
            Issue.record("Expected failed, got \(String(describing: actual))")
            return
        }
        #expect(reason.hasPrefix(expectedDomain))
        #expect(Int(reason.split(separator: " ").last ?? "") != nil)
        #expect(!reason.contains("127.0.0.1"))
        #expect(!reason.contains("secret"))
    }

    @Test("Sends cancelled at a spread of moments around a refused connection each throw cancelled or failed")
    func cancelRacingRefusal() async throws {
        // FoundationNetworking traps when a URLSessionTask is cancelled while a refused connection
        // fails it, so on Linux this crashed the process about one run in three before
        // URLSessionTransport stopped cancelling its uploads.
        let url = try #require(URL(string: "http://127.0.0.1:1/batches"))
        let sut = URLSessionTransport()
        let count = 300

        let actual = await withTaskGroup(of: HTTPTransportError?.self) { group in
            for index in 0..<count {
                group.addTask {
                    let sending = Task { () async -> HTTPTransportError? in
                        do throws(HTTPTransportError) {
                            _ = try await sut.send(HTTPRequest(method: .post, url: url), body: Data("a".utf8))
                            return nil
                        } catch {
                            return error
                        }
                    }
                    if !index.isMultiple(of: 3) {
                        await Task.yield()
                    }
                    if index % 3 == 2 {
                        try? await Task.sleep(for: .microseconds(index % 50 * 10))
                    }
                    sending.cancel()
                    return await sending.value
                }
            }
            var errors: [HTTPTransportError?] = []
            for await error in group {
                errors.append(error)
            }
            return errors
        }

        #expect(actual.count == count)
        #expect(actual.allSatisfy { error in
            switch error {
            case .cancelled?, .failed?: true
            case .invalidRequest?, nil: false
            }
        })
    }

    @Test("A send from a cancelled task throws cancelled")
    func cancelled() async throws {
        let url = try #require(URL(string: "http://127.0.0.1:1/batches"))
        let sut = URLSessionTransport()
        let expected = HTTPTransportError.cancelled
        let sending = Task { () async -> Result<HTTPTransportResponse, HTTPTransportError> in
            withUnsafeCurrentTask { $0?.cancel() }
            do throws(HTTPTransportError) {
                return .success(try await sut.send(HTTPRequest(method: .post, url: url), body: Data("a".utf8)))
            } catch {
                return .failure(error)
            }
        }

        let actual = await sending.value

        #expect(actual == .failure(expected))
    }
}
