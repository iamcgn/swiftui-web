// `UIGestureRecognizerRepresentable` (iOS 18): a UIKit recognizer on a SwiftUI view, made once
// and kept across updates, seeing the view's presses with its coordinator as delegate, its
// actions reaching `handleUIGestureRecognizerAction`, and the converter giving points in the
// view's space and the window's (Mlem's QuickSwipes `PanGesture`).
#if !os(WASI)
import Testing
import SwiftUI
import SwiftUIWebHeadless

@MainActor private final class Log { var events: [String] = []; var made = 0; var updated = 0 }

/// A pan that does not begin within `leadingBuffer` points of the view's leading edge, as
/// Mlem's does.
private struct Pan: UIGestureRecognizerRepresentable {
    let leadingBuffer: CGFloat
    let log: Log

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let leadingBuffer: CGFloat
        init(leadingBuffer: CGFloat) { self.leadingBuffer = leadingBuffer }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer.location(in: gestureRecognizer.view).x > leadingBuffer
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool { true }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator(leadingBuffer: leadingBuffer) }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        log.made += 1
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) { log.updated += 1 }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let local = context.converter.localLocation
        let global = context.converter.location(in: .global)
        let translation = context.converter.localTranslation ?? .zero
        // Apple's other spellings agree: a global point converted back, the space-taking forms.
        let back = context.converter.convert(globalPoint: global)
        let agrees = back == local && context.converter.convert(globalPoint: global, to: .global) == global
            && context.converter.translation(in: .local) == context.converter.localTranslation
            && context.converter.velocity(in: .global) == context.converter.localVelocity
        log.events.append("\(recognizer.state.rawValue) \(Int(local.x)),\(Int(local.y)) \(Int(global.x)) t\(Int(translation.x))\(agrees ? "" : " disagree")")
    }
}

@Observable @MainActor private final class Model { var tint = Color.red }

private struct Panned: View {
    let model: Model
    let log: Log
    var body: some View {
        model.tint.frame(width: 40, height: 20).gesture(Pan(leadingBuffer: 0, log: log))
    }
}

@Suite @MainActor struct GestureRecognizerRepresentableTests {
    // A 40 × 20 box centred in 200 × 100: x 80…120, y 40…60.
    private func runtime(_ log: Log, buffer: CGFloat = 0) -> Runtime {
        let runtime = Runtime()
        runtime.mount(Color.red.frame(width: 40, height: 20).gesture(Pan(leadingBuffer: buffer, log: log)))
        runtime.layout(in: CGSize(width: 200, height: 100))
        return runtime
    }

    @Test func aPanSeesTheViewsPressesInItsSpace() {
        let log = Log()
        let r = runtime(log)
        r.pointerDown(at: CGPoint(x: 90, y: 50), time: 0)
        r.pointerMoved(to: CGPoint(x: 95, y: 50), time: 0.05)
        r.pointerMoved(to: CGPoint(x: 110, y: 52), time: 0.1)
        r.pointerUp(at: CGPoint(x: 110, y: 52), time: 0.15)
        // Below the 10 pt slop nothing; then began, and ended at the release (states 1 and 3).
        #expect(log.events == ["1 30,12 110 t20", "3 30,12 110 t20"])
        #expect(log.made == 1)
    }

    @Test func theCoordinatorDecidesAsTheDelegate() {
        let log = Log()
        let r = runtime(log, buffer: 35)
        // Where the pan would begin is 30 pt from the leading edge: the delegate refuses it.
        r.pointerDown(at: CGPoint(x: 90, y: 50), time: 0)
        r.pointerMoved(to: CGPoint(x: 110, y: 50), time: 0.1)
        r.pointerUp(at: CGPoint(x: 110, y: 50), time: 0.2)
        #expect(log.events.isEmpty)
        // 38 pt in, it begins.
        r.pointerDown(at: CGPoint(x: 100, y: 50), time: 1)
        r.pointerMoved(to: CGPoint(x: 118, y: 50), time: 1.1)
        r.pointerUp(at: CGPoint(x: 118, y: 50), time: 1.2)
        #expect(log.events.first?.hasPrefix("1 ") == true)
    }

    @Test func theRecognizerIsMadeOnceAndUpdated() {
        let log = Log()
        let model = Model()
        let r = Runtime()
        r.mount(Panned(model: model, log: log))
        r.layout(in: CGSize(width: 200, height: 100))
        #expect(log.made == 1)
        let updates = log.updated
        // A change to what the view reads updates the recognizer; it is not made again.
        model.tint = .blue
        r.layout(in: CGSize(width: 200, height: 100))
        #expect(log.made == 1)
        #expect(log.updated > updates)
        r.pointerDown(at: CGPoint(x: 90, y: 50), time: 0)
        r.pointerMoved(to: CGPoint(x: 110, y: 50), time: 0.1)
        r.pointerUp(at: CGPoint(x: 110, y: 50), time: 0.2)
        #expect(log.events.count == 2)
    }
}
#endif
