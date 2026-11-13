// Layers as Objective-C objects (CALayer.swift, decision 0023): with the runtime a layer is an
// NSObject, so the layer delegate's `display(_:)` can be named by selector, as Gifu's image view
// does, and key-value coding on a layer keeps what is set under a key it has no property for.
#if canImport(ObjectiveC)
import Testing
import UIKit
@testable import UIKitWebCore

/// Gifu's GIFImageView (Classes/GIFImageView.swift), cut down: it asks whether UIImageView
/// responds to `display(_:)` before calling super, then updates its frame.
@MainActor final class AnimatedImageView: UIImageView {
    var updates = 0
    override func display(_ layer: CALayer) {
        if UIImageView.instancesRespond(to: #selector(display(_:))) {
            super.display(layer)
        }
        updates += 1
    }
}

@Suite @MainActor struct LayerObjectTests {
    @Test func aLayerIsAnObjectiveCObject() {
        let layer = CALayer()
        let object: NSObject = layer
        #expect(object.isEqual(layer) && !object.isEqual(CALayer()))
        let shape: NSObject = CAShapeLayer()
        #expect(shape is CALayer)
    }

    @Test func theLayerDelegatesDisplayIsNamedBySelector() {
        #expect(UIImageView.instancesRespond(to: #selector(UIView.display(_:))))
        let view = AnimatedImageView(image: nil)
        view.display(view.layer)
        #expect(view.updates == 1)
        // Sent by selector, as Core Animation sends it to the layer's delegate.
        _ = view.perform(#selector(UIView.display(_:)), with: view.layer)
        #expect(view.updates == 2)
    }

    @Test func aLayerKeepsValuesForKeysItHasNoPropertyFor() {
        let layer = CALayer()
        layer.setValue("badge", forKey: "tag")
        layer.setValue(3, forKey: "index")
        #expect(layer.value(forKey: "tag") as? String == "badge")
        #expect(layer.value(forKey: "index") as? Int == 3)
        #expect(layer.value(forKey: "missing") == nil)
        layer.setValue(nil, forKey: "tag")
        #expect(layer.value(forKey: "tag") == nil)
        #expect(CALayer().value(forKey: "index") == nil)
    }
}
#endif
