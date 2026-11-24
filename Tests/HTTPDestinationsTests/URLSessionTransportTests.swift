import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import HTTPDestinations
import HTTPTypes
import Testing

@Suite("URLSessionTransport", .timeLimit(.minutes(1)))
struct URLSessionTransportTests {
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
            case nil: false
            }
        })
    }

    @Test("A send from a cancelled task throws cancelled")
    func cancelled() async throws {
        let url = try #require(URL(string: "http://127.0.0.1:1/batches"))
        let sut = URLSessionTransport()
        let expected = HTTPTransportError.cancelled
        let sending = Task { () async -> Result<HTTPResponse, HTTPTransportError> in
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
