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

    /// Actions, levels, order, live regions, help and rotors on text alone (nothing that
    /// drifts between macOS releases): the golden is layout only, the probe checks the overlay.
    public static let actions = Fixture("accessibility/actions", size: CGSize(width: 320, height: 220)) {
        AccessibilityActionsDemo()
    }

    public static let all: [Fixture] = [basic, actions]
}

struct AccessibilityActionsDemo: View {
    @Namespace private var fruit
    @State private var archived = 0
    @State private var level = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Overview").accessibilityHeading(.h1).probe("title")
            Text("Archived: \(archived)")
                .accessibilityAction(named: "Archive") { archived += 1 }
                .accessibilityAction { archived += 10 }
                .probe("card")
            Text("Level: \(level)")
                .accessibilityAdjustableAction { level += $0 == .increment ? 1 : -1 }
                .probe("level")
            Text("Third").accessibilitySortPriority(-1).probe("third")
            Text("Second").probe("second")
            Text("Ticker").accessibilityAddTraits(.updatesFrequently).help("Updates every second").probe("ticker")
            VStack(alignment: .leading, spacing: 10) {
                Text("Apple").accessibilityRotorEntry(id: "apple", in: fruit).probe("apple")
                Text("Banana").accessibilityRotorEntry(id: "banana", in: fruit).probe("banana")
            }
            .accessibilityRotor("Fruit") {
                AccessibilityRotorEntry("Apple", id: "apple", in: fruit)
                AccessibilityRotorEntry("Banana", id: "banana", in: fruit)
            }
        }
        .probe("stack")
    }
}
