// `UIGestureRecognizerRepresentable` (iOS 18): a UIKit gesture recognizer as a SwiftUI gesture.
// The recognizer is made once and kept for the view's life (`@State`); the view's presses reach
// it through UIKitWeb's `HostedGestureRecognizerDriver`, on a stand-in view where the SwiftUI
// view is, and each of its actions calls the representable's
// `handleUIGestureRecognizerAction(_:context:)`. While the recognizer has begun, the SwiftUI
// gesture is active, so it takes the press as a recognised `DragGesture` would.
// Docs/elements/Gestures.md.
import SwiftUIWebCore
import UIKitWebCore

/// A type that represents a UIKit gesture recognizer in SwiftUI.
@MainActor @preconcurrency
public protocol UIGestureRecognizerRepresentable {
    /// The type of the recognizer.
    associatedtype UIGestureRecognizerType: UIGestureRecognizer

    /// A type to coordinate with the recognizer (its delegate, typically).
    associatedtype Coordinator = Void

    typealias Context = UIGestureRecognizerRepresentableContext<Self>
    typealias CoordinateSpaceConverter = UIGestureRecognizerRepresentableCoordinateSpaceConverter

    /// Creates the coordinator, before the recognizer.
    @MainActor @preconcurrency func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator

    /// Creates the recognizer and configures its initial state.
    @MainActor @preconcurrency func makeUIGestureRecognizer(context: Context) -> UIGestureRecognizerType

    /// Responds to the recognizer's actions (each change of its state past `possible`).
    @MainActor @preconcurrency func handleUIGestureRecognizerAction(_ recognizer: UIGestureRecognizerType, context: Context)

    /// Updates the recognizer with new information from SwiftUI.
    @MainActor @preconcurrency func updateUIGestureRecognizer(_ recognizer: UIGestureRecognizerType, context: Context)
}

extension UIGestureRecognizerRepresentable {
    public func handleUIGestureRecognizerAction(_ recognizer: UIGestureRecognizerType, context: Context) {}
    public func updateUIGestureRecognizer(_ recognizer: UIGestureRecognizerType, context: Context) {}
}

extension UIGestureRecognizerRepresentable where Coordinator == Void {
    public func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { () }
}

/// What a representable's methods are given: its coordinator and a converter for the
/// recognizer's points.
@MainActor @preconcurrency
public struct UIGestureRecognizerRepresentableContext<Representable: UIGestureRecognizerRepresentable> {
    /// The representable's coordinator.
    public let coordinator: Representable.Coordinator
    /// Converts the recognizer's points into SwiftUI coordinate spaces.
    public let converter: UIGestureRecognizerRepresentableCoordinateSpaceConverter
}

/// The recognizer's location, translation and velocity in a SwiftUI coordinate space: the
/// view's own (`.local`) or the window's (`.global`). A named space is measured as the view's
/// own, as the drag gesture's are here.
@MainActor @preconcurrency
public struct UIGestureRecognizerRepresentableCoordinateSpaceConverter {
    let frame: _HostedRecognizerFrame

    private var recognizer: UIGestureRecognizer? { frame.driver?.recognizer }
    private var pan: UIPanGestureRecognizer? { recognizer as? UIPanGestureRecognizer }

    /// The recognizer's location (its touches' centre) in the view's space.
    public var localLocation: CGPoint { location(in: .local) }

    /// A pan's translation in the view's space (nil for a recognizer with none).
    public var localTranslation: CGPoint? { translation(in: .local) }

    /// A pan's velocity in the view's space, in points per second (nil for a recognizer with none).
    public var localVelocity: CGPoint? { velocity(in: .local) }

    /// The recognizer's location in `coordinateSpace`.
    public func location(in coordinateSpace: some CoordinateSpaceProtocol) -> CGPoint {
        convert(globalPoint: recognizer?.location(in: nil) ?? .zero, to: coordinateSpace)
    }

    /// A pan's translation (nil for other recognizers). A translation has no origin, so it is
    /// the same in every space here, where spaces differ only by an offset.
    public func translation(in coordinateSpace: some CoordinateSpaceProtocol) -> CGPoint? {
        pan?.translation(in: nil)
    }

    /// A pan's velocity in points per second (nil for other recognizers), the same in every
    /// space for the same reason.
    public func velocity(in coordinateSpace: some CoordinateSpaceProtocol) -> CGPoint? {
        pan?.velocity(in: nil)
    }

    /// A point in the window's space in `coordinateSpace`.
    public func convert(globalPoint: CGPoint, to coordinateSpace: some CoordinateSpaceProtocol = .local) -> CGPoint {
        guard !coordinateSpace.coordinateSpace.isGlobal else { return globalPoint }
        let origin = frame.driver?.frame.origin ?? .zero
        return CGPoint(x: globalPoint.x - origin.x, y: globalPoint.y - origin.y)
    }
}

/// The driver a converter reads, set once the recognizer exists (the coordinator, which gets
/// the converter, is made before it).
@MainActor
final class _HostedRecognizerFrame {
    var driver: HostedGestureRecognizerDriver?
}

extension View {
    /// Adds a UIKit gesture recognizer to the view.
    nonisolated public func gesture(_ representable: some UIGestureRecognizerRepresentable) -> some View {
        modifier(_UIGestureRecognizerRepresentableModifier(representable: representable))
    }
}

/// Keeps the recognizer for the view's life and hands the SwiftUI gesture system a gesture
/// that forwards the view's presses to it.
struct _UIGestureRecognizerRepresentableModifier<Representable: UIGestureRecognizerRepresentable>: ViewModifier {
    nonisolated(unsafe) let representable: Representable
    @State private var box = _HostedRecognizerBox()

    /// Made where `gesture(_:)` is, outside the main actor, as Apple's modifiers are.
    nonisolated init(representable: Representable) {
        self.representable = representable
    }

    func body(content: Content) -> some View {
        let host: _HostedRecognizer<Representable>
        if let existing = box.host as? _HostedRecognizer<Representable> {
            host = existing
        } else {
            host = _HostedRecognizer()
            box.host = host
        }
        host.representable = representable
        return content.gesture(_HostedRecognizerGesture(host: host))
    }
}

/// Holds the view's `_HostedRecognizer` across updates; made outside the main actor, as a
/// modifier's state is, so it starts empty and the first body fills it.
final class _HostedRecognizerBox: @unchecked Sendable {
    var host: AnyObject?
    init() {}
}

/// The representable's coordinator and recognizer, made on the first update.
@MainActor
final class _HostedRecognizer<Representable: UIGestureRecognizerRepresentable> {
    var representable: Representable?
    let frame = _HostedRecognizerFrame()
    private var coordinator: Representable.Coordinator?
    private var recognizer: Representable.UIGestureRecognizerType?
    /// The SwiftUI recogniser of the press in flight, told when the UIKit one begins and ends.
    weak var forwarder: _HostedRecognizerForwarder?

    var driver: HostedGestureRecognizerDriver? { frame.driver }

    private func context(_ coordinator: Representable.Coordinator) -> Representable.Context {
        Representable.Context(coordinator: coordinator, converter: UIGestureRecognizerRepresentableCoordinateSpaceConverter(frame: frame))
    }

    /// Makes the coordinator and recognizer the first time, then updates the recognizer.
    func update() {
        guard let representable else { return }
        if let recognizer, let coordinator {
            representable.updateUIGestureRecognizer(recognizer, context: context(coordinator))
            return
        }
        let coordinator = representable.makeCoordinator(converter: UIGestureRecognizerRepresentableCoordinateSpaceConverter(frame: frame))
        self.coordinator = coordinator
        let recognizer = representable.makeUIGestureRecognizer(context: context(coordinator))
        self.recognizer = recognizer
        frame.driver = HostedGestureRecognizerDriver(recognizer)
        recognizer.addTarget { [weak self] _ in self?.recognizerActed() }
        representable.updateUIGestureRecognizer(recognizer, context: context(coordinator))
    }

    private func recognizerActed() {
        guard let representable, let recognizer, let coordinator else { return }
        let state = recognizer.state
        representable.handleUIGestureRecognizerAction(recognizer, context: context(coordinator))
        forwarder?.recognizerChanged(to: state)
    }
}

/// The SwiftUI gesture standing for the representable.
struct _HostedRecognizerGesture<Representable: UIGestureRecognizerRepresentable>: Gesture {
    typealias Value = Void
    typealias Body = Never
    let host: _HostedRecognizer<Representable>
    var body: Never { fatalError() }

    @MainActor func _makeRecognizer() -> _GestureRecognizer<Void> {
        host.update()
        return _HostedRecognizerForwarder(driver: { [host] in host.driver }, attach: { [host] in host.forwarder = $0 })
    }
}

/// Forwards the view's presses to the driver, in window coordinates; active while the UIKit
/// recognizer has begun.
@MainActor
final class _HostedRecognizerForwarder: _GestureRecognizer<Void> {
    private let driver: @MainActor () -> HostedGestureRecognizerDriver?
    private let attach: @MainActor (_HostedRecognizerForwarder) -> Void

    init(driver: @escaping @MainActor () -> HostedGestureRecognizerDriver?, attach: @escaping @MainActor (_HostedRecognizerForwarder) -> Void) {
        self.driver = driver
        self.attach = attach
    }

    private func windowPoint(_ event: GestureEvent) -> CGPoint {
        CGPoint(x: event.location.x + event.windowOrigin.x, y: event.location.y + event.windowOrigin.y)
    }

    override func began(_ event: GestureEvent) {
        finish()
        guard let driver = driver() else { return }
        attach(self)
        driver.frame.origin = event.windowOrigin
        driver.began(at: windowPoint(event), time: event.time)
    }

    override func moved(_ event: GestureEvent) {
        driver()?.moved(to: windowPoint(event), time: event.time)
    }

    override func ended(_ event: GestureEvent, inside: Bool) {
        driver()?.ended(at: windowPoint(event), time: event.time)
        finish()
    }

    override func cancel() {
        driver()?.cancel()
        finish()
    }

    /// The UIKit recognizer's action: began or changed make the gesture active, ended ends it,
    /// cancelled forgets it.
    func recognizerChanged(to state: UIGestureRecognizer.State) {
        switch state {
        case .began, .changed: if phase != .active { emitChanged(()) }
        case .ended: emitEnded(())
        case .cancelled: fail()
        default: break
        }
    }
}
