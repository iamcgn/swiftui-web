// The hooks a view hosting another framework's scene inside UIKit overrides (SwiftUIWeb's
// `UIHostingController` in SwiftUIWebUIKit; decision 0014, Phase 3): what it paints, the
// accessibility elements it exposes and the routing of the host's calls to them, the clock it
// advances on. The names carry an underscore: this is SPI for the frameworks built on UIKitWeb,
// not UIKit API.

extension UIView {
    /// Registers this view as a hosting view: the scene advances its clock and routes semantics
    /// identifiers it owns to it. Call from the hosting view's initializer.
    public func _registerAsHostingView() { UIKitScene.shared.registerHostingView(self) }
}

extension UIKitScene {
    struct WeakView { weak var view: UIView? }

    func registerHostingView(_ view: UIView) {
        hostingViews.removeAll { $0.view == nil }
        hostingViews.append(WeakView(view: view))
    }

    /// The hosting view owning `identifier`, if any, in a window of the scene or a hosted tree.
    func hostingView(handling identifier: Int) -> UIView? {
        hostingViews.compactMap(\.view).first { $0._hostedHandles(semanticsIdentifier: identifier) }
    }

    func advanceHostingViews(elapsed: Double) -> Bool {
        var animating = false
        for entry in hostingViews {
            if let view = entry.view, view.window != nil, view._hostedAdvanceFrame(elapsed: elapsed) { animating = true }
        }
        return animating
    }

    var hostedFocusedTextFieldIdentifier: Int? {
        for entry in hostingViews {
            if let view = entry.view, let identifier = view._hostedFocusedTextFieldIdentifier { return identifier }
        }
        return nil
    }
}
