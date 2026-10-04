// Menus (Docs/elements/UIKit/Menus.md): `UIMenu` trees of actions, submenus and deferred
// elements, shown as a floating card near their source by `MenuPresenter` for a button's
// `menu` (a tap with `showsMenuAsPrimaryAction`, a long press otherwise), a bar button item's
// menu, a `UIContextMenuInteraction`'s long press (with its preview) and a
// `UIEditMenuInteraction`'s horizontal bar. The iOS 26 card cannot be opened by the harness,
// so its geometry is approximate (not measured).

/// A container for grouping related menu elements.
@MainActor
public final class UIMenu: UIMenuElement {
    public struct Identifier: Hashable, Sendable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
    }

    public struct Options: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        /// The menu's children appear inline in the parent, separated from the rest.
        public static let displayInline = Options(rawValue: 1 << 0)
        public static let destructive = Options(rawValue: 1 << 1)
        public static let singleSelection = Options(rawValue: 1 << 5)
        public static let displayAsPalette = Options(rawValue: 1 << 7)
    }

    public enum ElementSize: Int, Sendable { case small = 0, medium, large, automatic }

    public let identifier: Identifier
    public var options: Options
    public var preferredElementSize: ElementSize
    public var children: [UIMenuElement]

    public init(title: String = "", subtitle: String? = nil, image: UIImage? = nil, identifier: Identifier? = nil, options: Options = [],
                preferredElementSize: ElementSize = .automatic, children: [UIMenuElement] = []) {
        self.identifier = identifier ?? Identifier("UIMenu-\(UIMenu.counter)")
        UIMenu.counter += 1
        self.options = options
        self.preferredElementSize = preferredElementSize
        self.children = children
        super.init(title: title, image: image, subtitle: subtitle)
    }

    @MainActor private static var counter = 0

    /// A copy with other children.
    public func replacingChildren(_ newChildren: [UIMenuElement]) -> UIMenu {
        UIMenu(title: title, subtitle: subtitle, image: image, identifier: identifier, options: options, preferredElementSize: preferredElementSize, children: newChildren)
    }

    /// Every action in the tree, submenus included.
    public var flattenedActions: [UIAction] {
        children.flatMap { element -> [UIAction] in
            if let action = element as? UIAction { return [action] }
            if let menu = element as? UIMenu { return menu.flattenedActions }
            if let deferred = element as? UIDeferredMenuElement { return deferred.resolved.flatMap { ($0 as? UIAction).map { [$0] } ?? ($0 as? UIMenu)?.flattenedActions ?? [] } }
            return []
        }
    }
}

/// A menu element whose children a provider supplies when the menu is shown (the provider's
/// completion is expected at once; a later one shows nothing).
@MainActor
public final class UIDeferredMenuElement: UIMenuElement {
    public typealias Provider = (@escaping ([UIMenuElement]) -> Void) -> Void
    let provider: Provider
    let cached: Bool
    private var cache: [UIMenuElement]?

    public init(_ elementProvider: @escaping Provider) {
        provider = elementProvider
        cached = true
        super.init()
    }

    private init(provider: @escaping Provider, cached: Bool) {
        self.provider = provider
        self.cached = cached
        super.init()
    }

    public static func uncached(_ elementProvider: @escaping Provider) -> UIDeferredMenuElement { UIDeferredMenuElement(provider: elementProvider, cached: false) }

    /// The elements the provider delivered (at once), cached unless `uncached`.
    var resolved: [UIMenuElement] {
        if cached, let cache { return cache }
        var elements: [UIMenuElement] = []
        provider { elements = $0 }
        if cached { cache = elements }
        return elements
    }
}

// MARK: - Presentation

/// Opens menu cards and edit menus over the window and closes them.
@MainActor
enum MenuPresenter {
    static let longPressDuration = 0.5

    /// Presents `menu` near `source` (a control or any view); `onAction` hears the action chosen.
    static func present(_ menu: UIMenu, from source: UIView, preview: UIView? = nil, at point: CGPoint? = nil, onAction: ((UIAction) -> Void)? = nil) {
        guard let window = source.window else { return }
        let presenter = window.rootViewController?.topmostPresented ?? window.rootViewController
        guard let presenter, presenter.presentedViewController == nil else { return }
        let controller = MenuPanelController(menu: menu, source: source, preview: preview, point: point, onAction: onAction)
        presenter.present(controller, animated: false)
    }

    // MARK: Context menu long presses (TouchRouter)

    private static var pendingTimer: UIKitScene.Timer?
    private static var pendingStart = CGPoint.zero
    private static weak var pendingTouch: UITouch?
    private static var presentedForTouch = false

    /// A touch landed: a view with a context menu interaction in the hit chain arms a long press.
    static func touchBegan(_ touch: UITouch, hit: UIView?) {
        pendingTimer?.cancel()
        pendingTimer = nil
        presentedForTouch = false
        var view = hit
        var found: (UIView, UIContextMenuInteraction)?
        while let v = view, found == nil {
            if let interaction = v.interactions.compactMap({ $0 as? UIContextMenuInteraction }).first { found = (v, interaction) }
            view = v.superview
        }
        guard let (owner, interaction) = found else { return }
        pendingStart = touch.location(in: nil)
        pendingTouch = touch
        pendingTimer = UIKitScene.shared.schedule(after: longPressDuration) { [weak owner, weak interaction] in
            guard let owner, let interaction, pendingTouch === touch else { return }
            pendingTimer = nil
            let location = touch.location(in: owner)
            guard let configuration = interaction.delegate?.contextMenuInteraction(interaction, configurationForMenuAtLocation: location) else { return }
            presentedForTouch = true
            touch.view?.touchesCancelled([touch], with: UIEvent(type: .touches, timestamp: touch.timestamp))
            interaction.present(configuration, from: owner, at: location)
        }
    }

    static func touchMoved(_ touch: UITouch) {
        guard pendingTimer != nil, pendingTouch === touch else { return }
        let location = touch.location(in: nil)
        if abs(location.x - pendingStart.x) > 10 || abs(location.y - pendingStart.y) > 10 { pendingTimer?.cancel(); pendingTimer = nil }
    }

    /// Returns whether the touch was taken by a context menu (the view's touch is cancelled).
    static func touchEnded(_ touch: UITouch) -> Bool {
        pendingTimer?.cancel()
        pendingTimer = nil
        let taken = presentedForTouch && pendingTouch === touch
        presentedForTouch = false
        pendingTouch = nil
        return taken
    }
}

extension UIViewController {
    /// The last controller in the presentation chain from this one.
    var topmostPresented: UIViewController {
        var controller = self
        while let next = controller.presentedViewController { controller = next }
        return controller
    }
}

/// The controller behind a menu card (presented with the custom style; the container lays it
/// out beside its source through `layoutPanel`).
@MainActor
final class MenuPanelController: UIViewController {
    let menu: UIMenu
    private(set) weak var source: UIView?
    let preview: UIView?
    let point: CGPoint?
    let onAction: ((UIAction) -> Void)?
    /// The edit menu's bar instead of a card.
    var isEditMenu = false
    private(set) var panel: MenuPanelView!

    init(menu: UIMenu, source: UIView, preview: UIView?, point: CGPoint?, onAction: ((UIAction) -> Void)?) {
        self.menu = menu
        self.source = source
        self.preview = preview
        self.point = point
        self.onAction = onAction
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .custom
    }

    override func loadView() {
        let panel = MenuPanelView(controller: self)
        self.panel = panel
        view = panel
    }

    /// The source's frame in the container.
    func sourceFrame(in container: UIView) -> CGRect {
        guard let source, source.window != nil else { return CGRect(x: container.bounds.midX, y: container.bounds.midY, width: 0, height: 0) }
        if let point { return CGRect(origin: source.convert(point, to: container), size: .zero) }
        return source.convert(source.bounds, to: container)
    }

    /// Places the card under its source (above it when there is no room), 6 from it and 10 from
    /// the container's edges; a context menu's preview sits above the card; the edit menu's bar
    /// floats above its point.
    func layoutPanel(in container: UIView) {
        let bounds = container.bounds
        let source = sourceFrame(in: container)
        let size = panel.sizeThatFits(CGSize(width: bounds.width - 20, height: bounds.height - 20))
        var x = isEditMenu ? source.midX - size.width / 2 : (source.minX + size.width <= bounds.width - 10 ? source.minX : source.maxX - size.width)
        x = min(max(x, 10), max(10, bounds.width - 10 - size.width))
        var previewFrame = CGRect.null
        if let preview {
            let previewSize = preview.bounds.size == .zero ? CGSize(width: 250, height: 150) : preview.bounds.size
            previewFrame = CGRect(x: x, y: 0, width: min(previewSize.width, bounds.width - 20), height: previewSize.height)
        }
        let stack = size.height + (preview == nil ? 0 : previewFrame.height + MenuPanelView.previewGap)
        var y: CGFloat
        if isEditMenu {
            y = source.minY - MenuPanelView.gap - size.height
            if y < 10 { y = source.maxY + MenuPanelView.gap }
        } else if source.maxY + MenuPanelView.gap + stack <= bounds.height - 10 || source.minY - MenuPanelView.gap - stack < 10 {
            y = min(source.maxY + MenuPanelView.gap, bounds.height - 10 - stack)
            if preview != nil { previewFrame.origin.y = y; y += previewFrame.height + MenuPanelView.previewGap }
        } else {
            y = source.minY - MenuPanelView.gap - size.height
            if preview != nil { previewFrame.origin.y = y - MenuPanelView.previewGap - previewFrame.height }
        }
        panel.frame = CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
        if let preview {
            if preview.superview !== container { container.insertSubview(preview, belowSubview: panel) }
            preview.frame = previewFrame.integral
            preview.layer.cornerRadius = 20
            preview.clipsToBounds = true
        }
    }

    /// An action chosen: the menu closes, the handler and the presenter's callback run.
    func choose(_ action: UIAction) {
        onAction?(action)
        dismiss(animated: false) { action.perform(sender: self.source) }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        preview?.removeFromSuperview()
    }
}

/// The card: a glass panel of rows (44 pt, a 17 pt title 16 in, the image trailing), thin
/// separators between rows and an 8 pt gap between inline sections, a 32 pt header for a
/// titled menu, submenu rows with a chevron that open the submenu in place, check marks for
/// `on` states, red destructive and dimmed disabled rows; the edit menu as a row of pills.
@MainActor
final class MenuPanelView: UIView {
    static let width: CGFloat = 250
    static let rowHeight: CGFloat = 44
    static let headerHeight: CGFloat = 32
    static let sectionGap: CGFloat = 8
    static let cornerRadius: CGFloat = 26
    static let gap: CGFloat = 6
    static let previewGap: CGFloat = 10
    static let editRowHeight: CGFloat = 44

    unowned let controller: MenuPanelController
    /// The submenus opened in place, innermost last.
    private var path: [UIMenu] = []
    private var rows: [Row] = []
    private var highlighted: Int?

    enum Row {
        case header(String)
        case action(UIAction)
        case submenu(UIMenu)
        case back(UIMenu)
        case gap
    }

    init(controller: MenuPanelController) {
        self.controller = controller
        super.init(frame: .zero)
        isAccessibilityElement = false
        rebuild()
    }

    var currentMenu: UIMenu { path.last ?? controller.menu }

    private func rebuild() {
        var result: [Row] = []
        let menu = currentMenu
        if let parent = path.dropLast().last ?? (path.isEmpty ? nil : controller.menu) {
            result.append(.back(parent))
        } else if !menu.title.isEmpty, !controller.isEditMenu {
            result.append(.header(menu.title))
        }
        append(menu.children, into: &result)
        rows = result
        for subview in subviews { subview.removeFromSuperview() }
        setNeedsDisplay()
    }

    private func append(_ elements: [UIMenuElement], into result: inout [Row]) {
        for element in elements {
            if let action = element as? UIAction {
                if !action.attributes.contains(.hidden) { result.append(.action(action)) }
            } else if let menu = element as? UIMenu {
                if menu.options.contains(.displayInline) {
                    if case .gap = result.last {} else if !result.isEmpty { result.append(.gap) }
                    append(menu.children, into: &result)
                    result.append(.gap)
                } else {
                    result.append(.submenu(menu))
                }
            } else if let deferred = element as? UIDeferredMenuElement {
                append(deferred.resolved, into: &result)
            }
        }
        if case .gap = result.last { result.removeLast() }
    }

    /// The rows' frames in the card (the edit menu lays its actions out side by side).
    private var rowFrames: [CGRect] {
        if controller.isEditMenu {
            var x: CGFloat = 8
            return rows.map { row in
                guard case .action(let action) = row else { return .zero }
                let width = Self.editWidth(of: action)
                let frame = CGRect(x: x, y: 0, width: width, height: Self.editRowHeight)
                x += width
                return frame
            }
        }
        var y: CGFloat = 0
        return rows.map { row in
            let height: CGFloat
            switch row {
            case .header: height = Self.headerHeight
            case .gap: height = Self.sectionGap
            default: height = Self.rowHeight
            }
            let frame = CGRect(x: 0, y: y, width: Self.width, height: height)
            y += height
            return frame
        }
    }

    private static func editWidth(of action: UIAction) -> CGFloat {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17)
        label.text = action.title
        return label.intrinsicContentSize.width + 24
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        if controller.isEditMenu {
            let width = rows.reduce(16) { total, row in
                if case .action(let action) = row { return total + Self.editWidth(of: action) }
                return total
            }
            return CGSize(width: min(width, size.width), height: Self.editRowHeight)
        }
        return CGSize(width: Self.width, height: rowFrames.last.map { $0.maxY } ?? 0)
    }

    override var intrinsicContentSize: CGSize { sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)) }

    // MARK: Touches

    private func row(at point: CGPoint) -> Int? { rowFrames.firstIndex { $0.contains(point) } }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        highlighted = row(at: touch.location(in: self))
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        highlighted = row(at: touch.location(in: self))
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let index = row(at: touch.location(in: self)) else { highlighted = nil; setNeedsDisplay(); return }
        highlighted = nil
        activate(index)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        highlighted = nil
        setNeedsDisplay()
    }

    /// Activates a row: an action closes the menu and runs; a submenu opens in place; the back
    /// row returns to the parent.
    func activate(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        switch rows[index] {
        case .action(let action):
            guard !action.attributes.contains(.disabled) else { return }
            controller.choose(action)
        case .submenu(let menu):
            path.append(menu)
            rebuild()
            controller.presentationContainer?.setNeedsLayout()
        case .back:
            path.removeLast()
            rebuild()
            controller.presentationContainer?.setNeedsLayout()
        case .header, .gap:
            break
        }
    }

    /// The titles shown, top to bottom (tests).
    var visibleTitles: [String] {
        rows.compactMap { row in
            switch row {
            case .header(let title): return title
            case .action(let action): return action.title
            case .submenu(let menu): return menu.title
            case .back(let menu): return menu.title.isEmpty ? "Back" : menu.title
            case .gap: return nil
            }
        }
    }

    // MARK: Drawing

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        let glass: RGBA = style == .dark ? RGBA(r: 44, g: 44, b: 46) : RGBA(r: 244, g: 244, b: 244)
        let radius = controller.isEditMenu ? rect.height / 2 : Self.cornerRadius
        list.append(.beginShadow(RGBA(red: 0, green: 0, blue: 0, alpha: 0.16), radius: 30, offset: CGSize(width: 0, height: 10)))
        list.append(.fillPath(Path(roundedRect: rect, cornerRadius: radius, style: .continuous), glass))
        list.append(.endGroup)
        let label = UIColor.label.rgba(for: style)
        let secondary = UIColor.secondaryLabel.rgba(for: style)
        let separator: RGBA = style == .dark ? RGBA(r: 255, g: 255, b: 255, a: 0.15) : RGBA(r: 0, g: 0, b: 0, a: 0.1)
        let frames = rowFrames
        for (index, row) in rows.enumerated() {
            let frame = context.absoluteRect(frames[index])
            if index == highlighted {
                list.append(.fillRRect(frame.insetBy(dx: controller.isEditMenu ? 4 : 0, dy: controller.isEditMenu ? 6 : 0), cornerRadius: controller.isEditMenu ? 16 : 0, RGBA(red: 0, green: 0, blue: 0, alpha: 0.08)))
            }
            switch row {
            case .header(let title):
                Self.drawText(title, font: .systemFont(ofSize: 13), color: secondary, in: frame, inset: 16, into: &list, context: context)
            case .gap:
                list.append(.fillRect(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height), separator.multiplyingAlpha(by: 0.5)))
            case .action(let action):
                var ink = action.attributes.contains(.destructive) ? UIColor.systemRed.rgba(for: style) : label
                if action.attributes.contains(.disabled) { ink = ink.multiplyingAlpha(by: 0.3) }
                var inset: CGFloat = 16
                if action.state == .on {
                    SymbolPainter.paint(name: "checkmark", in: CGRect(x: frame.minX + 12, y: frame.midY - 7, width: 14, height: 14), color: ink, weight: 600, into: &list)
                    inset = 36
                } else if action.state == .mixed {
                    SymbolPainter.paint(name: "minus", in: CGRect(x: frame.minX + 12, y: frame.midY - 7, width: 14, height: 14), color: ink, weight: 600, into: &list)
                    inset = 36
                } else if controller.isEditMenu {
                    inset = 12
                }
                Self.drawText(action.title, font: .systemFont(ofSize: 17), color: ink, in: frame, inset: inset, centred: controller.isEditMenu, into: &list, context: context)
                if let subtitle = action.subtitle, !controller.isEditMenu {
                    Self.drawText(subtitle, font: .systemFont(ofSize: 12), color: secondary, in: CGRect(x: frame.minX, y: frame.minY + 24, width: frame.width, height: 16), inset: inset, into: &list, context: context)
                }
                if let image = action.image, image.isSystemSymbol, !controller.isEditMenu {
                    SymbolPainter.paint(name: image.name, in: CGRect(x: frame.maxX - 16 - 20, y: frame.midY - 10, width: 20, height: 20), color: ink, weight: 400, into: &list)
                }
            case .submenu(let menu):
                Self.drawText(menu.title, font: .systemFont(ofSize: 17), color: label, in: frame, inset: 16, into: &list, context: context)
                if let image = menu.image, image.isSystemSymbol {
                    SymbolPainter.paint(name: image.name, in: CGRect(x: frame.maxX - 16 - 20 - 18, y: frame.midY - 10, width: 20, height: 20), color: label, weight: 400, into: &list)
                }
                var chevron = Path()
                chevron.move(to: CGPoint(x: frame.maxX - 20, y: frame.midY - 6))
                chevron.addLine(to: CGPoint(x: frame.maxX - 14, y: frame.midY))
                chevron.addLine(to: CGPoint(x: frame.maxX - 20, y: frame.midY + 6))
                list.append(.strokePath(chevron, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round), secondary))
            case .back(let menu):
                var chevron = Path()
                chevron.move(to: CGPoint(x: frame.minX + 20, y: frame.midY - 6))
                chevron.addLine(to: CGPoint(x: frame.minX + 14, y: frame.midY))
                chevron.addLine(to: CGPoint(x: frame.minX + 20, y: frame.midY + 6))
                list.append(.strokePath(chevron, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round), label))
                Self.drawText(menu.title.isEmpty ? "Back" : menu.title, font: .systemFont(ofSize: 17, weight: .semibold), color: label, in: frame, inset: 32, into: &list, context: context)
            }
            // A thin separator under each row but the last of a section.
            if index + 1 < rows.count, !controller.isEditMenu {
                switch (row, rows[index + 1]) {
                case (.gap, _), (_, .gap), (.header, _): break
                default: list.append(.fillRect(CGRect(x: frame.minX + 16, y: frame.maxY - 0.5, width: frame.width - 16, height: 0.5), separator))
                }
            }
        }
    }

    private static func drawText(_ text: String, font: UIFont, color: RGBA, in frame: CGRect, inset: CGFloat, centred: Bool = false, into list: inout DisplayList, context: PaintContext) {
        _ = context
        let label = UILabel()
        label.font = font
        label.text = text
        let size = label.intrinsicContentSize
        let x = centred ? frame.midX - size.width / 2 : frame.minX + inset
        let baseline = frame.midY - font.lineHeight / 2 + font.ascender
        list.append(.drawText(text, DisplayFont(font.resolved), origin: CGPoint(x: x, y: baseline), color))
    }
}

// MARK: - Context menus

/// Describes the menu a context menu interaction shows and its preview.
@MainActor
public final class UIContextMenuConfiguration {
    public typealias ActionProvider = ([UIMenuElement]) -> UIMenu?
    public typealias PreviewProvider = () -> UIViewController?
    public let identifier: (any NSCopying)?
    let previewProvider: PreviewProvider?
    let actionProvider: ActionProvider?
    public var preferredMenuElementOrder: ElementOrder = .automatic
    public enum ElementOrder: Int, Sendable { case automatic = 0, priority, fixed }

    public init(identifier: (any NSCopying)? = nil, previewProvider: PreviewProvider? = nil, actionProvider: ActionProvider? = nil) {
        self.identifier = identifier
        self.previewProvider = previewProvider
        self.actionProvider = actionProvider
    }
}

/// A placeholder for identifiers (Foundation's `NSCopying` is not available on wasm).
public protocol NSCopying: AnyObject {}

/// An interaction that shows a context menu after a long press on its view.
@MainActor
public final class UIContextMenuInteraction: UIInteraction {
    public private(set) weak var view: UIView?
    public weak var delegate: (any UIContextMenuInteractionDelegate)?
    public enum Appearance: Int, Sendable { case unknown = 0, rich, compact }
    public var menuAppearance: Appearance { .rich }

    public init(delegate: any UIContextMenuInteractionDelegate) {
        self.delegate = delegate
    }

    public func willMove(to view: UIView?) {}
    public func didMove(to view: UIView?) { self.view = view }

    public func location(in view: UIView?) -> CGPoint { lastLocation }
    private var lastLocation = CGPoint.zero

    /// Dismisses the interaction's menu, if shown.
    public func dismissMenu() { presented?.dismiss(animated: false); presented = nil }
    private weak var presented: MenuPanelController?

    func present(_ configuration: UIContextMenuConfiguration, from owner: UIView, at location: CGPoint) {
        lastLocation = location
        let menu = configuration.actionProvider?([]) ?? UIMenu()
        let previewController = configuration.previewProvider?()
        let preview = previewController?.view
        if let preview, previewController.map({ $0.preferredContentSize != .zero }) == true { preview.frame = CGRect(origin: .zero, size: previewController!.preferredContentSize) }
        delegate?.contextMenuInteraction(self, willDisplayMenuFor: configuration, animator: nil)
        MenuPresenter.present(menu, from: owner, preview: preview, at: location) { [weak self] _ in
            guard let self else { return }
            self.delegate?.contextMenuInteraction(self, willEndFor: configuration, animator: nil)
        }
        presented = owner.window?.rootViewController?.topmostPresented as? MenuPanelController
    }
}

@MainActor
public protocol UIContextMenuInteractionDelegate: AnyObject {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration?
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willDisplayMenuFor configuration: UIContextMenuConfiguration, animator: Any?)
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willEndFor configuration: UIContextMenuConfiguration, animator: Any?)
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: Any?)
}

extension UIContextMenuInteractionDelegate {
    public func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willDisplayMenuFor configuration: UIContextMenuConfiguration, animator: Any?) {}
    public func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willEndFor configuration: UIContextMenuConfiguration, animator: Any?) {}
    public func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: Any?) {}
}

// MARK: - Edit menus

/// Where an edit menu is shown.
@MainActor
public final class UIEditMenuConfiguration {
    public let identifier: AnyHashable
    public let sourcePoint: CGPoint
    public var preferredArrowDirection: ArrowDirection = .automatic
    public enum ArrowDirection: Int, Sendable { case automatic = 0, up, down, left, right }
    public init(identifier: AnyHashable?, sourcePoint: CGPoint) {
        self.identifier = identifier ?? AnyHashable("UIEditMenu-\(UIEditMenuConfiguration.counter)")
        UIEditMenuConfiguration.counter += 1
        self.sourcePoint = sourcePoint
    }
    @MainActor private static var counter = 0
}

/// An interaction that shows an edit menu (a bar of actions) above a point in its view.
@MainActor
public final class UIEditMenuInteraction: UIInteraction {
    public private(set) weak var view: UIView?
    public weak var delegate: (any UIEditMenuInteractionDelegate)?
    private weak var presented: MenuPanelController?
    private var configuration: UIEditMenuConfiguration?

    public init(delegate: (any UIEditMenuInteractionDelegate)?) { self.delegate = delegate }

    public func willMove(to view: UIView?) {}
    public func didMove(to view: UIView?) { self.view = view }

    public var isVisible: Bool { presented?.presentingViewController != nil }

    /// Shows the menu the delegate builds (from no suggested actions) above the configuration's point.
    public func presentEditMenu(with configuration: UIEditMenuConfiguration) {
        guard let view else { return }
        self.configuration = configuration
        let menu = delegate?.editMenuInteraction(self, menuFor: configuration, suggestedActions: []) ?? UIMenu()
        guard !menu.children.isEmpty, let window = view.window else { return }
        let presenter = window.rootViewController?.topmostPresented ?? window.rootViewController
        guard let presenter, presenter.presentedViewController == nil else { return }
        delegate?.editMenuInteraction(self, willPresentMenuFor: configuration, animator: nil)
        let controller = MenuPanelController(menu: menu, source: view, preview: nil, point: configuration.sourcePoint) { [weak self] _ in
            guard let self, let configuration = self.configuration else { return }
            self.delegate?.editMenuInteraction(self, willDismissMenuFor: configuration, animator: nil)
        }
        controller.isEditMenu = true
        presenter.present(controller, animated: false)
        presented = controller
    }

    public func dismissMenu() {
        presented?.dismiss(animated: false)
        presented = nil
    }

    public func reloadVisibleMenu() {
        guard let configuration, presented != nil else { return }
        dismissMenu()
        presentEditMenu(with: configuration)
    }

    public func updateVisibleMenuPosition(animated: Bool) { presented?.presentationContainer?.setNeedsLayout() }
}

@MainActor
public protocol UIEditMenuInteractionDelegate: AnyObject {
    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu?
    func editMenuInteraction(_ interaction: UIEditMenuInteraction, targetRectFor configuration: UIEditMenuConfiguration) -> CGRect
    func editMenuInteraction(_ interaction: UIEditMenuInteraction, willPresentMenuFor configuration: UIEditMenuConfiguration, animator: Any?)
    func editMenuInteraction(_ interaction: UIEditMenuInteraction, willDismissMenuFor configuration: UIEditMenuConfiguration, animator: Any?)
}

extension UIEditMenuInteractionDelegate {
    public func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        UIMenu(children: suggestedActions)
    }
    public func editMenuInteraction(_ interaction: UIEditMenuInteraction, targetRectFor configuration: UIEditMenuConfiguration) -> CGRect { .null }
    public func editMenuInteraction(_ interaction: UIEditMenuInteraction, willPresentMenuFor configuration: UIEditMenuConfiguration, animator: Any?) {}
    public func editMenuInteraction(_ interaction: UIEditMenuInteraction, willDismissMenuFor configuration: UIEditMenuConfiguration, animator: Any?) {}
}
