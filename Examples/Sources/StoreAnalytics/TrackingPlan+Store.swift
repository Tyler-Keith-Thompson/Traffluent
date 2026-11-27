// Linked, not named: the plan finds these modules' events at run time, so each module that
// declares or tracks events the app sends stays a dependency of this one.
import AutomaticControlTracking
import LifecycleTracking
import Sessions
import StoreEvents
import SwiftUITracking
public import TrackingPlans

extension TrackingPlan {
    /// Every event the store app tracks: its own, and the ones the library tracks for it
    /// (screens, controls, sessions and the app's lifecycle), found in the modules the program
    /// links, so a new event needs no list.
    ///
    /// The collector's encoder reads each record through its event's schema here, and leaves out
    /// a record whose event the plan doesn't hold. `export-tracking-plan` writes this plan into
    /// `Examples/TrackingPlan` (`StoreTrackingPlan`, which links the same modules through this
    /// one), which is the document a collector validates against.
    ///
    /// - Throws: ``TrackingPlanError`` when two of the events share a name and version, or one is
    ///   malformed.
    public static var store: TrackingPlan {
        get throws(TrackingPlanError) { try TrackingPlan() }
    }
}
