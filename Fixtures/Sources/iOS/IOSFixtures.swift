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

    /// A grouped form: sections with headers, the rows the settings screen uses.
    public static let form = Fixture("ios/form/basic", size: CGSize(width: 320, height: 520)) {
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
    }.platform(.iOS)

    /// A list: plain rows, a section with a header, a row with a detail on the right.
    public static let list = Fixture("ios/list/basic", size: CGSize(width: 320, height: 400)) {
        List {
            Text("Apple").probe("row1")
            Text("Banana").probe("row2")
            Section("Fruit") {
                Text("Cherry").probe("row3")
                HStack { Text("Detail").probe("detailLabel"); Spacer(); Text("Value").foregroundStyle(.secondary).probe("detailValue") }.probe("detailRow")
            }
        }
        .probe("list")
    }.platform(.iOS)

    /// The same rows in the plain list style.
    public static let listPlain = Fixture("ios/list/plain", size: CGSize(width: 320, height: 300)) {
        List {
            Text("Apple").probe("row1")
            Text("Banana").probe("row2")
            Section("Fruit") { Text("Cherry").probe("row3") }
        }
        .listStyle(.plain)
        .probe("list")
    }.platform(.iOS)

    /// A navigation stack with a large title over a list.
    public static let navigation = Fixture("ios/nav/basic", size: CGSize(width: 320, height: 480)) {
        NavigationStack {
            List {
                NavigationLink("Detail") { Text("Pushed") }.probe("link")
                Text("Row").probe("row")
            }
            .navigationTitle("Settings")
            .probe("list")
        }
        .probe("nav")
    }.platform(.iOS)

    /// The same with an inline title.
    public static let navigationInline = Fixture("ios/nav/inline", size: CGSize(width: 320, height: 300)) {
        NavigationStack {
            List { Text("Row").probe("row") }
                .navigationTitle("Settings")
                #if canImport(SwiftUIWebCore) || targetEnvironment(macCatalyst)   // iOS-only API: Apple's macOS SwiftUI lacks it
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .probe("list")
        }
        .probe("nav")
    }.platform(.iOS)

    /// Behaviour: a push through the path binding shows the detail under its own bar with a
    /// back button carrying the previous title; a pop returns to the root.
    public static let navigationPush = Fixture(
        "ios/nav/push", size: CGSize(width: 320, height: 480),
        model: { IOSNavigationModel() },
        steps: [FixtureStep("push") { $0.path = [1] }, FixtureStep("pop") { $0.path = [] }]
    ) { model in
        NavigationStack(path: Binding(get: { model.path }, set: { model.path = $0 })) {
            List {
                NavigationLink("Detail", value: 1).probe("link")
                Text("Row").probe("row")
            }
            .navigationTitle("Settings")
            .navigationDestination(for: Int.self) { _ in
                List { Text("Pushed").probe("pushed") }
                    .navigationTitle("Detail")
                    .probe("detail")
            }
            .probe("list")
        }
        .probe("nav")
    }.platform(.iOS)

    /// The pushed screen with an inline title over plain content.
    public static let navigationPushInline = Fixture(
        "ios/nav/push-inline", size: CGSize(width: 320, height: 480),
        model: { IOSNavigationModel() },
        steps: [FixtureStep("push") { $0.path = [1] }, FixtureStep("pop") { $0.path = [] }]
    ) { model in
        NavigationStack(path: Binding(get: { model.path }, set: { model.path = $0 })) {
            List {
                NavigationLink("Detail", value: 1).probe("link")
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
    }.platform(.iOS)

    /// The pushed screen hides its back button and has no title of its own.
    public static let navigationPushNoBack = Fixture(
        "ios/nav/push-noback", size: CGSize(width: 320, height: 480),
        model: { IOSNavigationModel() },
        steps: [FixtureStep("push") { $0.path = [1] }, FixtureStep("pop") { $0.path = [] }]
    ) { model in
        NavigationStack(path: Binding(get: { model.path }, set: { model.path = $0 })) {
            List {
                NavigationLink("Detail", value: 1).probe("link")
            }
            .navigationTitle("Settings")
            .navigationDestination(for: Int.self) { _ in
                VStack { Text("Pushed").probe("pushed") }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationBarBackButtonHidden()
                    .probe("detail")
            }
            .probe("list")
        }
        .probe("nav")
    }.platform(.iOS)

    /// Sizing: a stack with a small root and no title, next to plain text.
    public static let navigationSizing = Fixture("ios/nav/sizing", size: CGSize(width: 320, height: 300)) {
        VStack(spacing: 8) {
            NavigationStack { Text("Small").probe("small") }.probe("navText")
            Text("Row").probe("below")
        }
        .probe("stack")
    }.platform(.iOS)

    /// Behaviour: scrolling under a large title collapses the bar (a plain scroll view of rows).
    public static let navigationScroll = Fixture(
        "ios/nav/scroll", size: CGSize(width: 320, height: 400),
        model: { IOSScrollModel() },
        steps: [
            FixtureStep("row1") { $0.target = 1 },       // 40 pt: the bar stays large, the content slides under it
            FixtureStep("row8") { $0.target = 8 },       // far: the bar collapses to the inline one and the content grows
        ]
    ) { model in
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(0..<20, id: \.self) { index in
                            Text("Row").frame(maxWidth: .infinity, alignment: .leading).frame(height: 40).probe("row\(index)").id(index)
                        }
                    }
                    .probe("content")
                }
                .navigationTitle("Settings")
                .probe("scroll")
                .onChange(of: model.target) { _, target in
                    if let target { withAnimation { proxy.scrollTo(target, anchor: .top) } }
                }
            }
        }
        .probe("nav")
    }.platform(.iOS)

    public static let all: [Fixture] = [textStyles, layoutBasics, toggle, button, slider, stepper, textField, picker, settings,
                                        form, list, listPlain, navigation, navigationInline,
                                        navigationPush, navigationPushInline, navigationPushNoBack, navigationSizing, navigationScroll]
}

/// Drives `ios/nav/scroll`.
@Observable
public final class IOSScrollModel {
    public var target: Int? = nil
    public init() {}
}

/// Drives the `ios/nav/push*` fixtures.
@Observable
public final class IOSNavigationModel {
    public var path: [Int] = []
    public init() {}
}
