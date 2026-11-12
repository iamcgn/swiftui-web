// UIKit's and Foundation's option sets are Hashable, as every imported NS_OPTIONS type is: apps
// key dictionaries by control states and events and synthesise Hashable over structs that hold
// animation options (swift-navigation's `UIKitAnimation`).
import Testing
import UIKit

@Suite struct OptionSetHashableTests {
    struct Transition: Hashable {
        var duration: Double
        var options: UIView.AnimationOptions
    }

    @Test func optionSetsKeyDictionariesAndSynthesiseHashable() {
        var handlers: [UIControl.Event: String] = [:]
        handlers[.touchUpInside] = "tap"
        handlers[[.editingChanged, .valueChanged]] = "change"
        #expect(handlers[.touchUpInside] == "tap")
        #expect(handlers[[.valueChanged, .editingChanged]] == "change")

        let a = Transition(duration: 0.3, options: [.curveEaseIn, .allowUserInteraction])
        let b = Transition(duration: 0.3, options: [.allowUserInteraction, .curveEaseIn])
        #expect(Set([a, b]).count == 1)
        #expect(Set<UIRectEdge>([.top, .bottom, [.top]]).count == 2)
    }
}
