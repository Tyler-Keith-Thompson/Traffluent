public import Destinations
public import Events
public import Foundation
public import HTTPTypes
import Logging

/// A destination that sends each batch it receives to an HTTP endpoint, as one request.
///
/// The wire shape, for a server that ingests these batches:
///
/// - One request per batch, in the order the delivery hands them over, the next sent only once
///   the previous one has a response or has failed.
/// - The method is `POST` and the URL is the configured endpoint.
/// - The header fields are the configured ones, with `Content-Type` set to the encoder's
///   ``EncodedBatch/contentType`` (it replaces a configured `Content-Type`).
/// - The body is exactly the encoder's ``EncodedBatch/body`` for the batch's records, oldest
///   first. The format is the encoder's; events need no `Codable` conformance.
/// - A response with a 2xx status means the batch arrived. Any other status, or no response,
///   means it didn't; either way the batch is not sent again.
///
/// ``receive(_:)`` handles its own failures: a batch the encoder can't encode, a send that gets
/// no response and a response that isn't 2xx are each logged at error level and dropped, so
/// the delivery and its other destinations carry on. A cancelled delivery cancels the send in
/// flight, and ``receive(_:)`` returns without logging it.
///
/// ```swift
/// let collector = HTTPDestination(
///     endpoint: collectorURL,
///     headerFields: [.authorization: "Bearer \(token)"],
///     encoder: PlansEncoder())
/// let delivery = tracker.records.batch().deliver(to: collector)
/// ```
public struct HTTPDestination<Transport: HTTPTransport, Encoding: BatchEncoder>: Destination {
    private let request: HTTPRequest
    private let transport: Transport
    private let encoder: Encoding

    /// A destination that sends batches to `endpoint` through `transport`, encoded by `encoder`.
    ///
    /// - Parameters:
    ///   - endpoint: The URL each batch is posted to.
    ///   - headerFields: The header fields every request carries (an `Authorization`, say); none
    ///     by default. The encoder's content type replaces a `Content-Type` among them.
    ///   - transport: What sends each request.
    ///   - encoder: What turns each batch into a request body.
    public init(endpoint: URL, headerFields: HTTPFields = [:], transport: Transport, encoder: Encoding) {
        request = HTTPRequest(method: .post, url: endpoint, headerFields: headerFields)
        self.transport = transport
        self.encoder = encoder
    }

    /// Sends `batch` to the endpoint as one request, and logs a failure.
    ///
    /// - Parameter batch: The records to send.
    public func receive(_ batch: [EventRecord]) async {
        await send(batch).log()
    }

    /// Encodes `batch`, sends it, and says what became of it.
    package func send(_ batch: [EventRecord]) async -> Outcome {
        let encoded: EncodedBatch
        do {
            encoded = try encoder.encode(batch)
        } catch {
            return .notEncoded(error)
        }
        var request = request
        request.headerFields[.contentType] = encoded.contentType
        do {
            let response = try await transport.send(request, body: encoded.body)
            return response.status.kind == .successful ? .delivered(response) : .rejected(response)
        } catch {
            return .notSent(error)
        }
    }

    /// What became of one batch.
    package enum Outcome {
        /// The server answered with a 2xx status.
        case delivered(HTTPResponse)
        /// The server answered with another status.
        case rejected(HTTPResponse)
        /// The encoder threw, so nothing was sent.
        case notEncoded(Encoding.Failure)
        /// The transport got no response.
        case notSent(HTTPTransportError)
    }
}

// At file scope because a generic type can't hold a static stored property; one logger for every
// specialization of HTTPDestination.
private let logger = Logger(label: "HTTPDestinations.HTTPDestination")

extension HTTPDestination.Outcome {
    /// Logs a batch that didn't arrive; a delivered or cancelled one isn't logged.
    fileprivate func log() {
        switch self {
        case .delivered, .notSent(.cancelled):
            break
        case .rejected(let response):
            logger.error("Dropped a batch the endpoint answered with \(response.status)")
        case .notEncoded(let error):
            logger.error("Dropped a batch the encoder couldn't encode: \(error)")
        case .notSent(.failed(let reason)):
            logger.error("Dropped a batch that got no response: \(reason)")
        }
    }
}
