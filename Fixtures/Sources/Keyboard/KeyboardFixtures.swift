// Keyboard fixture: a selectable list (arrow keys), a focusable view with onKeyPress and
// onMoveCommand, buttons with keyboard shortcuts (⌘S, the default and cancel actions), a sheet
// (Escape) and a menu (arrows and Return). The golden holds the base state only; keys cannot be
// captured by the golden window, so Playwright/keyboard-probe.mjs drives them in the browser.
import SwiftUI
import FixtureKit

@Observable
public final class KeyboardModel {
    public var log = "none"
    public var selection: Int? = nil
    public var sheet = false
    public init() {}
}

struct KeyboardItem: Identifiable, Hashable {
    let id: Int
    let name: String
}

struct KeyboardSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 12) {
            Text("Sheet content")
            Button("Done") { dismiss() }
        }
    }
}

public enum KeyboardFixtures {
    static let items = [KeyboardItem(id: 1, name: "Apple"), KeyboardItem(id: 2, name: "Banana"), KeyboardItem(id: 3, name: "Cherry")]

    public static let basic = Fixture(
        "keyboard/basic", size: CGSize(width: 360, height: 320),
        model: { KeyboardModel() },
        steps: []
    ) { model in
        VStack(spacing: 10) {
            List(items, selection: Binding(get: { model.selection }, set: { model.selection = $0 })) { item in
                Text(item.name)
            }
            .frame(height: 100)
            .probe("list")
            Text("Focus me")
                .padding(6)
                .focusable()
                .onKeyPress(.upArrow) { model.log = "up"; return .handled }
                .onMoveCommand { direction in model.log = "move \(direction)" }
                .probe("focusable")
            HStack(spacing: 12) {
                Button("Save") { model.log = "save" }.keyboardShortcut("s")
                Button("Go") { model.log = "go" }.keyboardShortcut(.defaultAction)
                Button("Cancel") { model.log = "cancel" }.keyboardShortcut(.cancelAction)
            }
            .probe("buttons")
            HStack(spacing: 12) {
                Button("Sheet") { model.sheet = true }
                    .sheet(isPresented: Binding(get: { model.sheet }, set: { model.sheet = $0 })) { KeyboardSheet() }
                Menu("Options") {
                    Button("Cut") { model.log = "cut" }
                    Button("Copy") { model.log = "copy" }
                }
            }
            .probe("row")
            Text("Log: \(model.log)").probe("log")
            Text("Selected: \(model.selection.map { String($0) } ?? "none")").probe("selected")
        }
        .probe("stack")
    }

    public static let all: [Fixture] = [basic]
}
