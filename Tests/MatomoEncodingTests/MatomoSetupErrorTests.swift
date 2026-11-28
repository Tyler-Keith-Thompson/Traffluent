import EventMacros
import Events
import Foundation
import HTTPDestinations
import MatomoEncoding
import Testing
import TrackingPlans

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("HTTPDestination.matomo and MatomoBatchEncoder: setup errors")
private struct MatomoSetupErrorTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
        var seats: Int
    }

    @Event(name: "checkout_started")
    struct CheckoutStarted {
        var cartSize: Int
        var plan: String
    }

    static let urls: [(String, Bool)] = [
        ("http://analytics.example.com", true), ("ftp://analytics.example.com", true), ("https:///matomo", true), ("https://user@analytics.example.com", true),
        ("https://user:secret@analytics.example.com", true), ("https://:secret@analytics.example.com", true), ("https://analytics.example.com?idsite=1", true),
        ("https://analytics.example.com#top", true), ("https://analytics.example.com/matomo.php", true), ("https://analytics.example.com/piwik.php", true),
        ("https://analytics.example.com/MATOMO.PHP/", true), ("https://analytics.example.com/stats/index.php", true), ("https://analytics.example.com/.php", true),
        ("https://analytics.example.com", false), ("HTTPS://analytics.example.com", false), ("https://analytics.example.com/matomo", false),
        ("https://analytics.example.com/php", false), ("https://analytics.example.com/matomo.phps", false), ("https://analytics.example.com/matomo.php/stats", false),
    ]

    @Test("The factory throws invalidURL for a URL that isn't a plain https URL of the installation, and accepts one that is", arguments: Self.urls)
    func invalidURL(url: String, throwsError: Bool) throws {
        let plan = try TrackingPlan(schemas: [])
        let installation = try #require(URL(string: url))
        let expected: MatomoSetupError? = throwsError ? .invalidURL : nil

        let actual: MatomoSetupError?
        do {
            _ = try HTTPDestination.matomo(url: installation, siteID: 1, dimensions: [:], category: "Shop", plan: plan)
            actual = nil
        } catch {
            actual = error
        }

        #expect(actual == expected)
    }

    @Test("The factory and the encoder throw invalidSiteID for a site ID below 1, and accept 1 and above", arguments: [
        (Int.min, true), (-1, true), (0, true), (1, false), (2, false), (Int.max, false),
    ])
    func invalidSiteID(siteID: Int, throwsError: Bool) throws {
        let plan = try TrackingPlan(schemas: [])
        let url = try #require(URL(string: "https://analytics.example.com"))
        let expected: MatomoSetupError? = throwsError ? .invalidSiteID : nil

        let actualFactory: MatomoSetupError?
        do {
            _ = try HTTPDestination.matomo(url: url, siteID: siteID, dimensions: [:], category: "Shop", plan: plan)
            actualFactory = nil
        } catch {
            actualFactory = error
        }
        let actualEncoder: MatomoSetupError?
        do {
            _ = try MatomoBatchEncoder(siteID: siteID, dimensions: [:], category: "Shop", plan: plan)
            actualEncoder = nil
        } catch {
            actualEncoder = error
        }

        #expect(actualFactory == expected)
        #expect(actualEncoder == expected)
    }

    // Matomo removes line breaks and NULs, trims spaces, tabs, line breaks, NULs and vertical tabs,
    // and stores `&` as `&amp;` (5 characters), `<` and `>` as 4, `"` as `&quot;` and `'` as
    // `&#039;` (6), in at most 4,096 characters.
    static let categories: [(String, Bool)] = [
        ("", true), (" ", true), ("\n", true), ("\r\n", true), (" \t\r\n\0\u{0B} ", true), ("\0", true),
        (String(repeating: "a", count: 4097), true), (String(repeating: "&", count: 820), true), (String(repeating: "'", count: 683), true),
        (String(repeating: "é", count: 4097), true), (String(repeating: "<", count: 1025), true),
        ("a", false), (" a ", false), ("\na\n", false), ("Shop & Co", false), (String(repeating: "a", count: 4096), false),
        (" " + String(repeating: "a", count: 4096) + "\n", false), (String(repeating: "&", count: 819), false), (String(repeating: "'", count: 682), false),
        (String(repeating: "é", count: 4096), false), (String(repeating: "<", count: 1024), false), ("a" + String(repeating: "\n", count: 5000), false),
    ]

    @Test("The encoder throws invalidCategory for a category Matomo would empty or cut short, and accepts the last that fits", arguments: Self.categories)
    func invalidCategory(category: String, throwsError: Bool) throws {
        let plan = try TrackingPlan(schemas: [])
        let expected: MatomoSetupError? = throwsError ? .invalidCategory : nil

        let actual: MatomoSetupError?
        do {
            _ = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: category, plan: plan)
            actual = nil
        } catch {
            actual = error
        }

        #expect(actual == expected)
    }

    @Test("The encoder throws invalidDimension for a dimension ID below 1, and accepts 1 and above", arguments: [
        (Int.min, true), (-1, true), (0, true), (1, false), (2, false), (999, false), (1000, false), (Int.max, false),
    ])
    func invalidDimension(dimension: Int, throwsError: Bool) throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema])
        let expected: MatomoSetupError? = throwsError ? .invalidDimension(property: "plan", dimension: dimension) : nil

        let actual: MatomoSetupError?
        do {
            _ = try MatomoBatchEncoder(siteID: 1, dimensions: ["plan": dimension], category: "Shop", plan: plan)
            actual = nil
        } catch {
            actual = error
        }

        #expect(actual == expected)
    }

    @Test("The encoder throws duplicateProperty for a property a literal maps twice, to one dimension or two")
    func duplicateProperty() throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema])

        #expect(throws: MatomoSetupError.duplicateProperty("plan")) {
            try MatomoBatchEncoder(siteID: 1, dimensions: ["plan": 1, "seats": 2, "plan": 3], category: "Shop", plan: plan)
        }
        #expect(throws: MatomoSetupError.duplicateProperty("plan")) {
            try MatomoBatchEncoder(siteID: 1, dimensions: ["plan": 1, "plan": 1], category: "Shop", plan: plan)
        }
    }

    @Test("The encoder throws unknownProperty for a property no event of the plan has, naming the first in the mapping's order")
    func unknownProperty() throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema, CheckoutStarted.schema])

        #expect(throws: MatomoSetupError.unknownProperty("coupon")) {
            try MatomoBatchEncoder(siteID: 1, dimensions: ["plan": 1, "coupon": 2, "Seats": 3], category: "Shop", plan: plan)
        }
        #expect(throws: MatomoSetupError.unknownProperty("Seats")) {
            try MatomoBatchEncoder(siteID: 1, dimensions: ["Seats": 3], category: "Shop", plan: plan)
        }
        #expect(throws: MatomoSetupError.unknownProperty("plan")) {
            try MatomoBatchEncoder(siteID: 1, dimensions: ["plan": 1], category: "Shop", plan: try TrackingPlan(schemas: []))
        }
    }

    @Test("The encoder throws sharedDimension for two properties of one event mapped to one dimension, and accepts one shared by properties of two events")
    func sharedDimension() throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema, CheckoutStarted.schema])

        #expect(throws: MatomoSetupError.sharedDimension(event: "signed_up", version: 1, dimension: 2)) {
            try MatomoBatchEncoder(siteID: 1, dimensions: ["plan": 2, "seats": 2], category: "Shop", plan: plan)
        }
        #expect(throws: Never.self) {
            try MatomoBatchEncoder(siteID: 1, dimensions: ["seats": 2, "cartSize": 2], category: "Shop", plan: plan)
        }
    }

    // The type names as the macro writes them, and ones an app could write by hand. `Sensitive`
    // is the library's own (Events, or Traffluent through the umbrella), alone or optional or in
    // an array; another module's type of that name, or a type whose name holds it, isn't.
    static let sensitiveTypes: [(String, Bool)] = [
        ("Sensitive<String>", true), ("Sensitive<Int>?", true), ("Sensitive<String>!", true), ("[Sensitive<String>]", true), ("[Sensitive<String>]?", true),
        ("Events.Sensitive<String>", true), ("Traffluent.Sensitive<String>", true), ("Optional<Sensitive<String>>", true), ("Swift.Array<Sensitive<Bool>>", true),
        ("String", false), ("MySensitive<String>", false), ("Sensitive", false), ("Other.Sensitive<String>", false), ("[String: Sensitive<String>]", false), ("Box<Sensitive<String>>", false),
    ]

    @Test("The encoder throws sensitiveProperty for a mapped property whose type is Sensitive, optional or in an array, and accepts any other type", arguments: Self.sensitiveTypes)
    func sensitiveProperty(typeName: String, throwsError: Bool) throws {
        let schema = EventSchema(name: "signed_up", version: 3, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "plan", typeName: "String", isOptional: false),
            EventSchema.Property(name: "email", typeName: typeName, isOptional: false),
        ])
        let plan = try TrackingPlan(schemas: [schema])
        let expected: MatomoSetupError? = throwsError ? .sensitiveProperty(event: "signed_up", version: 3, property: "email") : nil

        let actual: MatomoSetupError?
        do {
            _ = try MatomoBatchEncoder(siteID: 1, dimensions: ["plan": 1, "email": 2], category: "Shop", plan: plan)
            actual = nil
        } catch {
            actual = error
        }

        #expect(actual == expected)
    }

    @Test("A Sensitive property left unmapped sets up, and one Sensitive in a single event is refused though another event's of that name isn't")
    func sensitivePropertyUnmapped() throws {
        let sensitive = EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: "email", typeName: "Sensitive<String>", isOptional: false)])
        let plain = EventSchema(name: "contacted", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: "email", typeName: "String", isOptional: false)])
        let plan = try TrackingPlan(schemas: [plain, sensitive])

        #expect(throws: Never.self) {
            try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: plan)
        }
        #expect(throws: MatomoSetupError.sensitiveProperty(event: "signed_up", version: 1, property: "email")) {
            try MatomoBatchEncoder(siteID: 1, dimensions: ["email": 1], category: "Shop", plan: plan)
        }
    }

    @Test("A dictionary of dimensions is checked in the order of its names, whatever order it iterates in")
    func dictionaryOrder() throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema])
        let dimensions = MatomoDimensions(["zeta": 1, "alpha": 2, "plan": 0])

        #expect(throws: MatomoSetupError.invalidDimension(property: "plan", dimension: 0)) {
            try MatomoBatchEncoder(siteID: 1, dimensions: dimensions, category: "Shop", plan: plan)
        }
        #expect(throws: MatomoSetupError.unknownProperty("alpha")) {
            try MatomoBatchEncoder(siteID: 1, dimensions: MatomoDimensions(["zeta": 1, "alpha": 2, "plan": 3]), category: "Shop", plan: plan)
        }
    }

    @Test("The factory checks the URL, then the site ID, the category and the dimensions, each dimension's ID before a duplicate, a duplicate before an unknown property, that before a Sensitive one, and that before a shared dimension")
    func order() throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema])
        let sensitivePlan = try TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "plan", typeName: "String", isOptional: false),
            EventSchema.Property(name: "seats", typeName: "Int", isOptional: false),
            EventSchema.Property(name: "email", typeName: "Sensitive<String>", isOptional: false),
        ])])
        let http = try #require(URL(string: "http://analytics.example.com"))
        let url = try #require(URL(string: "https://analytics.example.com"))

        #expect(throws: MatomoSetupError.invalidURL) {
            try HTTPDestination.matomo(url: http, siteID: 0, dimensions: ["plan": 0], category: "", plan: plan)
        }
        #expect(throws: MatomoSetupError.invalidSiteID) {
            try HTTPDestination.matomo(url: url, siteID: 0, dimensions: ["plan": 0], category: "", plan: plan)
        }
        #expect(throws: MatomoSetupError.invalidCategory) {
            try HTTPDestination.matomo(url: url, siteID: 1, dimensions: ["plan": 0], category: "", plan: plan)
        }
        #expect(throws: MatomoSetupError.invalidDimension(property: "coupon", dimension: 0)) {
            try HTTPDestination.matomo(url: url, siteID: 1, dimensions: ["plan": 1, "plan": 1, "coupon": 0], category: "Shop", plan: plan)
        }
        #expect(throws: MatomoSetupError.duplicateProperty("plan")) {
            try HTTPDestination.matomo(url: url, siteID: 1, dimensions: ["coupon": 1, "plan": 2, "plan": 2], category: "Shop", plan: plan)
        }
        #expect(throws: MatomoSetupError.unknownProperty("coupon")) {
            try HTTPDestination.matomo(url: url, siteID: 1, dimensions: ["plan": 2, "seats": 2, "email": 2, "coupon": 1], category: "Shop", plan: sensitivePlan)
        }
        #expect(throws: MatomoSetupError.sensitiveProperty(event: "signed_up", version: 1, property: "email")) {
            try HTTPDestination.matomo(url: url, siteID: 1, dimensions: ["plan": 2, "seats": 2, "email": 2], category: "Shop", plan: sensitivePlan)
        }
        #expect(throws: MatomoSetupError.sharedDimension(event: "signed_up", version: 1, dimension: 2)) {
            try HTTPDestination.matomo(url: url, siteID: 1, dimensions: ["plan": 2, "seats": 2], category: "Shop", plan: sensitivePlan)
        }
    }

    @Test("A plan holding an event whose name Matomo would empty still sets up: only its records are skipped")
    func planWithRefusedNames() throws {
        let blank = EventSchema(name: " ", version: 1, consentCategory: .analytics, properties: [])
        let long = EventSchema(name: String(repeating: "a", count: 4097), version: 1, consentCategory: .analytics, properties: [])
        let plan = try TrackingPlan(schemas: [blank, long, SignedUp.schema])

        #expect(throws: Never.self) {
            try MatomoBatchEncoder(siteID: 1, dimensions: ["plan": 1], category: "Shop", plan: plan)
        }
    }
}
