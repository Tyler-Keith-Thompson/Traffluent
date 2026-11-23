#if canImport(UIKit) && !os(watchOS)
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// A gesture recognizer that reports each touch in its view as it begins, with the control it
/// begins on, and as it ends, and never recognizes.
///
/// UIKit gives a touch to the recognizers of the views it is in before the view it began in, so
/// a control is reported before it sees the touch. The recognizer neither delays nor cancels a
/// touch to its view, and fails once all of its touches end.
// It stays possible while its touches last, rather than failing at once, to learn when each is
// over, which a recognizer that has failed doesn't. A recognizer that never recognizes prevents no
// other, and none waits on it unless the app asks.
final class ControlTouchRecognizer: UIGestureRecognizer {
    private let touchBegan: @MainActor (UITouch, UIControl?) -> Void
    private let touchesEnded: @MainActor ([ObjectIdentifier]) -> Void
    /// The touches seen to begin and not yet reported over.
    private var touches: [ObjectIdentifier] = []

    /// A recognizer that passes `touchBegan` each touch as it begins, and `touchesEnded` the
    /// touches that are over.
    ///
    /// - Parameters:
    ///   - touchBegan: Given each touch as it begins, and the nearest control at or above the view
    ///     it begins in, or `nil` outside any control.
    ///   - touchesEnded: Given the identities of touches that ended or were cancelled, or that
    ///     the recognizer stopped seeing as it reset.
    init(touchBegan: @escaping @MainActor (UITouch, UIControl?) -> Void, touchesEnded: @escaping @MainActor ([ObjectIdentifier]) -> Void) {
        self.touchBegan = touchBegan
        self.touchesEnded = touchesEnded
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        for touch in touches {
            self.touches.append(ObjectIdentifier(touch))
            touchBegan(touch, touch.view?.enclosingControl)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        end(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        end(touches)
    }

    override func reset() {
        super.reset()
        // Another recognizer that took the touches over (a scroll view's pan) fails this one,
        // which then sees no more of them.
        if !touches.isEmpty {
            touchesEnded(touches)
            touches = []
        }
    }

    /// Reports `ended` over, and fails once no touch is left.
    private func end(_ ended: Set<UITouch>) {
        let identities = ended.map(ObjectIdentifier.init)
        touches.removeAll { identities.contains($0) }
        touchesEnded(identities)
        if touches.isEmpty {
            state = .failed
        }
    }
}

extension UIView {
    /// The nearest control at or above this view.
    fileprivate var enclosingControl: UIControl? {
        sequence(first: self, next: \.superview).lazy.compactMap { $0 as? UIControl }.first
    }
}
#endif
