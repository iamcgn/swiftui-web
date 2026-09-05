// The iOS profile's colours: the system palette in both appearances and the dark looks of
// text, controls, lists, forms and the navigation bar (Catalyst window in the dark style).
import SwiftUI
import FixtureKit

public enum IOSDarkFixtures {
    @MainActor private static func systemColorGrid() -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.red.probe("red"); Color.orange.probe("orange"); Color.yellow.probe("yellow"); Color.green.probe("green")
                Color.mint.probe("mint"); Color.teal.probe("teal"); Color.cyan.probe("cyan"); Color.blue.probe("blue")
            }
            HStack(spacing: 0) {
                Color.indigo.probe("indigo"); Color.purple.probe("purple"); Color.pink.probe("pink"); Color.brown.probe("brown")
                Color.white.probe("white"); Color.gray.probe("gray"); Color.black.probe("black"); Color.clear.probe("clear")
            }
            HStack(spacing: 0) {
                Color.primary.probe("primary"); Color.secondary.probe("secondary"); Color.accentColor.probe("accentColor")
                Rectangle().fill(.tertiary).probe("tertiary"); Rectangle().fill(.quaternary).probe("quaternary")
                Rectangle().probe("shapeDefault")
            }
        }
        .probe("stack")
    }

    /// The light palette (iOS 26 shares most of macOS 26's values; measured rather than assumed).
    public static let systemColors = Fixture("ios/color/system", size: CGSize(width: 400, height: 240)) {
        systemColorGrid()
    }.platform(.iOS)

    public static let darkSystemColors = Fixture("ios/dark/system-colors", size: CGSize(width: 400, height: 240)) {
        systemColorGrid()
    }.platform(.iOS).colorScheme(.dark)

    public static let darkText = Fixture("ios/dark/text", size: CGSize(width: 320, height: 240)) {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hello").probe("primary")
            Text("Hello").foregroundStyle(.secondary).probe("secondary")
            Text("Hello").foregroundStyle(.tertiary).probe("tertiary")
            Text("Hello").foregroundColor(.red).probe("red")
            Text("Hello").disabled(true).probe("disabled")
            Link("Hello", destination: URL(string: "https://example.com")!).probe("link")
            Divider().probe("divider")
            Text("Hello").underline().probe("underlined")
        }
        .probe("stack")
    }.platform(.iOS).colorScheme(.dark)

    public static let darkControls = Fixture("ios/dark/controls", size: CGSize(width: 320, height: 560)) {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button("OK") {}.probe("plain")
                Button("Bordered") {}.buttonStyle(.bordered).probe("bordered")
                Button("Prominent") {}.buttonStyle(.borderedProminent).probe("prominent")
            }
            .probe("buttons")
            Button("Disabled") {}.buttonStyle(.bordered).disabled(true).probe("disabledButton")
            Toggle("Enabled", isOn: .constant(true)).probe("switchOn")
            Toggle("Enabled", isOn: .constant(false)).probe("switchOff")
            TextField("Placeholder", text: .constant("")).probe("emptyField")
            TextField("Placeholder", text: .constant("Hello")).textFieldStyle(.roundedBorder).probe("roundedField")
            TextField("Placeholder", text: .constant("Hello")).textFieldStyle(.roundedBorder).disabled(true).probe("disabledField")
            Slider(value: .constant(0.5)).probe("slider")
            Stepper("Quantity: 3", value: .constant(3)).probe("stepper")
            Picker("Fruit", selection: .constant(1)) { Text("Apple").tag(1); Text("Banana").tag(2) }.probe("menuPicker")
            Picker("Size", selection: .constant(1)) { Text("Small").tag(1); Text("Medium").tag(2) }.pickerStyle(.segmented).probe("segmented")
        }
        .probe("stack")
    }.platform(.iOS).colorScheme(.dark)

    public static let darkList = Fixture("ios/dark/list", size: CGSize(width: 320, height: 400)) {
        List {
            Text("Apple").probe("row1")
            Text("Banana").probe("row2")
            Section("Fruit") {
                Toggle("Enabled", isOn: .constant(true)).probe("toggle")
                HStack { Text("Detail").probe("detailLabel"); Spacer(); Text("Value").foregroundStyle(.secondary).probe("detailValue") }.probe("detailRow")
            }
        }
        .probe("list")
    }.platform(.iOS).colorScheme(.dark)

    public static let darkListPlain = Fixture("ios/dark/list-plain", size: CGSize(width: 320, height: 240)) {
        List {
            Text("Apple").probe("row1")
            Text("Banana").probe("row2")
        }
        .listStyle(.plain)
        .probe("list")
    }.platform(.iOS).colorScheme(.dark)

    public static let darkForm = Fixture("ios/dark/form", size: CGSize(width: 320, height: 480)) {
        Form {
            Section("Account") {
                TextField("Name", text: .constant("Ada")).probe("name")
                Toggle("Notifications", isOn: .constant(true)).probe("toggle")
            }
            Section("Preferences") {
                Picker("Flavour", selection: .constant("Vanilla")) {
                    Text("Vanilla").tag("Vanilla"); Text("Chocolate").tag("Chocolate")
                }
                .probe("picker")
                Stepper("Quantity: 3", value: .constant(3)).probe("stepper")
                Slider(value: .constant(0.5)) { Text("Volume") }.probe("slider")
                Button("Save") {}.probe("button")
            }
        }
        .probe("form")
    }.platform(.iOS).colorScheme(.dark)

    /// The bar over a list in the dark style, then pushed: the dark back button.
    public static let darkNavigation = Fixture(
        "ios/dark/nav", size: CGSize(width: 320, height: 400),
        model: { IOSNavigationModel() },
        steps: [FixtureStep("push") { $0.path = [1] }]
    ) { model in
        NavigationStack(path: Binding(get: { model.path }, set: { model.path = $0 })) {
            List {
                NavigationLink("Detail", value: 1).probe("link")
                Text("Row").probe("row")
            }
            .navigationTitle("Settings")
            .navigationDestination(for: Int.self) { _ in
                VStack { Text("Pushed").probe("pushed") }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle("Detail")
                    #if canImport(SwiftUIWebCore) || targetEnvironment(macCatalyst)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .probe("detail")
            }
            .probe("list")
        }
        .probe("nav")
    }.platform(.iOS).colorScheme(.dark)

    public static let all: [Fixture] = [systemColors, darkSystemColors, darkText, darkControls, darkList, darkListPlain, darkForm, darkNavigation]
}
