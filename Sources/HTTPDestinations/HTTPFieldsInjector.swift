import HTTPTypes
import Instrumentation

/// Writes the values an instrument injects into a request's header fields, one field per key.
///
/// A value replaces any field already of its key's name, configured ones included: the batch's
/// trace context is more specific than a header every request carries. A key that isn't a valid
/// field name can't travel in a header, so it is left out.
struct HTTPFieldsInjector: Injector {
    func inject(_ value: String, forKey key: String, into fields: inout HTTPFields) {
        guard let name = HTTPField.Name(key) else {
            return
        }
        fields[name] = value
    }
}
