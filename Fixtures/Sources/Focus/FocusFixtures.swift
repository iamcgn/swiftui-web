// FocusState fixture: two fields bound to a focus state through `focused(_:equals:)`, a text
// showing which is focused and a button moving focus programmatically. The golden holds the
// unfocused base state (the hosted window is not key); Playwright/focus-probe.mjs drives focus.
import SwiftUI
import FixtureKit

public enum FocusField: Hashable, Sendable { case name, email }

@Observable
public final class FocusModel {
    public var target: FocusField? = nil
    public var name = ""
    public var email = ""
    public init() {}
}

struct FocusForm: View {
    let model: FocusModel
    @FocusState private var focus: FocusField?

    var body: some View {
        VStack(spacing: 12) {
            TextField("Name", text: Binding(get: { model.name }, set: { model.name = $0 }))
                .focused($focus, equals: .name)
                .probe("name")
            TextField("Email", text: Binding(get: { model.email }, set: { model.email = $0 }))
                .focused($focus, equals: .email)
                .probe("email")
            Text(focus == .name ? "Focused: name" : focus == .email ? "Focused: email" : "Focused: none").probe("status")
            Button("Focus email") { focus = .email }.probe("button")
        }
        .onChange(of: model.target) { focus = model.target }
    }
}

public enum FocusFixtures {
    public static let basic = Fixture(
        "focus/basic", size: CGSize(width: 320, height: 200),
        model: { FocusModel() },
        steps: []
    ) { model in
        FocusForm(model: model).probe("form")
    }

    public static let all: [Fixture] = [basic]
}
