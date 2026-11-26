import AutomaticControlTracking
import Events
import LifecycleTracking
import Sessions
import StoreEvents
#if canImport(SwiftUI)
    import SwiftUITracking
#endif
public import TrackingPlans

extension TrackingPlan {
    /// Every event the store app tracks: its own, and the ones the library tracks for it
    /// (screens, controls, sessions and the app's lifecycle).
    ///
    /// The collector's encoder reads each record through its event's schema here, and leaves out
    /// a record whose event isn't listed, so a feature turned on in ``StoreAnalytics`` needs its
    /// events listed too. `export-tracking-plan` writes this plan into `Examples/TrackingPlan`
    /// (`StoreTrackingPlan`), which is the document a collector validates against.
    public static let store = TrackingPlan(schemas: storeSchemas + librarySchemas)

    private static let storeSchemas = [
        ProductAddedToCart.schema,
        PromotionTapped.schema,
        CheckoutStarted.schema,
        OrderCompleted.schema,
        SignedUp.schema,
    ]

    // ScreenViewed is declared in SwiftUITracking, which builds empty off Apple platforms, so a
    // Linux build's plan leaves it out; the plan is exported on a Mac.
    #if canImport(SwiftUI)
        private static let screenSchemas = [ScreenViewed.schema]
    #else
        private static let screenSchemas: [EventSchema] = []
    #endif

    private static let librarySchemas = screenSchemas + [
        ControlActivated.schema,
        SessionStarted.schema,
        SessionEnded.schema,
        ApplicationInstalled.schema,
        ApplicationUpdated.schema,
        ApplicationOpened.schema,
        ApplicationBackgrounded.schema,
        ApplicationTerminated.schema,
    ]
}
