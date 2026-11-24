// Linux only: FoundationNetworking's URLSession.
#if canImport(FoundationNetworking)
    import Foundation
    import FoundationNetworking
    import HTTPTypes
    import HTTPTypesFoundation
    import Synchronization

    extension URLSession {
        /// Uploads `body` with `request` and returns the response, and never cancels the upload.
        ///
        /// FoundationNetworking traps ("Trying to access a behaviour for a task that in not in the
        /// registry", TaskRegistry.swift) when a `URLSessionTask` is cancelled while it fails:
        /// `cancel()` hops twice onto the session's work queue before it fails the task, and a
        /// failure in between (a refused connection) has already removed the task from the
        /// registry. Its async `upload(for:from:)` cancels the task when the calling task is
        /// cancelled, so a cancelled send could crash the process. Here a cancelled caller gets
        /// `CancellationError` at once instead, and the abandoned upload ends on its own, with a
        /// response, a failure or the request's timeout.
        ///
        /// - Throws: `CancellationError` when the calling task is cancelled before a response
        ///   arrives, the session's error when none arrives, `URLError(.unsupportedURL)` for a
        ///   request `URLRequest` can't hold, or `URLError(.badServerResponse)` for a response that
        ///   isn't HTTP.
        func uploadWithoutCancelling(for request: HTTPRequest, from body: Data) async throws -> HTTPResponse {
            guard let urlRequest = URLRequest(httpRequest: request) else {
                throw URLError(.unsupportedURL)
            }
            let upload = Upload()
            let urlResponse = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URLResponse, any Error>) in
                    guard upload.wait(continuation) else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    let task = uploadTask(with: urlRequest, from: body) { _, response, error in
                        upload.finish(response.map(Result.success) ?? .failure(error ?? URLError(.badServerResponse)))
                    }
                    task.resume()
                }
            } onCancel: {
                upload.cancel()
            }
            guard let response = (urlResponse as? HTTPURLResponse)?.httpResponse else {
                throw URLError(.badServerResponse)
            }
            return response
        }
    }

    /// Who resumes an upload's continuation: its completion handler or its caller's cancellation,
    /// whichever comes first.
    ///
    /// A class around a `Mutex` because both escaping closures share it; a `Mutex`, not an actor,
    /// because the cancellation handler and the completion handler are synchronous.
    private final class Upload: Sendable {
        private enum State {
            case starting
            case waiting(CheckedContinuation<URLResponse, any Error>)
            case cancelled
            case finished
        }

        private let state = Mutex(State.starting)

        /// Stores `continuation` for `finish` or `cancel` to resume; `false` when the caller was
        /// already cancelled, so the upload mustn't start.
        func wait(_ continuation: CheckedContinuation<URLResponse, any Error>) -> Bool {
            state.withLock { state in
                guard case .starting = state else {
                    return false
                }
                state = .waiting(continuation)
                return true
            }
        }

        /// Resumes the continuation with the upload's outcome, unless the caller was cancelled.
        func finish(_ result: Result<URLResponse, any Error>) {
            take(becoming: .finished)?.resume(with: result)
        }

        /// Resumes the continuation with `CancellationError`, unless the upload finished.
        func cancel() {
            take(becoming: .cancelled)?.resume(throwing: CancellationError())
        }

        private func take(becoming next: State) -> CheckedContinuation<URLResponse, any Error>? {
            state.withLock { state in
                switch state {
                case .starting:
                    state = next
                    return nil
                case .waiting(let continuation):
                    state = next
                    return continuation
                case .cancelled, .finished:
                    return nil
                }
            }
        }
    }
#endif
