// Dark appearance fixtures: the same views as their light fixtures, rendered with
// `colorScheme == .dark` (the harness gives the window the dark appearance).
import SwiftUI
import FixtureKit

public enum DarkFixtures {
    public static let systemColors = Fixture("dark/system-colors", size: CGSize(width: 400, height: 240)) {
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
                Color("Accent").probe("namedAccent"); Color("Panel").probe("namedPanel")
                Rectangle().fill(.tertiary).probe("tertiary"); Rectangle().fill(.quaternary).probe("quaternary")
                Rectangle().probe("shapeDefault")
            }
        }
        .probe("stack")
    }.colorScheme(.dark)

    public static let text = Fixture("dark/text", size: CGSize(width: 320, height: 200)) {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hello").probe("primary")
            Text("Hello").foregroundStyle(.secondary).probe("secondary")
            Text("Hello").foregroundStyle(.tertiary).probe("tertiary")
            Text("Hello").foregroundColor(.red).probe("red")
            Text("Hello").disabled(true).probe("disabled")
            Link("Hello", destination: URL(string: "https://example.com")!).probe("link")
            Divider().probe("divider")
            Text("Hello").font(.title).underline().probe("underlined")
        }
        .probe("stack")
    }.colorScheme(.dark)

    public static let controls = Fixture("dark/controls", size: CGSize(width: 320, height: 460)) {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button("Plain") {}.buttonStyle(.plain).probe("plain")
                Button("Bordered") {}.buttonStyle(.bordered).probe("bordered")
                Button("Prominent") {}.buttonStyle(.borderedProminent).probe("prominent")
                Button("Hidden") {}.disabled(true).probe("disabledButton")
            }
            .probe("buttons")
            HStack(spacing: 12) {
                Toggle("Enabled", isOn: .constant(true)).probe("checkOn")
                Toggle("Enabled", isOn: .constant(false)).probe("checkOff")
            }
            .probe("checks")
            HStack(spacing: 12) {
                Toggle("Enabled", isOn: .constant(true)).toggleStyle(.switch).probe("switchOn")
                Toggle("Enabled", isOn: .constant(false)).toggleStyle(.switch).probe("switchOff")
            }
            .probe("switches")
            TextField("Placeholder", text: .constant("")).probe("emptyField")
            TextField("Placeholder", text: .constant("Hello")).probe("filledField")
            TextField("Placeholder", text: .constant("Hello")).disabled(true).probe("disabledField")
            Slider(value: .constant(0.5)).probe("slider")
            ProgressView(value: 0.4).probe("progress")
            Stepper("Volume", value: .constant(1)).probe("stepper")
            Picker("Fruit", selection: .constant(1)) { Text("Apple").tag(1); Text("Banana").tag(2) }.probe("menuPicker")
            Picker("Fruit", selection: .constant(1)) { Text("Apple").tag(1); Text("Banana").tag(2) }.pickerStyle(.segmented).probe("segmented")
            GroupBox("Settings") { Text("Inside").probe("inside") }.probe("groupBox")
        }
        .probe("stack")
    }.colorScheme(.dark)

    public static let list = Fixture("dark/list", size: CGSize(width: 320, height: 200)) {
        List {
            Text("Apple").probe("row1")
            Text("Banana").probe("row2")
            Toggle("Enabled", isOn: .constant(true)).probe("toggle")
        }
        .probe("list")
    }.colorScheme(.dark)

    public static let all: [Fixture] = [systemColors, text, controls, list]
}
