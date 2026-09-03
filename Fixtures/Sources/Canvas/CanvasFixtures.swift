// Canvas fixtures: immediate-mode drawing through GraphicsContext (fills, strokes, text,
// transforms, opacity, clipping) and the canvas's sizing in a stack and a frame.
import SwiftUI
import FixtureKit

public enum CanvasFixtures {
    /// Shapes, a stroked path, text, a translated and rotated square, opacity and a clip.
    public static let basic = Fixture("canvas/basic", size: CGSize(width: 320, height: 240)) {
        Canvas { context, size in
            context.fill(Path(CGRect(x: 10, y: 10, width: 60, height: 40)), with: .color(.red))
            context.fill(Path(ellipseIn: CGRect(x: 90, y: 10, width: 40, height: 40)), with: .color(.blue))
            var line = Path()
            line.move(to: CGPoint(x: 150, y: 10))
            line.addLine(to: CGPoint(x: 230, y: 50))
            line.addLine(to: CGPoint(x: 150, y: 50))
            context.stroke(line, with: .color(.green), lineWidth: 3)
            context.draw(Text("Canvas"), at: CGPoint(x: 40, y: 80), anchor: .center)
            context.draw(Text("Corner"), in: CGRect(x: 100, y: 70, width: 100, height: 20))
            var moved = context
            moved.translateBy(x: 40, y: 120)
            moved.rotate(by: .degrees(45))
            moved.fill(Path(CGRect(x: -15, y: -15, width: 30, height: 30)), with: .color(.orange))
            var faded = context
            faded.opacity = 0.5
            faded.fill(Path(CGRect(x: 100, y: 100, width: 60, height: 40)), with: .color(.purple))
            var clipped = context
            clipped.clip(to: Path(ellipseIn: CGRect(x: 200, y: 90, width: 60, height: 60)))
            clipped.fill(Path(CGRect(x: 200, y: 90, width: 30, height: 60)), with: .color(.black))
            context.fill(Path(CGRect(x: size.width - 20, y: size.height - 20, width: 20, height: 20)), with: .color(.gray))
        }
        .probe("canvas")
    }

    /// A canvas fills its stack's width and shares the height; a frame sizes it.
    public static let sizing = Fixture("canvas/sizing", size: CGSize(width: 320, height: 240)) {
        VStack(spacing: 8) {
            Text("Above").probe("above")
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.red))
            }
            .probe("fill")
            Canvas { context, size in
                context.fill(Path(ellipseIn: CGRect(origin: .zero, size: size)), with: .color(.blue))
            }
            .frame(width: 80, height: 50)
            .probe("framed")
        }
        .probe("stack")
    }

    public static let all: [Fixture] = [basic, sizing]
}
