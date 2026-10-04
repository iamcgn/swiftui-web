import SwiftUI
import FixtureKit

public enum ButtonFixtures {
    public static let basic = Fixture("button/basic", size: CGSize(width: 300, height: 200)) {
        VStack(spacing: 12) {
            Button("OK") {}.probe("ok")
            Button("Increment") {}.probe("increment")
            Button(action: {}) { Text("Label").probe("labelText") }.probe("labelButton")
            HStack {
                Button("−") {}.probe("minus")
                Button("+") {}.probe("plus")
            }
            .probe("row")
        }
        .probe("stack")
    }

    public static let styles = Fixture("button/styles", size: CGSize(width: 300, height: 200)) {
        VStack(spacing: 12) {
            Button("Plain") {}.buttonStyle(.plain).probe("plain")
            Button("Bordered") {}.buttonStyle(.bordered).probe("bordered")
            Button("Borderless") {}.buttonStyle(.borderless).probe("borderless")
            Button("Prominent") {}.buttonStyle(.borderedProminent).probe("prominent")
            Button("Padded") {}.padding().probe("paddedOuter")
        }
    }

    /// Control sizes, roles and the disabled look. Out of the golden set: macOS 26.6 draws every
    /// bordered button 20 tall in a white bezel (mini 13, small 16, large 28) and an inactive
    /// window shows no accent, so the 26.2 goldens above would not agree; its measurements are in
    /// Docs/elements/Button.md ("macOS 26.6") and `ios/button/looks` carries the iOS ones.
    public static let looks = Fixture("button/looks", size: CGSize(width: 320, height: 300)) {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button("Mini") {}.controlSize(.mini).probe("mini")
                Button("Small") {}.controlSize(.small).probe("small")
                Button("Regular") {}.probe("regular")
                Button("Large") {}.controlSize(.large).probe("large")
                Button("Extra") {}.controlSize(.extraLarge).probe("extraLarge")
            }
            .probe("sizesRow")
            HStack(spacing: 8) {
                Button("Delete", role: .destructive) {}.probe("destructiveBordered")
                Button("Delete", role: .destructive) {}.buttonStyle(.borderedProminent).probe("destructiveProminent")
                Button("Delete", role: .destructive) {}.buttonStyle(.borderless).probe("destructiveBorderless")
            }
            .probe("rolesRow")
            HStack(spacing: 8) {
                Button("Bordered") {}.disabled(true).probe("disabledBordered")
                Button("Prominent") {}.buttonStyle(.borderedProminent).disabled(true).probe("disabledProminent")
                Button("Plain") {}.buttonStyle(.plain).disabled(true).probe("disabledPlain")
            }
            .probe("disabledRow")
            Button("Large") {}.buttonStyle(.borderedProminent).controlSize(.large).probe("prominentLarge")
        }
        .probe("stack")
    }

    public static let all: [Fixture] = [basic, styles]
}
