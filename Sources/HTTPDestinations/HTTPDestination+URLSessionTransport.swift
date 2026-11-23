// Left out on WASI with URLSessionTransport itself.
#if !os(WASI)
    public import Foundation
    public import HTTPTypes

    extension HTTPDestination where Transport == URLSessionTransport {
        /// A destination that sends batches to `endpoint` with `URLSession.shared`, encoded by
        /// `encoder`; not available on WASI.
        ///
        /// - Parameters:
        ///   - endpoint: The URL each batch is posted to.
        ///   - headerFields: The header fields every request carries (an `Authorization`, say);
        ///     none by default. The encoder's content type replaces a `Content-Type` among them.
        ///   - encoder: What turns each batch into a request body.
        public init(endpoint: URL, headerFields: HTTPFields = [:], encoder: Encoding) {
            self.init(endpoint: endpoint, headerFields: headerFields, transport: URLSessionTransport(), encoder: encoder)
        }
    }
#endif
