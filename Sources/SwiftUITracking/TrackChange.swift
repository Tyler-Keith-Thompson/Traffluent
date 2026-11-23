#if canImport(SwiftUI)
public import Events
public import SwiftUI
import Trackers

extension View {
    /// Tracks the event `event` makes from `value`'s new value each time `value` changes.
    ///
    /// ```swift
    /// Picker("Plan", selection: $plan) { … }
    ///     .trackChange(of: plan) { PlanSelected(plan: $0) }
    /// ```
    ///
    /// It tracks once per change, as `onChange(of:initial:_:)` runs: not for the value the view
    /// first appears with, and not when SwiftUI redraws the view with an equal value. The record's
    /// call site is where the modifier is applied.
    ///
    /// - Parameters:
    ///   - value: The value whose changes are tracked.
    ///   - event: Makes the event to track from the new value. It runs on the main actor as the
    ///     change is seen, so it should only build the event.
    ///   - file: The caller's file; leave it to its default.
    ///   - fileID: The caller's module and file name; leave it to its default.
    ///   - function: The caller's enclosing declaration; leave it to its default.
    ///   - line: The caller's line; leave it to its default.
    ///   - column: The caller's column; leave it to its default.
    /// - Returns: The view, tracking an event each time `value` changes.
    public func trackChange<Value: Equatable, Tracked: Event>(
        of value: Value,
        _ event: @escaping (Value) -> Tracked,
        file: String = #file,
        fileID: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) -> some View {
        modifier(TrackChange(value: value, event: event, callSite: CallSite(file: file, fileID: fileID, function: function, line: line, column: column)))
    }
}

/// Tracks an event made from its value each time the value changes.
struct TrackChange<Value: Equatable, Tracked: Event>: ViewModifier {
    let value: Value
    let event: (Value) -> Tracked
    let callSite: CallSite
    @Environment(\.tracker) private var tracker

    func body(content: Content) -> some View {
        content.onChange(of: value, initial: false) { [tracker, event, callSite] _, newValue in
            tracker.track(event(newValue), from: callSite)
        }
    }
}
#endif
