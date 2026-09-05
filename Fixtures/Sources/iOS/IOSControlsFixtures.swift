// More of the iOS profile: progress views, the bold trait of every text style, the spacing a
// `VStack` puts between controls, and list footers.
import SwiftUI
import FixtureKit

public enum IOSControlsFixtures {
    /// Linear bars (determinate, indeterminate, labelled) and the ring / spinner.
    public static let progress = Fixture("ios/progress/basic", size: CGSize(width: 320, height: 300)) {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView(value: 0.4).probe("bar")
            ProgressView().progressViewStyle(.linear).probe("indeterminate")
            ProgressView(value: 0.4) { Text("Volume") }.probe("labelled")
            ProgressView(value: 0.4).frame(width: 120).probe("narrow")
            HStack(spacing: 12) {
                ProgressView().probe("spinner")
                ProgressView(value: 0.4).progressViewStyle(.circular).probe("ring")
                ProgressView { Text("Volume") }.probe("spinnerLabelled")
            }
            .probe("row")
        }
        .probe("stack")
    }.platform(.iOS)

    /// The bold trait on every text style.
    public static let boldTrait = Fixture("ios/text/bold-trait", size: CGSize(width: 320, height: 480)) {
        VStack(alignment: .leading, spacing: 0) {
            Text("Large Title").font(.largeTitle).bold().probe("largeTitle")
            Text("Title").font(.title).bold().probe("title")
            Text("Title 2").font(.title2).bold().probe("title2")
            Text("Title 3").font(.title3).bold().probe("title3")
            Text("Headline").font(.headline).bold().probe("headline")
            Text("Subheadline").font(.subheadline).bold().probe("subheadline")
            Text("Body").font(.body).bold().probe("body")
            Text("Callout").font(.callout).bold().probe("callout")
            Text("Footnote").font(.footnote).bold().probe("footnote")
            Text("Caption").font(.caption).bold().probe("caption")
            Text("Caption 2").font(.caption2).bold().probe("caption2")
        }
        .probe("stack")
    }.platform(.iOS)

    /// Default `VStack` spacing between controls and text.
    public static let controlSpacing = Fixture("ios/layout/controls", size: CGSize(width: 320, height: 480)) {
        VStack {
            Text("Hello").probe("text")
            Toggle("Enabled", isOn: .constant(true)).probe("toggle")
            Button("OK") {}.probe("plain")
            Button("Bordered") {}.buttonStyle(.bordered).probe("bordered")
            TextField("Placeholder", text: .constant("Hello")).probe("field")
            TextField("Placeholder", text: .constant("Hello")).textFieldStyle(.roundedBorder).probe("rounded")
            Slider(value: .constant(0.5)).probe("slider")
            Stepper("Quantity: 3", value: .constant(3)).probe("stepper")
            Picker("Size", selection: .constant(1)) { Text("Small").tag(1); Text("Medium").tag(2) }.pickerStyle(.segmented).probe("segmented")
            Text("Hello").probe("textBelow")
        }
        .probe("stack")
    }.platform(.iOS)

    /// Section footers in the grouped and plain looks.
    public static let listFooter = Fixture("ios/list/footer", size: CGSize(width: 320, height: 400)) {
        List {
            Section {
                Text("Apple").probe("row1")
            } header: {
                Text("Fruit").probe("header")
            } footer: {
                Text("Banana").probe("footer")
            }
            Section {
                Text("Cherry").probe("row2")
            } footer: {
                Text("Apple").probe("footer2")
            }
        }
        .probe("list")
    }.platform(.iOS)

    public static let all: [Fixture] = [progress, boldTrait, controlSpacing, listFooter]
}
