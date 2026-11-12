// Animation, Gradient and AnyGradient are Hashable, as SwiftUI declares them: apps and packages
// key dictionaries by them or put them in Hashable types (swift-navigation's
// `UIKitAnimation.Framework` holds an `Animation` and synthesises Hashable).
import Testing
import SwiftUI
import SwiftUIWebCore

@Suite struct HashableValuesTests {
    @Test func animationsHashByCurveAndTiming() {
        let set: Set<Animation> = [.easeIn(duration: 0.3), .easeIn(duration: 0.3), .linear, .linear.delay(1), .spring]
        #expect(set.count == 4)
        #expect(set.contains(.linear.delay(1)))
        #expect(!set.contains(.linear.delay(2)))
    }

    @Test func gradientsHashByTheirStops() {
        let a = Gradient(colors: [.red, .blue])
        let b = Gradient(stops: [.init(color: .red, location: 0), .init(color: .blue, location: 1)])
        let c = Gradient(colors: [.blue, .red])
        #expect(Set([a, b, c]).count == 2)
        #expect(Set([AnyGradient(a), AnyGradient(b), AnyGradient(c)]).count == 2)
        #expect(a.stops.map(\.hashValue) == b.stops.map(\.hashValue))
    }
}
