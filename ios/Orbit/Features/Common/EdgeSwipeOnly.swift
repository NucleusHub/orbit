import SwiftUI
import UIKit

extension View {
    /// iOS 26 lets a drag anywhere on a pushed page pull it back, which reads as the page sliding
    /// sideways while scrolling; this keeps back to the edge swipe.
    func edgeSwipeBackOnly() -> some View {
        background(EdgeSwipeOnly().frame(width: 0, height: 0))
    }
}

private struct EdgeSwipeOnly: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Probe { Probe() }
    func updateUIViewController(_ controller: Probe, context: Context) {}

    final class Probe: UIViewController {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            disable()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            disable()
        }

        private func disable() {
            if #available(iOS 26, *) { navigationController?.interactiveContentPopGestureRecognizer?.isEnabled = false }
        }
    }
}
