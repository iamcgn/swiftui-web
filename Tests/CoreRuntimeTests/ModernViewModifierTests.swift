// What the iOS-branch sweep after PR 97 found most: geometry read with `onGeometryChange`, pages
// sized with `containerRelativeFrame`, anchors drawn over with `overlayPreferenceValue`,
// `ControlGroup`, `fontDesign`, the `.fill` and `.separator` styles and `Color.mix`.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

private struct BoundsKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

@Suite @MainActor struct ModernViewModifierTests {
    private func texts(_ runtime: Runtime) -> [TextNode] {
        runtime.root.descendants(where: { $0 is TextNode }).compactMap { $0 as? TextNode }
    }

    private func node(_ runtime: Runtime, _ string: String) -> TextNode? {
        texts(runtime).first { $0.view.resolvedString == string }
    }

    @Test func geometryChangesReachTheAction() {
        final class Box { var widths: [CGFloat] = []; var pairs: [(CGFloat, CGFloat)] = [] }
        let box = Box()
        let runtime = Runtime()
        runtime.mount(Color.red.frame(width: 120, height: 40)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { box.widths.append($0) }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { old, new in box.pairs.append((old, new)) })
        runtime.layout(in: CGSize(width: 300, height: 300))
        runtime.flush()
        #expect(box.widths == [120])
        #expect(box.pairs.count == 1 && box.pairs.first?.0 == 40 && box.pairs.first?.1 == 40)
        runtime.layout(in: CGSize(width: 300, height: 300))
        runtime.flush()
        #expect(box.widths == [120], "an unchanged value runs nothing")
    }

    @Test func containerRelativeFramesShareTheScrollView() {
        #expect(_ContainerRelativeFrameModifier.share(of: 320, count: 3, span: 1, spacing: 10) == 100)
        #expect(_ContainerRelativeFrameModifier.share(of: 320, count: 3, span: 2, spacing: 10) == 210)
        let runtime = Runtime()
        runtime.mount(ScrollView(.horizontal) {
            HStack(spacing: 0) {
                Text("Page").containerRelativeFrame(.horizontal)
                Text("Half").containerRelativeFrame(.horizontal, count: 2, spacing: 0)
            }
        })
        runtime.layout(in: CGSize(width: 300, height: 200))
        let frames = runtime.root.descendants(where: { $0 is ContainerRelativeFrameNode<Text> }).map(\.frame.width)
        #expect(frames == [300, 150])
    }

    @Test func anchorsAreDrawnOverInTheirPlace() {
        let runtime = Runtime()
        runtime.mount(VStack(spacing: 0) {
            Color.clear.frame(width: 100, height: 50)
            Text("Target").anchorPreference(key: BoundsKey.self, value: .bounds) { $0 }
        }
        .overlayPreferenceValue(BoundsKey.self, alignment: .topLeading) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    Text("Marker").offset(x: proxy[anchor].minX, y: proxy[anchor].minY)
                }
            }
        })
        runtime.layout(in: CGSize(width: 300, height: 300))
        let target = node(runtime, "Target")?.frameInRoot
        let marker = node(runtime, "Marker")?.frameInRoot
        #expect(target != nil && marker != nil)
        if let target, let marker { #expect(marker.minY == target.minY) }
    }

    @Test func controlGroupsShowTheirControls() {
        let runtime = Runtime()
        runtime.mount(VStack {
            ControlGroup { Button("Undo") {}; Button("Redo") {} }
            ControlGroup("Edit", systemImage: "pencil") { Button("Cut") {} }.controlGroupStyle(.navigation)
        }
        .toolbar { ToolbarSpacer(); ToolbarTitleMenu { Button("Rename") {} } })
        runtime.layout(in: CGSize(width: 300, height: 300))
        let shown = texts(runtime).map { $0.view.resolvedString }
        #expect(shown.contains("Undo") && shown.contains("Redo") && shown.contains("Cut"))
    }

    @Test func fontDesignAndTraitsReachTheText() {
        let runtime = Runtime()
        runtime.mount(VStack {
            Text("Round").fontDesign(.rounded)
            Text("Lean").italic()
            Text("12:00").monospacedDigit()
            Text("Code").font(.body).monospaced()
        })
        runtime.layout(in: CGSize(width: 300, height: 300))
        #expect(node(runtime, "Round")?.resolvedFont.family == "system-rounded")
        #expect(node(runtime, "Lean")?.resolvedFont.italic == true)
        #expect(node(runtime, "12:00")?.resolvedFont.tabularDigits == true)
        #expect(node(runtime, "Code")?.resolvedFont.family == "system-monospaced")
    }

    @Test func stylesAndMixedColorsResolve() {
        var environment = EnvironmentValues()
        let fill = FillShapeStyle().resolveColor(in: environment)
        let separator = SeparatorShapeStyle().resolveColor(in: environment)
        #expect(fill.alpha > 0 && fill.alpha < 1)
        #expect(separator.alpha > 0 && separator.alpha < 1)
        environment._backgroundStyle = AnyShapeStyle(Color.red)
        #expect(BackgroundStyle().resolveColor(in: environment) == Color.red.resolve(in: environment))

        let plain = EnvironmentValues()
        let black = Color(red: 0, green: 0, blue: 0), white = Color(red: 1, green: 1, blue: 1)
        #expect(black.mix(with: white, by: 0).resolve(in: plain) == black.resolve(in: plain))
        let device = black.mix(with: white, by: 0.5, in: .device).resolve(in: plain)
        #expect(abs(device.red - 0.5) < 0.001 && abs(device.blue - 0.5) < 0.001)
        let perceptual = black.mix(with: white, by: 0.5).resolve(in: plain)
        #expect(perceptual.red > 0.1 && perceptual.red < 0.5, "Oklab's midpoint is darker than sRGB's")
        #if os(WASI)
        #expect(ProcessInfo.processInfo.thermalState == .nominal && !ProcessInfo.processInfo.isLowPowerModeEnabled)
        #endif
    }
}
