// draggable / dropDestination at rest: the modifiers do not change layout.
import SwiftUI
import FixtureKit

public enum DragDropFixtures {
    public static let basic = Fixture("dragdrop/basic", size: CGSize(width: 300, height: 140), content: {
        HStack(spacing: 30) {
            Text("Drag me").padding(8).background(Color.yellow).draggable("Drag me").probe("source")
            RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.3)).frame(width: 120, height: 80)
                .dropDestination(for: String.self, action: { _, _ in true })
                .probe("target")
        }
        .probe("row")
    })

    /// Drags across the app boundary (sw-dragdrop-os): the destination turns green while a drag
    /// is over it and shows the dropped text; `Playwright/dragdrop-probe.mjs` drives it with the
    /// browser's drag events. At rest it looks like `basic` with an empty label.
    public static let external = Fixture("dragdrop/external", size: CGSize(width: 300, height: 140), model: { DragDropModel() }, steps: []) { model in
        HStack(spacing: 30) {
            Text("Drag me").padding(8).background(Color.yellow).draggable("Drag me").probe("source")
            RoundedRectangle(cornerRadius: 8).fill((model.targeted ? Color.green : Color.blue).opacity(0.3)).frame(width: 120, height: 80)
                .overlay(Text(model.dropped))
                .dropDestination(for: String.self, action: { items, _ in model.dropped = items.first ?? ""; return true },
                                 isTargeted: { model.targeted = $0 })
                .probe("target")
        }
        .probe("row")
    }

    public static let all: [Fixture] = [basic, external]
}

/// Drives `dragdrop/external`.
@Observable
public final class DragDropModel {
    public var dropped = ""
    public var targeted = false
    public init() {}
}
