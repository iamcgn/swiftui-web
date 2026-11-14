// A control tint given as any shape style (`tint(_:)` with a style, as BackyardBirds' gauge passes
// an `AnyShapeStyle`), and a shape style's own blend mode (`.blue.blendMode(.plusDarker)`): a
// colour tint stays the colour, another style becomes the colour it resolves to in each
// appearance; a shape filled or stroked with a blended style is drawn in a blend group, and as a
// colour (text, a tint) the blended style is its base. Colours and gradients used as views keep
// the view's `blendMode(_:)`.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct ShapeStyleTintBlendTests {
    private func runtime<V: View>(_ view: V, iOS: Bool = false) -> Runtime {
        var environment = EnvironmentValues()
        if iOS { environment.platformProfile = .iOS }
        let runtime = Runtime(environment: environment)
        runtime.textEngine = RecordedTextEngine(entries: [:])
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 200, height: 100))
        return runtime
    }

    private func commands(_ runtime: Runtime) -> [String] { runtime.render(scale: 2).commands.map(\.description) }

    @Test func aStyleTintsControls() {
        let red = Color(red: 1, green: 0, blue: 0)
        let erased = runtime(ProgressView(value: 0.5).tint(AnyShapeStyle(red)), iOS: true)
        #expect(commands(erased).contains { $0.hasPrefix("fillRRect") && $0.hasSuffix("#FF0000") })
        // A gradient tints with its first colour.
        let gradient = runtime(ProgressView(value: 0.5).tint(Gradient(colors: [Color(red: 0, green: 0, blue: 1), red])), iOS: true)
        #expect(commands(gradient).contains { $0.hasPrefix("fillRRect") && $0.hasSuffix("#0000FF") })
        // nil keeps the colour overload: no tint.
        let none = runtime(ProgressView(value: 0.5).tint(nil), iOS: true)
        #expect(!commands(none).contains { $0.hasSuffix("#FF0000") })
    }

    @Test func aStyleTintKeepsBothAppearances() {
        var light = EnvironmentValues(), dark = EnvironmentValues()
        light.colorScheme = .light
        dark.colorScheme = .dark
        // A colour, erased or not, is kept as the colour, so it still follows the appearance.
        #expect(Color(_resolving: AnyShapeStyle(Color.primary), in: light) == .primary)
        #expect(Color(_resolving: Color.blue, in: dark) == .blue)
        // Any other style is resolved in each appearance.
        let material = Color(_resolving: Material.regular, in: light)
        #expect(material.resolve(in: light) == Material.regular.tint(in: light))
        #expect(material.resolve(in: dark) == Material.regular.tint(in: dark))
    }

    @Test func aBlendedStyleDrawsInABlendGroup() {
        let red = Color(red: 1, green: 0, blue: 0)
        let fill = commands(runtime(Rectangle().fill(red.blendMode(.multiply)).frame(width: 40, height: 20)))
        let begin = fill.firstIndex { $0.hasPrefix("beginBlend(multiply") }
        let paint = fill.firstIndex { $0.hasPrefix("fillPath") && $0.hasSuffix("#FF0000") }
        #expect(begin != nil && paint != nil)
        if let begin, let paint {
            #expect(begin < paint)
            #expect(fill[(paint + 1)...].first == "endGroup")
        }
        let stroke = commands(runtime(Circle().stroke(red.blendMode(.plusDarker), lineWidth: 3).frame(width: 30, height: 30)))
        #expect(stroke.contains { $0.hasPrefix("beginBlend(plusDarker") })
        #expect(stroke.contains { $0.hasPrefix("strokePath") && $0.hasSuffix("#FF0000") })
    }

    @Test func aBlendedStyleIsItsBaseAsAColour() {
        let environment = EnvironmentValues()
        let style = Color.blue.blendMode(.plusDarker)
        #expect(style.resolveColor(in: environment) == Color.blue.resolve(in: environment))
        #expect(style._asColor == .blue)
        #expect(Color(_resolving: style, in: environment) == .blue)
        let text = commands(runtime(Text("Birds").foregroundStyle(Color(red: 1, green: 0, blue: 0).blendMode(.multiply))))
        #expect(text.contains { $0.hasPrefix("drawText") && $0.contains("#FF0000") })
    }

    @Test func aColourViewKeepsTheViewsBlendMode() {
        let view = Rectangle().frame(width: 20, height: 20).overlay(Color.black.blendMode(.multiply))
        let list = commands(runtime(VStack { Color.red.blendMode(.screen); view }))
        #expect(list.contains { $0.hasPrefix("beginBlend(screen") })
        #expect(list.contains { $0.hasPrefix("beginBlend(multiply") })
    }
}
#endif
