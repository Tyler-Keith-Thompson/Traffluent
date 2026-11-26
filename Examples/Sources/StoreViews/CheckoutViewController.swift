#if canImport(UIKit) && !os(watchOS)
    import StoreModel
    import Trackers
    import UIKit
    import UIKitTracking

    /// The checkout in UIKit: the total, express shipping, and the button that places the order.
    ///
    /// It tracks nothing itself but the order. The window scene tracks its screen view as it
    /// appears, and each of its controls as a touch activates it, named after its accessibility
    /// identifier (`trackWindowSceneAutomatically(_:)`). The order is placed with the tracker its
    /// traits hold, which SwiftUI's environment sets, bound as `Tracker.current`, as the button is
    /// tapped.
    final class CheckoutViewController: UIViewController {
        private let totalInCents: Int
        private let placeOrder: @MainActor (_ expressShipping: Bool) -> Void
        private let expressShipping = UISwitch()
        private let placeOrderButton = UIButton(configuration: .borderedProminent())

        /// A checkout of a cart costing `totalInCents`, which calls `placeOrder` with the
        /// express shipping choice, with the tracker its traits hold bound as `Tracker.current`.
        init(totalInCents: Int, placeOrder: @escaping @MainActor (_ expressShipping: Bool) -> Void) {
            self.totalInCents = totalInCents
            self.placeOrder = placeOrder
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidLoad() {
            super.viewDidLoad()
            let total = UILabel()
            total.text = "Total: " + (Double(totalInCents) / 100).formatted(.currency(code: "USD"))
            let expressLabel = UILabel()
            expressLabel.text = "Express Shipping"
            expressShipping.accessibilityIdentifier = "express-shipping"
            placeOrderButton.configuration?.title = "Place Order"
            placeOrderButton.accessibilityIdentifier = "place-order"
            placeOrderButton.addAction(UIAction { [weak self] _ in self?.placeOrderTapped() }, for: .primaryActionTriggered)

            let express = UIStackView(arrangedSubviews: [expressLabel, expressShipping])
            express.spacing = 12
            let stack = UIStackView(arrangedSubviews: [total, express, placeOrderButton])
            stack.axis = .vertical
            stack.alignment = .leading
            stack.spacing = 20
            stack.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor),
                stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            ])
        }

        private func placeOrderTapped() {
            // The traits' tracker carries the checkout's screen name, which the app's bootstrapped
            // tracker doesn't.
            withTracker(view.traitCollection.tracker) { placeOrder(expressShipping.isOn) }
        }
    }
#endif
