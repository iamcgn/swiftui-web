// Spike 0.4: the runtime plans to discover DynamicProperty fields by key path with the
// underscored stdlib reflection API and to track @Observable reads with withObservationTracking.
// These tests must pass natively AND on wasm (swift package --swift-sdk ... js test).
import Testing
import SwiftUI
@_spi(Reflection) import Swift   // _forEachFieldWithKeyPath

private protocol SpikeDynamicProperty {
    static func spikeInstall<Root>(_ keyPath: PartialKeyPath<Root>, into root: inout Root)
}

private final class SpikeBox<Value> { var value: Value; init(_ v: Value) { value = v } }

private struct SpikeState<Value>: SpikeDynamicProperty {
    var initial: Value
    var box: SpikeBox<Value>? = nil
    static func spikeInstall<Root>(_ keyPath: PartialKeyPath<Root>, into root: inout Root) {
        guard let kp = keyPath as? WritableKeyPath<Root, Self> else { return }
        root[keyPath: kp].box = SpikeBox(root[keyPath: kp].initial)
    }
}

private struct SpikeView {
    var plain = 1
    var count = SpikeState(initial: 5)
    var title = SpikeState(initial: "hi")
}

@Observable private final class SpikeModel { var count = 0 }
private final class Flag: @unchecked Sendable { var fired = false }

@Suite struct ReflectionSpikeTests {
    @Test func discoversFieldsByKeyPathAndInstalls() {
        var view = SpikeView()
        var names: [String] = []
        let ok = _forEachFieldWithKeyPath(of: SpikeView.self, options: []) { name, keyPath in
            names.append(String(cString: name))
            let valueType = type(of: keyPath).valueType
            if let dyn = valueType as? SpikeDynamicProperty.Type {
                dyn.spikeInstall(keyPath, into: &view)
            }
            return true
        }
        #expect(ok)
        #expect(names == ["plain", "count", "title"])
        #expect(view.count.box?.value == 5)
        #expect(view.title.box?.value == "hi")
    }

    @Test func mirrorAndAnyHashableWork() {
        let m = Mirror(reflecting: SpikeView())
        #expect(m.children.map { $0.label ?? "" } == ["plain", "count", "title"])
        let set: Set<AnyHashable> = [AnyHashable(1), AnyHashable("a"), AnyHashable(1)]
        #expect(set.count == 2)
    }

    @Test func observationTrackingFiresOnChange() {
        let model = SpikeModel()
        let flag = Flag()
        withObservationTracking {
            _ = model.count
        } onChange: {
            flag.fired = true
        }
        #expect(!flag.fired)
        model.count += 1
        #expect(flag.fired)
    }

    @Test func coreGraphicsTypesComeWithImportSwiftUI() {
        // Real SwiftUI vends CGFloat/CGRect via its Foundation/CoreGraphics re-export; ours must too.
        let r = CGRect(x: 1, y: 2, width: 3, height: 4)
        #expect(r.maxX == 4 && r.maxY == 6)
        let f: CGFloat = 1.5
        #expect(f.rounded() == 2)
    }
}
