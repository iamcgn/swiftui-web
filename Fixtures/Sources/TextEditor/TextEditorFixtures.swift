// TextEditor fixtures: the macOS multi-line editor (geometry in frames, wrapping, an empty one),
// sizing in stacks, font and colour modifiers, disabled, and a behaviour fixture whose text
// follows the model.
import SwiftUI
import FixtureKit

/// Drives `texteditor/steps`.
@Observable
public final class TextEditorModel {
    public var text = "Hello"
    public init() {}
}

public enum TextEditorFixtures {
    public static let basic = Fixture("texteditor/basic", size: CGSize(width: 320, height: 320)) {
        VStack(spacing: 12) {
            TextEditor(text: .constant("Hello\nWorld")).frame(height: 60).probe("lines")
            TextEditor(text: .constant(TextMetricsRequests.paragraph)).frame(height: 80).probe("wrapping")
            TextEditor(text: .constant("")).frame(height: 40).probe("empty")
            TextEditor(text: .constant("Hello")).frame(width: 160, height: 40).probe("narrow")
        }
        .padding(20)
        .probe("stack")
    }

    public static let sizing = Fixture("texteditor/sizing", size: CGSize(width: 320, height: 240)) {
        VStack(spacing: 8) {
            Text("Above").probe("above")
            TextEditor(text: .constant("Hello")).probe("fill")
            HStack(spacing: 8) {
                TextEditor(text: .constant("Left")).probe("left")
                Text("Right").probe("right")
            }
            .frame(height: 60)
            .probe("row")
        }
        .probe("stack")
    }

    public static let styles = Fixture("texteditor/styles", size: CGSize(width: 320, height: 320)) {
        VStack(spacing: 12) {
            TextEditor(text: .constant("Hello")).font(.title).frame(height: 60).probe("title")
            TextEditor(text: .constant("Hello")).foregroundColor(.red).frame(height: 40).probe("red")
            TextEditor(text: .constant("Hello")).disabled(true).frame(height: 40).probe("disabled")
            TextEditor(text: .constant("Hello\nWorld")).lineSpacing(10).frame(height: 60).probe("spaced")
            TextEditor(text: .constant("Hello")).scrollContentBackground(.hidden).frame(height: 40).probe("noBackground")
        }
        .padding(20)
        .probe("stack")
    }

    public static let steps = Fixture(
        "texteditor/steps", size: CGSize(width: 320, height: 160),
        model: { TextEditorModel() },
        steps: [
            FixtureStep("append") { $0.text = "Hello\nWorld" },
            FixtureStep("clear") { $0.text = "" },
        ]
    ) { model in
        VStack(spacing: 12) {
            TextEditor(text: Binding(get: { model.text }, set: { model.text = $0 })).frame(height: 60).probe("editor")
            Text(model.text.isEmpty ? "Empty" : "Filled").probe("echo")
        }
        .padding(20)
        .probe("stack")
    }

    public static let all: [Fixture] = [basic, sizing, styles, steps]
}
