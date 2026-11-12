// `Color.Resolved` (iOS 17): `resolve(in:)` gives a colour's sRGB components in an environment,
// as IceCubes' theme and Thunderbird's design system use it, and a resolved colour is a colour
// and a shape style again.
import Testing
import SwiftUI
import SwiftUIWebCore
import WebFoundation

@Suite @MainActor struct ColorResolvedTests {
    @Test func resolvesComponents() {
        let resolved: Color.Resolved = Color(red: 1, green: 0.5, blue: 0, opacity: 0.25).resolve(in: EnvironmentValues())
        #expect(resolved == Color.Resolved(red: 1, green: 0.5, blue: 0, opacity: 0.25))
        #expect(resolved.description == "#FF800040")
        let luminance = 0.299 * resolved.red + 0.587 * resolved.green + 0.114 * resolved.blue
        #expect(abs(luminance - 0.5925) < 0.0001)
    }

    @Test func dynamicColoursResolvePerAppearance() {
        var light = EnvironmentValues()
        light.colorScheme = .light
        var dark = EnvironmentValues()
        dark.colorScheme = .dark
        let primaryLight: Color.Resolved = Color.primary.resolve(in: light)
        let primaryDark: Color.Resolved = Color.primary.resolve(in: dark)
        #expect(primaryLight != primaryDark)
        let red: Color.Resolved = Color(red: 1, green: 0, blue: 0).resolve(in: light)
        #expect(red == Color(red: 1, green: 0, blue: 0).resolve(in: dark))
    }

    @Test func linearComponentsAndRoundTrips() throws {
        let mid = Color.Resolved(colorSpace: .sRGBLinear, red: 0.214, green: 0, blue: 1)
        #expect(abs(mid.red - 0.5) < 0.001)
        #expect(abs(mid.linearRed - 0.214) < 0.001)
        #expect(mid.green == 0 && mid.blue == 1)
        let color = Color(mid)
        let back: Color.Resolved = color.resolve(in: EnvironmentValues())
        #expect(abs(back.red - mid.red) < 0.0001)
        let encoded = try JSONEncoder().encode(mid)
        #expect(try JSONDecoder().decode(Color.Resolved.self, from: encoded) == mid)
    }

    @Test func aResolvedColourIsAShapeStyle() {
        let style: any ShapeStyle = Color.Resolved(red: 0, green: 0, blue: 1)
        #expect(style._asColor == Color(red: 0, green: 0, blue: 1))
        #expect(Color.Resolved(red: 0, green: 0, blue: 1).resolveColor(in: EnvironmentValues()) == RGBA(red: 0, green: 0, blue: 1))
    }
}
