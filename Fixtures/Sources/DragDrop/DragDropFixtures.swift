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

    public static let all: [Fixture] = [basic]
}
