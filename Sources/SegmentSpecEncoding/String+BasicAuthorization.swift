import Foundation

extension String {
    /// The `Authorization` field of this write key, as Segment and RudderStack read it: HTTP Basic
    /// authentication with the key as the user name and an empty password,
    /// `Basic base64("<key>:")`.
    var basicAuthorization: String {
        "Basic " + Data((self + ":").utf8).base64EncodedString()
    }
}
