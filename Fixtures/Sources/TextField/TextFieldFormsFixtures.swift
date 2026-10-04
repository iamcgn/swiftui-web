// Vertical (growing) text fields and formatted values (Docs/elements/TextField.md, "Forms"). The
// plain style keeps these goldens free of the rounded bezel, whose metrics moved on macOS 26.6
// (21 pt tall, narrower insets) while the older text field goldens stay at 26.2.
import SwiftUI
import FixtureKit

/// The note the vertical fields wrap.
public let fixtureFieldNote = "A long note that wraps onto several lines in a narrow field"

public enum TextFieldFormsFixtures {
    /// `axis: .vertical`: a wrapped note, a short one, reserved lines, a line limit and a range.
    public static let vertical = Fixture("textfield/vertical", size: CGSize(width: 300, height: 300)) {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Notes", text: .constant(fixtureFieldNote), axis: .vertical).frame(width: 200).probe("wrapped")
            TextField("Notes", text: .constant("Short"), axis: .vertical).frame(width: 200).probe("short")
            TextField("Notes", text: .constant(""), axis: .vertical).lineLimit(3, reservesSpace: true).frame(width: 200).probe("reserved")
            TextField("Notes", text: .constant(fixtureFieldNote), axis: .vertical).lineLimit(2).frame(width: 200).probe("capped")
            TextField("Notes", text: .constant(fixtureFieldNote), axis: .vertical).lineLimit(2...4).frame(width: 200).probe("ranged")
            TextField("Notes", text: .constant("Short")).frame(width: 200).probe("single")
        }
        .textFieldStyle(.plain)
        .probe("stack")
    }

    /// Values through format styles and a formatter; `fixedSize` so the frames carry the text.
    public static let formatted = Fixture("textfield/formatted", size: CGSize(width: 300, height: 240)) {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Age", value: .constant(1234), format: .number).fixedSize().probe("int")
            TextField("Price", value: .constant(3.14159), format: .number).fixedSize().probe("double")
            TextField("Share", value: .constant(0.25), format: .percent).fixedSize().probe("percent")
            TextField("Amount", value: .constant(12.5), format: .currency(code: "USD")).fixedSize().probe("currency")
            TextField("Count", value: .constant(42), formatter: NumberFormatter()).fixedSize().probe("formatter")
            TextField("Placeholder", text: .constant("Hello")).fixedSize().probe("fixedText")
            TextField("Placeholder", text: .constant("")).fixedSize().probe("fixedEmpty")
        }
        .textFieldStyle(.plain)
        .probe("stack")
    }

    /// The vertical field on iPhone: plain (the default) and rounded, wrapped and short.
    public static let iosVertical = Fixture("ios/textfield/vertical", size: CGSize(width: 375, height: 667)) {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Notes", text: .constant(fixtureFieldNote), axis: .vertical).frame(width: 300).probe("plain")
            TextField("Notes", text: .constant(fixtureFieldNote), axis: .vertical).textFieldStyle(.roundedBorder).frame(width: 300).probe("rounded")
            TextField("Notes", text: .constant("Short"), axis: .vertical).textFieldStyle(.roundedBorder).frame(width: 300).probe("short")
            TextField("Notes", text: .constant(""), axis: .vertical).lineLimit(3, reservesSpace: true).textFieldStyle(.roundedBorder).frame(width: 300).probe("reserved")
        }
        .frame(maxHeight: .infinity, alignment: .top)   // the reserved field's height is approximate: nothing sits below it
        .probe("stack")
    }.platform(.iOS)

    public static let all: [Fixture] = [vertical, formatted, iosVertical]
}
