// Drag and drop (uk-dragdrop, Docs/elements/DragDrop.md): `UIDragInteraction` lifts a view's
// drag items on a long press (a finger) or a short travel (a pointer) and the scene carries the
// session: the lifted view's layer painted at 0.8 opacity under the pointer, the deepest
// `UIDropInteraction` (or table / collection drop delegate) under the pointer that can handle
// the session targeted and asked for its proposal, the drop performed on release. The host's
// external entry points (`HostedScene`, sw-dragdrop-os) carry a session across the app
// boundary the same way SwiftUI's runtime does: the items' providers become MIME items.
#if !os(WASI)
import Foundation
#endif
import WebFoundation   // Foundation everywhere, and the NSItemProvider stand-in where ObjectiveC is absent (wasm, Linux)

/// What a drop does with the items.
public enum UIDropOperation: UInt, Sendable { case cancel = 0, forbidden, copy, move }

/// One item of a drag: its provider and, for the app's own drags, a local object.
@MainActor
public final class UIDragItem {
    public let itemProvider: NSItemProvider
    public var localObject: Any?
    public var previewProvider: (() -> UIDragPreview?)?

    /// A value a provider gave for a type.
    enum Loaded: Sendable {
        case text(String), url(URL), data(Data)
        var text: String? {
            switch self {
            case .text(let text): return text
            case .data(let data): return String(decoding: data, as: UTF8.self)
            case .url(let url): return url.absoluteString
            }
        }
    }
    /// The providers' values by type: WebFoundation's stand-in gives them at once; Foundation's
    /// load on a queue of their own, so the item fetches them as it is made and the drop (a
    /// user's gesture later) finds them here.
    private var loaded: [String: Loaded] = [:]

    public init(itemProvider: NSItemProvider) {
        self.itemProvider = itemProvider
        #if canImport(Darwin)
        for type in itemProvider.registeredTypeIdentifiers {
            itemProvider.loadItem(forTypeIdentifier: type, options: nil) { value, _ in
                let converted: Loaded?
                switch value {
                case let text as NSString: converted = .text(text as String)
                case let url as NSURL: converted = .url(url as URL)
                case let data as NSData: converted = .data(data as Data)
                default: converted = nil
                }
                guard let converted else { return }
                Task { @MainActor in self.loaded[type] = converted }
            }
        }
        #endif
    }

    /// A value known up front (tests, and hosts that bring items in).
    func _preload(_ value: Loaded, forTypeIdentifier type: String) { loaded[type] = value }
    /// The item's text, known up front: Foundation's providers load on a queue of their own,
    /// so an app on a native host that needs the string at once (a system drag starting in the
    /// same event) can say what it is.
    public func _preloadText(_ text: String) { loaded["public.utf8-plain-text"] = .text(text) }

    /// The value for a type, once it has loaded.
    func value(forTypeIdentifier type: String) -> Loaded? {
        if let value = loaded[type] { return value }
        #if !canImport(Darwin)
        var result: Loaded?
        itemProvider.loadItem(forTypeIdentifier: type, options: nil) { value, _ in
            switch value {
            case let text as String: result = .text(text)
            case let url as URL: result = .url(url)
            case let data as Data: result = .data(data)
            default: break
            }
        }
        if let result { loaded[type] = result }
        return result
        #else
        return nil
        #endif
    }

    nonisolated static let textTypes: Set<String> = ["public.utf8-plain-text", "public.plain-text", "public.text"]

    /// The string the item can give, if any (its text type's value; a URL's string).
    public var text: String? {
        for type in itemProvider.registeredTypeIdentifiers where Self.textTypes.contains(type) {
            if let value = value(forTypeIdentifier: type) { return value.text }
        }
        return nil
    }

    /// Whether the item can give a string (a text type registered).
    var canLoadText: Bool { itemProvider.registeredTypeIdentifiers.contains(where: Self.textTypes.contains) }

    /// The item for the host's system drag: a text provider as plain text, a URL as a URI list,
    /// anything else as its bytes under its type.
    var externalItems: [ExternalDragItem] {
        var items: [ExternalDragItem] = []
        for type in itemProvider.registeredTypeIdentifiers {
            guard let value = value(forTypeIdentifier: type) else { continue }
            switch value {
            case .url(let url): items.append(ExternalDragItem(type: "text/uri-list", text: url.absoluteString))
            case .text(let text) where Self.textTypes.contains(type): items.append(ExternalDragItem(type: "text/plain", text: text))
            case .data(let data) where Self.textTypes.contains(type): items.append(ExternalDragItem(type: "text/plain", text: String(decoding: data, as: UTF8.self)))
            case .data(let data) where type == "public.url": items.append(ExternalDragItem(type: "text/uri-list", text: String(decoding: data, as: UTF8.self)))
            case .text(let text): items.append(ExternalDragItem(type: type, text: text))
            case .data(let data): items.append(ExternalDragItem(type: type, data: data))
            }
        }
        return items
    }

    /// A drag item from an item the host brought in (`text/plain` registers as plain text,
    /// `text/uri-list` as a URL, anything else under its own type).
    convenience init(external item: ExternalDragItem) {
        self.init(itemProvider: NSItemProvider._make(external: item))
        switch item.type {
        case "text/plain": loaded["public.utf8-plain-text"] = .text(item.text ?? "")
        case "text/uri-list": if let url = URL(string: item.text ?? "") { loaded["public.url"] = .url(url) }
        default:
            if let text = item.text { loaded[item.type] = .text(text) } else if let data = item.data { loaded[item.type] = .data(data) }
        }
    }
}

extension NSItemProvider {
    #if canImport(Darwin)
    static func _make(external item: ExternalDragItem) -> NSItemProvider {
        switch item.type {
        case "text/plain": return NSItemProvider(object: (item.text ?? "") as NSString)
        case "text/uri-list": return NSItemProvider(object: (URL(string: item.text ?? "") ?? URL(fileURLWithPath: "/")) as NSURL)
        default:
            if let text = item.text { return NSItemProvider(item: text as NSString, typeIdentifier: item.type) }
            return NSItemProvider(item: (item.data ?? Data()) as NSData, typeIdentifier: item.type)
        }
    }
    #else
    static func _make(external item: ExternalDragItem) -> NSItemProvider {
        let provider = NSItemProvider()
        switch item.type {
        case "text/plain": provider.registerItem(item.text ?? "", typeIdentifier: "public.utf8-plain-text")
        case "text/uri-list": provider.registerItem(URL(string: item.text ?? "") as Any, typeIdentifier: "public.url")
        default:
            if let text = item.text { provider.registerItem(text, typeIdentifier: item.type) }
            else if let data = item.data { provider.registerItem(data, typeIdentifier: item.type) }
        }
        return provider
    }
    #endif
}

/// The preview a drag shows: a view painted under the pointer.
@MainActor
public final class UIDragPreview {
    public let view: UIView
    public let parameters: UIDragPreviewParameters
    public init(view: UIView, parameters: UIDragPreviewParameters = UIDragPreviewParameters()) {
        self.view = view
        self.parameters = parameters
    }
}

public struct UIDragPreviewParameters: Sendable {
    public var backgroundColor: UIColor?
    public var visiblePath: UIBezierPath?
    public init() {}
}

/// What a drag and a drop session have in common: the items and where the pointer is.
@MainActor
public protocol UIDragDropSession: AnyObject {
    var items: [UIDragItem] { get }
    func location(in view: UIView) -> CGPoint
    var allowsMoveOperation: Bool { get }
    var isRestrictedToDraggingApplication: Bool { get }
    func hasItemsConforming(toTypeIdentifiers typeIdentifiers: [String]) -> Bool
    /// Whether every item can give a string (the only object class the stand-in providers load).
    func canLoadObjects(ofClass aClass: String.Type) -> Bool
}

/// The source side of a drag.
@MainActor
public protocol UIDragSession: UIDragDropSession {
    var localContext: Any? { get set }
}

/// The destination side: the session as a drop target sees it.
@MainActor
public protocol UIDropSession: UIDragDropSession {
    /// The app's own drag behind the drop, nil for one from outside.
    var localDragSession: (any UIDragSession)? { get }
    var progressIndicatorStyle: UIDropSessionProgressIndicatorStyle { get set }
    /// Loads every item's string and hands them over at once (the providers are synchronous).
    func loadObjects(ofClass aClass: String.Type, completion: @escaping ([String]) -> Void)
}

public struct UIDropSessionProgressIndicatorStyle: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let none = UIDropSessionProgressIndicatorStyle([])
    public static let `default` = UIDropSessionProgressIndicatorStyle(rawValue: 1)
}

/// The proposal a drop interaction's delegate answers while a session is over its view.
@MainActor
open class UIDropProposal {
    public let operation: UIDropOperation
    public var isPrecise = false
    public var prefersFullSizePreview = false
    public init(operation: UIDropOperation) { self.operation = operation }
}

/// The scene's session: both sides of a drag, local or from outside.
@MainActor
final class DragDropSession: UIDragSession, UIDropSession {
    var items: [UIDragItem]
    var localContext: Any?
    let isExternal: Bool
    var location = CGPoint.zero
    var allowsMoveOperation = true
    var isRestrictedToDraggingApplication = false
    var progressIndicatorStyle: UIDropSessionProgressIndicatorStyle = .default
    /// The view (or table / collection) the drag began in.
    weak var sourceView: UIView?
    /// The lifted view painted under the pointer, and where it was grabbed.
    weak var preview: UIView?
    var previewLayer: CALayer?
    var grab = CGPoint.zero
    /// The receiver currently targeted, and its last proposal.
    var target: (any _DropReceiver)?
    var proposal: UIDropOperation = .cancel
    /// Whether the host's system drag carries the session (its own pointer events stop).
    var isSystemDrag = false
    /// The window the session's points are in (a hosted tree's, or the scene's frontmost).
    weak var window: UIWindow?

    init(items: [UIDragItem], isExternal: Bool) {
        self.items = items
        self.isExternal = isExternal
    }

    var localDragSession: (any UIDragSession)? { isExternal ? nil : self }

    func location(in view: UIView) -> CGPoint { view.convert(location, from: nil) }

    func hasItemsConforming(toTypeIdentifiers typeIdentifiers: [String]) -> Bool {
        items.contains { item in typeIdentifiers.contains { item.itemProvider.hasItemConformingToTypeIdentifier($0) } }
    }

    func canLoadObjects(ofClass aClass: String.Type) -> Bool { !items.isEmpty && items.allSatisfy(\.canLoadText) }

    func loadObjects(ofClass aClass: String.Type, completion: @escaping ([String]) -> Void) {
        completion(items.compactMap(\.text))
    }

    var externalItems: [ExternalDragItem] { items.flatMap(\.externalItems) }
}

// MARK: - Interactions

/// The methods a drag interaction's delegate implements to provide the items and hear of the session.
@MainActor
public protocol UIDragInteractionDelegate: AnyObject {
    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: any UIDragSession) -> [UIDragItem]
    func dragInteraction(_ interaction: UIDragInteraction, previewForLifting item: UIDragItem, session: any UIDragSession) -> UIDragPreview?
    func dragInteraction(_ interaction: UIDragInteraction, sessionWillBegin session: any UIDragSession)
    func dragInteraction(_ interaction: UIDragInteraction, session: any UIDragSession, didEndWith operation: UIDropOperation)
    func dragInteraction(_ interaction: UIDragInteraction, sessionAllowsMoveOperation session: any UIDragSession) -> Bool
    func dragInteraction(_ interaction: UIDragInteraction, sessionIsRestrictedToDraggingApplication session: any UIDragSession) -> Bool
}

extension UIDragInteractionDelegate {
    public func dragInteraction(_ interaction: UIDragInteraction, previewForLifting item: UIDragItem, session: any UIDragSession) -> UIDragPreview? { nil }
    public func dragInteraction(_ interaction: UIDragInteraction, sessionWillBegin session: any UIDragSession) {}
    public func dragInteraction(_ interaction: UIDragInteraction, session: any UIDragSession, didEndWith operation: UIDropOperation) {}
    public func dragInteraction(_ interaction: UIDragInteraction, sessionAllowsMoveOperation session: any UIDragSession) -> Bool { true }
    public func dragInteraction(_ interaction: UIDragInteraction, sessionIsRestrictedToDraggingApplication session: any UIDragSession) -> Bool { false }
}

/// Lets a view start drags: a long press (0.5 s, a finger) or a 4 pt travel (a pointer)
/// asks the delegate for items and lifts them.
@MainActor
public final class UIDragInteraction: UIInteraction {
    public weak var delegate: (any UIDragInteractionDelegate)?
    public var isEnabled = true
    public var allowsSimultaneousRecognitionDuringLift = false
    public private(set) weak var view: UIView?
    private var recognizer: _DragLiftGestureRecognizer?

    public init(delegate: any UIDragInteractionDelegate) { self.delegate = delegate }

    public func willMove(to view: UIView?) {
        if let recognizer, let old = self.view { old.removeGestureRecognizer(recognizer) }
        recognizer = nil
    }

    public func didMove(to view: UIView?) {
        self.view = view
        guard let view else { return }
        let lift = _DragLiftGestureRecognizer()
        lift.addTarget { [weak self] recognizer in self?.handle(recognizer) }
        view.addGestureRecognizer(lift)
        recognizer = lift
    }

    /// The items for a drag starting at `point` (window coordinates); empty when the view
    /// cannot start one.
    func items(for session: DragDropSession) -> [UIDragItem] {
        guard isEnabled, let delegate else { return [] }
        return delegate.dragInteraction(self, itemsForBeginning: session)
    }

    private func handle(_ recognizer: UIGestureRecognizer) {
        let scene = UIKitScene.shared
        let point = recognizer.location(in: nil)
        switch recognizer.state {
        case .began:
            guard let view else { return }
            scene.beginDrag(from: view, pressedAt: (recognizer as? _DragLiftGestureRecognizer)?.startLocation ?? point, at: point)
        case .changed: scene.updateDrag(to: point)
        case .ended: scene.endDrag(at: point)
        case .cancelled, .failed: scene.cancelDrag()
        default: break
        }
    }
}

/// The methods a drop interaction's delegate implements to accept items.
@MainActor
public protocol UIDropInteractionDelegate: AnyObject {
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: any UIDropSession) -> Bool
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: any UIDropSession)
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: any UIDropSession) -> UIDropProposal
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: any UIDropSession)
    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: any UIDropSession)
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: any UIDropSession)
}

extension UIDropInteractionDelegate {
    public func dropInteraction(_ interaction: UIDropInteraction, canHandle session: any UIDropSession) -> Bool { true }
    public func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: any UIDropSession) {}
    public func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: any UIDropSession) -> UIDropProposal { UIDropProposal(operation: .cancel) }
    public func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: any UIDropSession) {}
    public func dropInteraction(_ interaction: UIDropInteraction, performDrop session: any UIDropSession) {}
    public func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: any UIDropSession) {}
}

/// Lets a view receive drops.
@MainActor
public final class UIDropInteraction: UIInteraction, _DropReceiver {
    public weak var delegate: (any UIDropInteractionDelegate)?
    public private(set) weak var view: UIView?
    public init(delegate: any UIDropInteractionDelegate) { self.delegate = delegate }
    public func didMove(to view: UIView?) { self.view = view }

    var receiverView: UIView? { view }
    func canHandle(_ session: DragDropSession) -> Bool { delegate?.dropInteraction(self, canHandle: session) ?? false }
    func sessionDidEnter(_ session: DragDropSession) { delegate?.dropInteraction(self, sessionDidEnter: session) }
    func sessionDidUpdate(_ session: DragDropSession) -> UIDropOperation { delegate?.dropInteraction(self, sessionDidUpdate: session).operation ?? .cancel }
    func sessionDidExit(_ session: DragDropSession) { delegate?.dropInteraction(self, sessionDidExit: session) }
    func performDrop(_ session: DragDropSession) { delegate?.dropInteraction(self, performDrop: session) }
    func sessionDidEnd(_ session: DragDropSession) { delegate?.dropInteraction(self, sessionDidEnd: session) }
}

/// What the scene targets: a drop interaction, or a table or collection view with a drop delegate.
@MainActor
protocol _DropReceiver: AnyObject {
    var receiverView: UIView? { get }
    func canHandle(_ session: DragDropSession) -> Bool
    func sessionDidEnter(_ session: DragDropSession)
    /// The receiver's proposal for the session at its current location.
    func sessionDidUpdate(_ session: DragDropSession) -> UIDropOperation
    func sessionDidExit(_ session: DragDropSession)
    func performDrop(_ session: DragDropSession)
    func sessionDidEnd(_ session: DragDropSession)
}

/// What the scene lifts from: a drag interaction, or a table or collection view with a drag delegate.
@MainActor
protocol _DragSourceView: AnyObject {
    func dragItems(for session: DragDropSession, at point: CGPoint) -> [UIDragItem]
    func dragSessionWillBegin(_ session: DragDropSession)
    func dragSessionDidEnd(_ session: DragDropSession, with operation: UIDropOperation)
    /// The view painted as the preview for a drag from `point`.
    func dragPreviewView(at point: CGPoint) -> UIView?
}

/// Recognizes the lift: a finger held 0.5 s within 10 pt, or a pointer that travels 4 pt.
@MainActor
final class _DragLiftGestureRecognizer: UIGestureRecognizer {
    private(set) var startLocation = CGPoint.zero
    private var timer: UIKitScene.Timer?
    private var isPointer = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first, mayBegin() else { return }
        startLocation = touch.location(in: nil)
        isPointer = touch.type == .indirectPointer
        guard !isPointer else { return }
        timer = UIKitScene.shared.schedule(after: 0.5) { [weak self] in
            guard let self, self.state == .possible else { return }
            self.transition(to: .began)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: nil)
        let travel = max(abs(location.x - startLocation.x), abs(location.y - startLocation.y))
        switch state {
        case .possible where isPointer && travel >= 4: transition(to: .began)
        case .possible where !isPointer && travel > 10: timer?.cancel(); transition(to: .failed)
        case .began, .changed: transition(to: .changed)
        default: break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        timer?.cancel()
        switch state {
        case .began, .changed: transition(to: .ended)
        default: transition(to: .failed)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        timer?.cancel()
        super.touchesCancelled(touches, with: event)
    }
}

// MARK: - The scene's session

extension UIKitScene {
    /// Whether a drag is in progress.
    public var isDragging: Bool { dragSession != nil }

    /// The window the drag's points are in: the session's source's, else the frontmost.
    var dragWindow: UIWindow? { dragSession?.sourceView?.window ?? dragSession?.window ?? windows.last(where: { !$0.isHidden }) }

    /// The drag source under `point` (window coordinates): the deepest view with a drag
    /// interaction, or a table / collection view with a drag delegate.
    func dragSource(at point: CGPoint, in window: UIWindow? = nil) -> (UIView, any _DragSourceView)? {
        guard let window = window ?? windows.last(where: { !$0.isHidden }), let hit = window.hitTest(window.convert(point, from: nil), with: nil) else { return nil }
        var view: UIView? = hit
        while let current = view {
            if let interaction = current.interactions.compactMap({ $0 as? UIDragInteraction }).first(where: { $0.isEnabled }) { return (current, interaction) }
            if let source = current as? any _DragSourceView { return (current, source) }
            view = current.superview
        }
        return nil
    }

    /// The receiver under `point` that can handle `session`.
    func dropReceiver(at point: CGPoint, for session: DragDropSession) -> (any _DropReceiver)? {
        guard let window = dragWindow, let hit = window.hitTest(window.convert(point, from: nil), with: nil) else { return nil }
        var view: UIView? = hit
        while let current = view {
            for interaction in current.interactions.compactMap({ $0 as? UIDropInteraction }) where interaction.canHandle(session) { return interaction }
            if let receiver = current as? any _DropReceiver, receiver.canHandle(session) { return receiver }
            view = current.superview
        }
        return nil
    }

    /// Lifts the items of `view`'s source, pressed at `start`, with the pointer at `point`.
    func beginDrag(from view: UIView, pressedAt start: CGPoint, at point: CGPoint) {
        guard dragSession == nil else { return }
        let source: any _DragSourceView
        if let interaction = view.interactions.compactMap({ $0 as? UIDragInteraction }).first(where: { $0.isEnabled }) {
            source = interaction
        } else if let sourceView = view as? any _DragSourceView {
            source = sourceView
        } else {
            return
        }
        let session = DragDropSession(items: [], isExternal: false)
        session.location = start
        session.sourceView = view
        session.window = view.window
        let items = source.dragItems(for: session, at: start)
        guard !items.isEmpty else { return }
        session.items = items
        if let interaction = source as? UIDragInteraction, let delegate = interaction.delegate {
            session.allowsMoveOperation = delegate.dragInteraction(interaction, sessionAllowsMoveOperation: session)
            session.isRestrictedToDraggingApplication = delegate.dragInteraction(interaction, sessionIsRestrictedToDraggingApplication: session)
        }
        dragSession = session
        let preview = source.dragPreviewView(at: start) ?? view
        session.preview = preview
        session.previewLayer = preview.layer
        let origin = preview.convert(CGPoint.zero, to: nil)
        session.grab = CGPoint(x: start.x - origin.x, y: start.y - origin.y)
        source.dragSessionWillBegin(session)
        updateDrag(to: point)
    }

    func updateDrag(to point: CGPoint) {
        guard let session = dragSession else { return }
        session.location = point
        let receiver = dropReceiver(at: point, for: session)
        if receiver !== session.target {
            session.target?.sessionDidExit(session)
            session.target = receiver
            receiver?.sessionDidEnter(session)
        }
        session.proposal = receiver?.sessionDidUpdate(session) ?? .cancel
        setNeedsFrame()
    }

    /// Drops at `point`: the targeted receiver performs the drop when its proposal allows;
    /// returns whether it took the items.
    @discardableResult
    func endDrag(at point: CGPoint) -> Bool {
        guard let session = dragSession else { return false }
        session.location = point
        dragSession = nil
        // The source hears the target's proposal (a forbidden one as forbidden), cancel
        // without a target.
        var operation = UIDropOperation.cancel
        if let target = session.target {
            operation = session.proposal
            if session.proposal == .copy || session.proposal == .move { target.performDrop(session) }
            target.sessionDidEnd(session)
        }
        (session.sourceView as? any _DragSourceView ?? session.sourceView?.interactions.compactMap { $0 as? UIDragInteraction }.first)?.dragSessionDidEnd(session, with: operation)
        setNeedsFrame()
        return operation != .cancel && operation != .forbidden
    }

    /// Cancels the drag in flight: the target is released, nothing is delivered.
    func cancelDrag() {
        guard let session = dragSession else { return }
        dragSession = nil
        session.target?.sessionDidExit(session)
        session.target?.sessionDidEnd(session)
        (session.sourceView as? any _DragSourceView ?? session.sourceView?.interactions.compactMap { $0 as? UIDragInteraction }.first)?.dragSessionDidEnd(session, with: .cancel)
        setNeedsFrame()
    }

    /// Paints the lifted view under the pointer at 0.8 opacity, over everything (the system
    /// draws its own image while it carries the drag).
    func paintDragPreview(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        guard let session = dragSession, !session.isSystemDrag, let layer = session.previewLayer else { return }
        let frame = CGRect(origin: CGPoint(x: session.location.x - session.grab.x, y: session.location.y - session.grab.y), size: layer.bounds.size)
        list.append(.beginGroup(opacity: 0.8))
        // The layer paints at its own frame in its superlayer's space: a context whose origin
        // puts that frame at `frame`.
        let child = PaintContext(origin: CGPoint(x: context.origin.x + frame.minX - layer.frame.minX, y: context.origin.y + frame.minY - layer.frame.minY), scale: context.scale)
        layer.paint(into: &list, context: child, style: style)
        list.append(.endGroup)
    }

    // MARK: Across the app boundary (sw-dragdrop-os)

    public func hasDragSource(at point: CGPoint) -> Bool { dragSource(at: point) != nil }
    public func externalDragItems() -> [ExternalDragItem] {
        guard let session = dragSession, !session.isExternal else { return [] }
        return session.externalItems
    }
    public func beginExternalDrag(at point: CGPoint) -> [ExternalDragItem] { beginExternalDrag(at: point, in: nil) }
    public func externalDragUpdated(types: [String], at point: CGPoint) -> Bool { externalDragUpdated(types: types, at: point, in: nil) }
    @discardableResult
    public func externalDrop(items: [ExternalDragItem], at point: CGPoint) -> Bool { externalDrop(items: items, at: point, in: nil) }

    /// The host's system drag is starting from the pressed source: the items lift now.
    func beginExternalDrag(at point: CGPoint, in window: UIWindow?) -> [ExternalDragItem] {
        if dragSession == nil, let (view, _) = dragSource(at: point, in: window) {
            beginDrag(from: view, pressedAt: point, at: point)
        }
        guard let session = dragSession, !session.isExternal else { return [] }
        session.isSystemDrag = true
        return session.externalItems
    }

    /// A system drag over `point`: the app's own session follows it; a drag from outside opens
    /// a session of its announced types. Returns whether a receiver is targeted.
    func externalDragUpdated(types: [String], at point: CGPoint, in window: UIWindow?) -> Bool {
        if dragSession == nil || (dragSession?.isExternal == true && dragSession?.items.flatMap(\.externalItems).map(\.type) != types) {
            let session = DragDropSession(items: types.map { UIDragItem(external: ExternalDragItem(type: $0, text: $0.hasPrefix("text/") ? "" : nil)) }, isExternal: true)
            session.isSystemDrag = true
            session.window = window
            dragSession = session
        }
        updateDrag(to: point)
        return dragSession?.target != nil && (dragSession?.proposal == .copy || dragSession?.proposal == .move)
    }

    public func externalDragExited() {
        guard let session = dragSession else { return }
        if session.isExternal {
            cancelDrag()
        } else {
            session.target?.sessionDidExit(session)
            session.target = nil
            session.proposal = .cancel
            setNeedsFrame()
        }
    }

    @discardableResult
    func externalDrop(items: [ExternalDragItem], at point: CGPoint, in window: UIWindow?) -> Bool {
        if let session = dragSession, session.isExternal {
            session.items = items.map { UIDragItem(external: $0) }
        } else if dragSession == nil {
            let session = DragDropSession(items: items.map { UIDragItem(external: $0) }, isExternal: true)
            session.isSystemDrag = true
            session.window = window
            dragSession = session
        }
        updateDrag(to: point)
        return endDrag(at: point)
    }

    public func externalDragEnded(dropped: Bool) {
        guard dragSession != nil else { return }
        cancelDrag()
    }

    public func externalDragPreview() -> ExternalDragPreview? {
        guard let session = dragSession, let layer = session.previewLayer else { return nil }
        var list = DisplayList()
        list.append(.beginGroup(opacity: 0.8))
        layer.paint(into: &list, context: PaintContext(origin: CGPoint(x: -layer.frame.minX, y: -layer.frame.minY), scale: UIScreen.main.scale), style: UIScreen.main.traitCollection.userInterfaceStyle)
        list.append(.endGroup)
        return ExternalDragPreview(list: list, size: layer.bounds.size, grab: session.grab)
    }
}

extension UIDragInteraction: _DragSourceView {
    func dragItems(for session: DragDropSession, at point: CGPoint) -> [UIDragItem] { items(for: session) }
    func dragSessionWillBegin(_ session: DragDropSession) { delegate?.dragInteraction(self, sessionWillBegin: session) }
    func dragSessionDidEnd(_ session: DragDropSession, with operation: UIDropOperation) { delegate?.dragInteraction(self, session: session, didEndWith: operation) }
    func dragPreviewView(at point: CGPoint) -> UIView? {
        guard let delegate, let session = UIKitScene.shared.dragSession, let item = session.items.first else { return view }
        return delegate.dragInteraction(self, previewForLifting: item, session: session)?.view ?? item.previewProvider?()?.view ?? view
    }
}

// MARK: - Collection views

/// The methods a collection view's drag delegate implements.
@MainActor
public protocol UICollectionViewDragDelegate: AnyObject {
    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: any UIDragSession, at indexPath: IndexPath) -> [UIDragItem]
    func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: any UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem]
    func collectionView(_ collectionView: UICollectionView, dragPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters?
    func collectionView(_ collectionView: UICollectionView, dragSessionWillBegin session: any UIDragSession)
    func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: any UIDragSession)
    func collectionView(_ collectionView: UICollectionView, dragSessionAllowsMoveOperation session: any UIDragSession) -> Bool
    func collectionView(_ collectionView: UICollectionView, dragSessionIsRestrictedToDraggingApplication session: any UIDragSession) -> Bool
}

extension UICollectionViewDragDelegate {
    public func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: any UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] { [] }
    public func collectionView(_ collectionView: UICollectionView, dragPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters? { nil }
    public func collectionView(_ collectionView: UICollectionView, dragSessionWillBegin session: any UIDragSession) {}
    public func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: any UIDragSession) {}
    public func collectionView(_ collectionView: UICollectionView, dragSessionAllowsMoveOperation session: any UIDragSession) -> Bool { true }
    public func collectionView(_ collectionView: UICollectionView, dragSessionIsRestrictedToDraggingApplication session: any UIDragSession) -> Bool { false }
}

/// How a collection view's drop lands: at an index path (inserting) or into an item.
@MainActor
public final class UICollectionViewDropProposal: UIDropProposal {
    public enum Intent: Int, Sendable { case unspecified = 0, insertAtDestinationIndexPath, insertIntoDestinationIndexPath }
    public let intent: Intent
    public init(operation: UIDropOperation, intent: Intent = .unspecified) {
        self.intent = intent
        super.init(operation: operation)
    }
}

/// One item of a collection drop: its drag item and, for a reorder, where it came from.
@MainActor
public final class UICollectionViewDropItem {
    public let dragItem: UIDragItem
    public let sourceIndexPath: IndexPath?
    init(dragItem: UIDragItem, sourceIndexPath: IndexPath?) {
        self.dragItem = dragItem
        self.sourceIndexPath = sourceIndexPath
    }
}

/// The drop as the delegate performs it: the items, the destination and the moves it asks for.
@MainActor
public final class UICollectionViewDropCoordinator {
    public let items: [UICollectionViewDropItem]
    public let destinationIndexPath: IndexPath?
    public let proposal: UICollectionViewDropProposal
    public let session: any UIDropSession
    private weak var collectionView: UICollectionView?
    init(items: [UICollectionViewDropItem], destinationIndexPath: IndexPath?, proposal: UICollectionViewDropProposal, session: any UIDropSession, collectionView: UICollectionView) {
        self.items = items
        self.destinationIndexPath = destinationIndexPath
        self.proposal = proposal
        self.session = session
        self.collectionView = collectionView
    }
    /// Animates the dragged item into the cell at `indexPath` (the collection has laid out
    /// for the delegate's data change by the time the drop settles).
    @discardableResult
    public func drop(_ dragItem: UIDragItem, toItemAt indexPath: IndexPath) -> UICollectionViewDropCoordinator { self }
    public func drop(_ dragItem: UIDragItem, intoItemAt indexPath: IndexPath, rect: CGRect) {}
}

/// The methods a collection view's drop delegate implements.
@MainActor
public protocol UICollectionViewDropDelegate: AnyObject {
    func collectionView(_ collectionView: UICollectionView, canHandle session: any UIDropSession) -> Bool
    func collectionView(_ collectionView: UICollectionView, dropSessionDidEnter session: any UIDropSession)
    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: any UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal
    func collectionView(_ collectionView: UICollectionView, dropSessionDidExit session: any UIDropSession)
    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator)
    func collectionView(_ collectionView: UICollectionView, dropSessionDidEnd session: any UIDropSession)
}

extension UICollectionViewDropDelegate {
    public func collectionView(_ collectionView: UICollectionView, canHandle session: any UIDropSession) -> Bool { true }
    public func collectionView(_ collectionView: UICollectionView, dropSessionDidEnter session: any UIDropSession) {}
    public func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: any UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        UICollectionViewDropProposal(operation: session.localDragSession != nil ? .move : .copy, intent: .insertAtDestinationIndexPath)
    }
    public func collectionView(_ collectionView: UICollectionView, dropSessionDidExit session: any UIDropSession) {}
    public func collectionView(_ collectionView: UICollectionView, dropSessionDidEnd session: any UIDropSession) {}
}

extension UICollectionView: _DragSourceView, _DropReceiver {
    /// The index path a drop at the session's location lands at: the item under it, else
    /// after the last item of the section under it (the end of the last section otherwise).
    func dropDestination(for session: DragDropSession) -> IndexPath? {
        let point = session.location(in: self)
        if let path = indexPathForItem(at: point) { return path }
        let sections = numberOfSections
        guard sections > 0 else { return nil }
        for section in (0..<sections).reversed() {
            let count = numberOfItems(inSection: section)
            if count > 0, let last = layoutAttributesForItem(at: IndexPath(item: count - 1, section: section)), point.y >= last.frame.minY {
                return IndexPath(item: count, section: section)
            }
        }
        return IndexPath(item: 0, section: 0)
    }

    func dragItems(for session: DragDropSession, at point: CGPoint) -> [UIDragItem] {
        guard dragInteractionEnabled, let dragDelegate, let path = indexPathForItem(at: convert(point, from: nil)) else { return [] }
        let items = dragDelegate.collectionView(self, itemsForBeginning: session, at: path)
        if !items.isEmpty {
            draggedIndexPaths = [path]
            session.allowsMoveOperation = dragDelegate.collectionView(self, dragSessionAllowsMoveOperation: session)
            session.isRestrictedToDraggingApplication = dragDelegate.collectionView(self, dragSessionIsRestrictedToDraggingApplication: session)
        }
        return items
    }
    func dragSessionWillBegin(_ session: DragDropSession) { dragDelegate?.collectionView(self, dragSessionWillBegin: session) }
    func dragSessionDidEnd(_ session: DragDropSession, with operation: UIDropOperation) {
        draggedIndexPaths = []
        dragDelegate?.collectionView(self, dragSessionDidEnd: session)
    }
    func dragPreviewView(at point: CGPoint) -> UIView? { indexPathForItem(at: convert(point, from: nil)).flatMap(cellForItem(at:)) }

    var receiverView: UIView? { self }
    func canHandle(_ session: DragDropSession) -> Bool { dropDelegate?.collectionView(self, canHandle: session) ?? false }
    func sessionDidEnter(_ session: DragDropSession) {
        activeDropSession = session
        dropDelegate?.collectionView(self, dropSessionDidEnter: session)
    }
    func sessionDidUpdate(_ session: DragDropSession) -> UIDropOperation {
        guard let dropDelegate else { return .cancel }
        let proposal = dropDelegate.collectionView(self, dropSessionDidUpdate: session, withDestinationIndexPath: dropDestination(for: session))
        lastDropProposal = proposal
        return proposal.operation
    }
    func sessionDidExit(_ session: DragDropSession) {
        activeDropSession = nil
        dropDelegate?.collectionView(self, dropSessionDidExit: session)
    }
    func performDrop(_ session: DragDropSession) {
        guard let dropDelegate else { return }
        let proposal = lastDropProposal ?? UICollectionViewDropProposal(operation: .copy, intent: .insertAtDestinationIndexPath)
        let local = session.sourceView === self
        let items = session.items.enumerated().map { index, item in
            UICollectionViewDropItem(dragItem: item, sourceIndexPath: local && index < draggedIndexPaths.count ? draggedIndexPaths[index] : nil)
        }
        let coordinator = UICollectionViewDropCoordinator(items: items, destinationIndexPath: dropDestination(for: session), proposal: proposal, session: session, collectionView: self)
        dropDelegate.collectionView(self, performDropWith: coordinator)
    }
    func sessionDidEnd(_ session: DragDropSession) {
        activeDropSession = nil
        lastDropProposal = nil
        dropDelegate?.collectionView(self, dropSessionDidEnd: session)
    }
}

// MARK: - Table views

@MainActor
public protocol UITableViewDragDelegate: AnyObject {
    func tableView(_ tableView: UITableView, itemsForBeginning session: any UIDragSession, at indexPath: IndexPath) -> [UIDragItem]
    func tableView(_ tableView: UITableView, dragSessionWillBegin session: any UIDragSession)
    func tableView(_ tableView: UITableView, dragSessionDidEnd session: any UIDragSession)
    func tableView(_ tableView: UITableView, dragSessionAllowsMoveOperation session: any UIDragSession) -> Bool
}

extension UITableViewDragDelegate {
    public func tableView(_ tableView: UITableView, dragSessionWillBegin session: any UIDragSession) {}
    public func tableView(_ tableView: UITableView, dragSessionDidEnd session: any UIDragSession) {}
    public func tableView(_ tableView: UITableView, dragSessionAllowsMoveOperation session: any UIDragSession) -> Bool { true }
}

@MainActor
public final class UITableViewDropProposal: UIDropProposal {
    public enum Intent: Int, Sendable { case unspecified = 0, insertAtDestinationIndexPath, insertIntoDestinationIndexPath, automatic }
    public let intent: Intent
    public init(operation: UIDropOperation, intent: Intent = .unspecified) {
        self.intent = intent
        super.init(operation: operation)
    }
}

@MainActor
public final class UITableViewDropItem {
    public let dragItem: UIDragItem
    public let sourceIndexPath: IndexPath?
    init(dragItem: UIDragItem, sourceIndexPath: IndexPath?) {
        self.dragItem = dragItem
        self.sourceIndexPath = sourceIndexPath
    }
}

@MainActor
public final class UITableViewDropCoordinator {
    public let items: [UITableViewDropItem]
    public let destinationIndexPath: IndexPath?
    public let proposal: UITableViewDropProposal
    public let session: any UIDropSession
    init(items: [UITableViewDropItem], destinationIndexPath: IndexPath?, proposal: UITableViewDropProposal, session: any UIDropSession) {
        self.items = items
        self.destinationIndexPath = destinationIndexPath
        self.proposal = proposal
        self.session = session
    }
    @discardableResult
    public func drop(_ dragItem: UIDragItem, toRowAt indexPath: IndexPath) -> UITableViewDropCoordinator { self }
    public func drop(_ dragItem: UIDragItem, intoRowAt indexPath: IndexPath, rect: CGRect) {}
}

@MainActor
public protocol UITableViewDropDelegate: AnyObject {
    func tableView(_ tableView: UITableView, canHandle session: any UIDropSession) -> Bool
    func tableView(_ tableView: UITableView, dropSessionDidEnter session: any UIDropSession)
    func tableView(_ tableView: UITableView, dropSessionDidUpdate session: any UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal
    func tableView(_ tableView: UITableView, dropSessionDidExit session: any UIDropSession)
    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator)
    func tableView(_ tableView: UITableView, dropSessionDidEnd session: any UIDropSession)
}

extension UITableViewDropDelegate {
    public func tableView(_ tableView: UITableView, canHandle session: any UIDropSession) -> Bool { true }
    public func tableView(_ tableView: UITableView, dropSessionDidEnter session: any UIDropSession) {}
    public func tableView(_ tableView: UITableView, dropSessionDidUpdate session: any UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
        UITableViewDropProposal(operation: session.localDragSession != nil ? .move : .copy, intent: .insertAtDestinationIndexPath)
    }
    public func tableView(_ tableView: UITableView, dropSessionDidExit session: any UIDropSession) {}
    public func tableView(_ tableView: UITableView, dropSessionDidEnd session: any UIDropSession) {}
}

extension UITableView: _DragSourceView, _DropReceiver {
    /// The row a drop at the session's location lands at: the row under it, else after the
    /// last row of the section under it.
    func dropDestination(for session: DragDropSession) -> IndexPath? {
        let point = session.location(in: self)
        if let path = indexPathForRow(at: point) { return path }
        let sections = numberOfSections
        guard sections > 0 else { return nil }
        for section in (0..<sections).reversed() {
            let count = numberOfRows(inSection: section)
            if count > 0, point.y >= rectForRow(at: IndexPath(row: count - 1, section: section)).minY { return IndexPath(row: count, section: section) }
        }
        return IndexPath(row: 0, section: 0)
    }

    func dragItems(for session: DragDropSession, at point: CGPoint) -> [UIDragItem] {
        guard dragInteractionEnabled, let dragDelegate, let path = indexPathForRow(at: convert(point, from: nil)) else { return [] }
        let items = dragDelegate.tableView(self, itemsForBeginning: session, at: path)
        if !items.isEmpty {
            draggedIndexPaths = [path]
            session.allowsMoveOperation = dragDelegate.tableView(self, dragSessionAllowsMoveOperation: session)
        }
        return items
    }
    func dragSessionWillBegin(_ session: DragDropSession) { dragDelegate?.tableView(self, dragSessionWillBegin: session) }
    func dragSessionDidEnd(_ session: DragDropSession, with operation: UIDropOperation) {
        draggedIndexPaths = []
        dragDelegate?.tableView(self, dragSessionDidEnd: session)
    }
    func dragPreviewView(at point: CGPoint) -> UIView? { indexPathForRow(at: convert(point, from: nil)).flatMap(cellForRow(at:)) }

    var receiverView: UIView? { self }
    func canHandle(_ session: DragDropSession) -> Bool { dropDelegate?.tableView(self, canHandle: session) ?? false }
    func sessionDidEnter(_ session: DragDropSession) {
        activeDropSession = session
        dropDelegate?.tableView(self, dropSessionDidEnter: session)
    }
    func sessionDidUpdate(_ session: DragDropSession) -> UIDropOperation {
        guard let dropDelegate else { return .cancel }
        let proposal = dropDelegate.tableView(self, dropSessionDidUpdate: session, withDestinationIndexPath: dropDestination(for: session))
        lastDropProposal = proposal
        return proposal.operation
    }
    func sessionDidExit(_ session: DragDropSession) {
        activeDropSession = nil
        dropDelegate?.tableView(self, dropSessionDidExit: session)
    }
    func performDrop(_ session: DragDropSession) {
        guard let dropDelegate else { return }
        let proposal = lastDropProposal ?? UITableViewDropProposal(operation: .copy, intent: .insertAtDestinationIndexPath)
        let local = session.sourceView === self
        let items = session.items.enumerated().map { index, item in
            UITableViewDropItem(dragItem: item, sourceIndexPath: local && index < draggedIndexPaths.count ? draggedIndexPaths[index] : nil)
        }
        dropDelegate.tableView(self, performDropWith: UITableViewDropCoordinator(items: items, destinationIndexPath: dropDestination(for: session), proposal: proposal, session: session))
    }
    func sessionDidEnd(_ session: DragDropSession) {
        activeDropSession = nil
        lastDropProposal = nil
        dropDelegate?.tableView(self, dropSessionDidEnd: session)
    }
}
