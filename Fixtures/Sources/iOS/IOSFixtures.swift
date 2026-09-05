// iOS fixtures (`ios/…`): rendered by Apple's SwiftUI in a UIKit window on Mac Catalyst
// (scripts/gen-goldens-ios.sh, decision 0013) and reproduced by the runtime's iOS platform
// profile. The iPad idiom shares its text styles and controls with iPhone.
import SwiftUI
import FixtureKit

public enum IOSFixtures {
    /// Every text style, the default font and the bold trait.
    public static let textStyles = Fixture("ios/text/styles", size: CGSize(width: 400, height: 460)) {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hello").probe("default")
            Text("Large Title").font(.largeTitle).probe("largeTitle")
            Text("Title").font(.title).probe("title")
            Text("Title 2").font(.title2).probe("title2")
            Text("Title 3").font(.title3).probe("title3")
            Text("Headline").font(.headline).probe("headline")
            Text("Subheadline").font(.subheadline).probe("subheadline")
            Text("Body").font(.body).probe("body")
            Text("Callout").font(.callout).probe("callout")
            Text("Footnote").font(.footnote).probe("footnote")
            Text("Caption").font(.caption).probe("caption")
            Text("Caption 2").font(.caption2).probe("caption2")
            Text("Bold").bold().probe("bold")
        }
        .probe("stack")
    }.platform(.iOS)

    /// Default padding, stack spacing between texts and to plain views, the divider.
    public static let layoutBasics = Fixture("ios/layout/basics", size: CGSize(width: 320, height: 300)) {
        VStack(alignment: .leading, spacing: 0) {
            Text("Hello").probe("paddedText").padding().probe("padded")
            VStack { Text("One").probe("one"); Text("Two").probe("two") }.probe("textStack")
            VStack { Text("Hello").probe("textAboveBox"); Color.blue.frame(width: 40, height: 10).probe("box") }.probe("mixedStack")
            HStack { Text("One").probe("hOne"); Text("Two").probe("hTwo"); Color.red.frame(width: 10, height: 10).probe("hBox") }.probe("hStack")
            Divider().probe("divider")
        }
        .probe("stack")
    }.platform(.iOS)

    /// The switch: on, off, custom label, baseline next to plain text, hidden label, disabled.
    public static let toggle = Fixture("ios/toggle/basic", size: CGSize(width: 320, height: 300)) {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enabled", isOn: .constant(true)).probe("on")
            Toggle("Enabled", isOn: .constant(false)).probe("off")
            Toggle(isOn: .constant(true)) { Text("Hg").probe("customText") }.probe("custom")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Toggle("Hg", isOn: .constant(true)).probe("baselineToggle")
                Text("Hg").probe("baselineText")
            }
            .probe("baselineRow")
            Toggle("Enabled", isOn: .constant(true)).labelsHidden().probe("hidden")
            Toggle("Enabled", isOn: .constant(true)).disabled(true).probe("disabled")
        }
        .probe("stack")
    }.platform(.iOS)

    /// Button styles: the plain default, bordered, prominent, borderless, disabled, destructive.
    public static let button = Fixture("ios/button/basic", size: CGSize(width: 320, height: 320)) {
        VStack(alignment: .leading, spacing: 12) {
            Button("OK") {}.probe("plain")
            Button("Bordered") {}.buttonStyle(.bordered).probe("bordered")
            Button("Prominent") {}.buttonStyle(.borderedProminent).probe("prominent")
            Button("Borderless") {}.buttonStyle(.borderless).probe("borderless")
            Button("Disabled") {}.buttonStyle(.bordered).disabled(true).probe("disabled")
            Button("Delete", role: .destructive) {}.probe("destructive")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button("OK") {}.probe("rowButton")
                Text("Hg").probe("rowText")
            }
            .probe("row")
        }
        .probe("stack")
    }.platform(.iOS)

    /// Slider: plain, with a label, stepped, disabled.
    public static let slider = Fixture("ios/slider/basic", size: CGSize(width: 320, height: 220)) {
        VStack(alignment: .leading, spacing: 12) {
            Slider(value: .constant(0.5)).probe("half")
            Slider(value: .constant(0)).probe("zero")
            Slider(value: .constant(0.5)) { Text("Volume") }.probe("labelled")
            Slider(value: .constant(50), in: 0...100, step: 10).probe("stepped")
            Slider(value: .constant(0.5)).disabled(true).probe("disabled")
            Slider(value: .constant(0.5)).frame(width: 120).probe("narrow")
        }
        .probe("stack")
    }.platform(.iOS)

    /// Stepper: labelled, hidden label, disabled, next to text.
    public static let stepper = Fixture("ios/stepper/basic", size: CGSize(width: 320, height: 200)) {
        VStack(alignment: .leading, spacing: 12) {
            Stepper("Quantity: 3", value: .constant(3)).probe("labelled")
            Stepper("Quantity: 3", value: .constant(3)).labelsHidden().probe("hidden")
            Stepper("Quantity: 3", value: .constant(3)).disabled(true).probe("disabled")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Hg").probe("rowText")
                Stepper("Hg", value: .constant(3)).probe("rowStepper")
            }
            .probe("row")
        }
        .probe("stack")
    }.platform(.iOS)

    /// TextField: the plain default, rounded border, empty with placeholder, secure, in a row.
    public static let textField = Fixture("ios/textfield/basic", size: CGSize(width: 320, height: 240)) {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Placeholder", text: .constant("Hello")).probe("plain")
            TextField("Placeholder", text: .constant("Hello")).textFieldStyle(.roundedBorder).probe("rounded")
            TextField("Placeholder", text: .constant("")).textFieldStyle(.roundedBorder).probe("roundedEmpty")
            SecureField("Password", text: .constant("secret")).textFieldStyle(.roundedBorder).probe("secure")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Name").probe("rowLabel")
                TextField("Placeholder", text: .constant("Hello")).textFieldStyle(.roundedBorder).probe("rowField")
            }
            .probe("row")
        }
        .probe("stack")
    }.platform(.iOS)

    /// Picker: the menu default, segmented, hidden label.
    public static let picker = Fixture("ios/picker/basic", size: CGSize(width: 320, height: 240)) {
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
            Picker("Size", selection: .constant(2)) {
                Text("Small").tag(1); Text("Medium").tag(2); Text("Large").tag(3)   // segment titles are not views on iOS: no probes
            }
            .pickerStyle(.segmented)
            .probe("segmented")
            Picker("Size", selection: .constant(1)) {
                Text("Small").tag(1); Text("Medium").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .probe("segmentedNarrow")
        }
        .probe("stack")
    }.platform(.iOS)

    /// A settings screen: the controls the landing page demonstrates in the iOS look.
    public static let settings = Fixture("ios/controls/settings", size: CGSize(width: 320, height: 480)) {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings").font(.largeTitle).bold().probe("title")
            Toggle("Wi-Fi", isOn: .constant(true)).probe("wifi")
            Toggle("Bluetooth", isOn: .constant(false)).probe("bluetooth")
            VStack(alignment: .leading, spacing: 4) {
                Text("Volume").font(.subheadline).probe("volumeLabel")
                Slider(value: .constant(0.6)).probe("volume")
            }
            Stepper("Quantity: 3", value: .constant(3)).probe("quantity")
            Picker("Size", selection: .constant(2)) { Text("Small").tag(1); Text("Medium").tag(2); Text("Large").tag(3) }
                .pickerStyle(.segmented)
                .probe("size")
            TextField("Name", text: .constant("")).textFieldStyle(.roundedBorder).probe("name")
            Button("Save") {}.buttonStyle(.borderedProminent).probe("save")
        }
        .padding()
        .probe("screen")
    }.platform(.iOS)

    public static let all: [Fixture] = [textStyles, layoutBasics, toggle, button, slider, stepper, textField, picker, settings]
}
