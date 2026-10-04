// Picker fixtures: the macOS pop-up button (default), hidden labels, segmented, radio group and
// inline styles, data-driven options, custom labels, disabled, and a behaviour fixture whose
// selection follows the model.
import SwiftUI
import FixtureKit

/// Drives `picker/steps`.
@Observable
public final class PickerModel {
    public var selection = 1
    public init() {}
}

public enum PickerFixtures {
    public static let basic = Fixture("picker/basic", size: CGSize(width: 320, height: 320)) {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Fruit", selection: .constant(1)) {
                Text("Apple").tag(1); Text("Banana").tag(2); Text("Cherry").tag(3)
            }
            .probe("menu")
            Picker("Fruit", selection: .constant(2)) {
                Text("Apple").tag(1); Text("Banana").tag(2); Text("Cherry").tag(3)
            }
            .labelsHidden()
            .probe("menuHidden")
            Picker("Fruit", selection: .constant(1)) {
                Text("Apple").tag(1).probe("segApple"); Text("Banana").tag(2).probe("segBanana"); Text("Cherry").tag(3).probe("segCherry")
            }
            .pickerStyle(.segmented)
            .probe("segmented")
            #if !os(iOS)   // macOS-only API (true on macOS, wasm and Linux); the iOS builds render only ios/ fixtures
            Picker("Fruit", selection: .constant(1)) {
                Text("Apple").tag(1).probe("radioApple"); Text("Banana").tag(2).probe("radioBanana"); Text("Cherry").tag(3).probe("radioCherry")
            }
            .pickerStyle(.radioGroup)
            .probe("radio")
            #endif
            Picker("Fruit", selection: .constant(1)) {
                Text("Apple").tag(1).probe("inlineApple"); Text("Banana").tag(2).probe("inlineBanana")
            }
            .pickerStyle(.inline)
            .probe("inline")
        }
        .probe("stack")
    }

    public static let forms = Fixture("picker/forms", size: CGSize(width: 320, height: 260)) {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Fruit", selection: .constant(1)) {
                ForEach(ListItem.fruits) { Text($0.name) }
            }
            .probe("forEach")
            Picker(selection: .constant(1)) {
                Text("Apple").tag(1); Text("Banana").tag(2)
            } label: {
                Label("Fruit", image: "icon")
            }
            .probe("labelPicker")
            Picker("Fruit", selection: .constant(1)) { Text("Apple").tag(1); Text("Banana").tag(2) }
                .disabled(true)
                .probe("disabled")
            Picker("Fruit", selection: .constant(1)) { Text("Apple").tag(1); Text("Banana").tag(2) }
                .frame(width: 200)
                .probe("fixed")
            Picker("Fruit", selection: .constant(1)) { Text("Apple").tag(1); Text("Banana").tag(2) }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .probe("fixedSegmented")
            HStack(spacing: 8) {
                Text("Row").probe("rowText")
                Picker("Fruit", selection: .constant(1)) { Text("Apple").tag(1); Text("Banana").tag(2) }.labelsHidden().probe("rowPicker")
                Button("OK") {}.probe("rowButton")
            }
            .probe("row")
        }
        .probe("stack")
    }

    public static let steps = Fixture(
        "picker/steps", size: CGSize(width: 320, height: 160),
        model: { PickerModel() },
        steps: [
            FixtureStep("banana") { $0.selection = 2 },
            FixtureStep("cherry") { $0.selection = 3 },
        ]
    ) { model in
        let selection = Binding(get: { model.selection }, set: { model.selection = $0 })
        VStack(alignment: .leading, spacing: 12) {
            Picker("Fruit", selection: selection) { Text("Apple").tag(1); Text("Banana").tag(2); Text("Cherry").tag(3) }.probe("menu")
            Picker("Fruit", selection: selection) { Text("Apple").tag(1); Text("Banana").tag(2); Text("Cherry").tag(3) }
                .pickerStyle(.segmented).probe("segmented")
            #if !os(iOS)   // macOS-only API (true on macOS, wasm and Linux); the iOS builds render only ios/ fixtures
            Picker("Fruit", selection: selection) { Text("Apple").tag(1); Text("Banana").tag(2); Text("Cherry").tag(3) }
                .pickerStyle(.radioGroup).probe("radio")
            #endif
        }
        .probe("stack")
    }

    /// Options that are images or labels, dividers and sections in a pop-up's content, a
    /// `sources:` picker over agreeing and mixed bindings, and `tag(_:includeOptional:)`. Not
    /// in the golden set: on macOS 26.6 every picker stretches to the proposed width with a
    /// 20 pt pop-up and 22 pt segments, unlike the 26.2 goldens the runtime matches
    /// (Docs/elements/Picker.md, "macOS 26.6"); the unit tests cover the behaviour.
    public static let options = Fixture("picker/options", size: CGSize(width: 360, height: 320)) {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Align", selection: .constant(1)) {
                Image(systemName: "text.alignleft").tag(1)
                Image(systemName: "text.aligncenter").tag(2)
                Image(systemName: "text.alignright").tag(3)
            }
            .pickerStyle(.segmented)
            .probe("iconSegments")
            Picker("Fruit", selection: .constant(1)) {
                Label("Apple", systemImage: "leaf").tag(1)
                Label("Banana", systemImage: "moon").tag(2)
            }
            .pickerStyle(.segmented)
            .probe("labelSegments")
            Picker("Fruit", selection: .constant(2)) {
                Section("Fresh") {
                    Label("Apple", systemImage: "leaf").tag(1)
                    Label("Banana", systemImage: "moon").tag(2)
                }
                Divider()
                Text("Cherry").tag(3)
            }
            .probe("labelMenu")
            #if !os(iOS)
            Picker("Fruit", selection: .constant(1)) {
                Label("Apple", systemImage: "leaf").tag(1).probe("radioApple")
                Label("Banana", systemImage: "moon").tag(2).probe("radioBanana")
            }
            .pickerStyle(.radioGroup)
            .probe("labelRadio")
            #endif
            Picker("Size", selection: .constant(Optional(2))) {
                Text("Small").tag(1, includeOptional: true)
                Text("Large").tag(2, includeOptional: true)
            }
            .probe("optionalTag")
            Picker("Shared", sources: [PickerSource(value: .constant(1)), PickerSource(value: .constant(1))], selection: \PickerSource.value) {
                Text("One").tag(1); Text("Two").tag(2)
            }
            .probe("sourcesAgree")
            Picker("Mixed", sources: [PickerSource(value: .constant(1)), PickerSource(value: .constant(2))], selection: \PickerSource.value) {
                Text("One").tag(1); Text("Two").tag(2)
            }
            .probe("sourcesMixed")
        }
        .probe("stack")
    }

    public static let all: [Fixture] = [basic, forms, steps]
}

/// A source of a `Picker(sources:)`: an element holding a binding to its value.
public struct PickerSource {
    public var value: Binding<Int>
    public init(value: Binding<Int>) { self.value = value }
}

