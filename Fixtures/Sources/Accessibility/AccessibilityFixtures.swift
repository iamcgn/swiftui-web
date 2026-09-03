// Accessibility fixture: static text, an image with a label, a heading trait, a hidden view,
// a combined element, and the controls whose roles the overlay exposes. The golden is layout
// only; Playwright/accessibility-probe.mjs checks the DOM overlay's roles and labels.
import SwiftUI
import FixtureKit

@Observable
public final class AccessibilityModel {
    public var volume = 0.25
    public var count = 2
    public init() {}
}

public enum AccessibilityFixtures {
    public static let basic = Fixture(
        "accessibility/basic", size: CGSize(width: 320, height: 300),
        model: { AccessibilityModel() }, steps: []
    ) { model in
        VStack(alignment: .leading, spacing: 10) {
            Text("Heading").accessibilityAddTraits(.isHeader).probe("heading")
            Text("Plain").probe("plain")
            Image("icon").accessibilityLabel("Icon image").probe("image")
            Text("Secret").accessibilityHidden(true).probe("hidden")
            HStack(spacing: 8) {
                Text("Card")
                Text("Detail")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Card with detail")
            .probe("card")
            Button("Save") {}.accessibilityHint("Saves the document").accessibilityIdentifier("save").probe("button")
            Toggle("Flag", isOn: .constant(true)).toggleStyle(.switch).probe("switch")
            Slider(value: Binding(get: { model.volume }, set: { model.volume = $0 })).accessibilityLabel("Volume").probe("slider")
            Stepper("Count", value: Binding(get: { model.count }, set: { model.count = $0 })).probe("stepper")
        }
        .probe("stack")
    }

    public static let all: [Fixture] = [basic]
}
