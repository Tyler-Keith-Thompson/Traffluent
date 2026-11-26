import AutomaticControlTracking
import Events
import LifecycleTracking
import Sessions
import StoreEvents
import SwiftUITracking
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

    private static let librarySchemas = [
        ScreenViewed.schema,
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
