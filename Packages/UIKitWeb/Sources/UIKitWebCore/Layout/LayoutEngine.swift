// The Auto Layout engine (decision 0014, Phase 3; Docs/elements/UIKit/AutoLayout.md): one
// Cassowary solve per layout pass over a root's subtree. Every view gets four variables (its
// origin and size in its superview's coordinates); a view that translates its autoresizing
// mask into constraints pins them to its frame, one that does not is placed by the solution;
// intrinsic content sizes become hugging and compression-resistance inequalities; the
// `NSLayoutConstraint`s held by the views relate attribute expressions in the holder's
// coordinates; the system layout guides are insets of their owner and a guide the app made has
// four variables of its own in its owner's coordinates. Solved frames land on the pixel grid.

@MainActor
final class LayoutEngine {
    private struct Variables {
        let x, y, width, height: LayoutVariable
    }

    private let root: UIView
    private let solver = CassowarySolver()
    private var variables: [ObjectIdentifier: Variables] = [:]
    private var placed: [UIView] = []
    private var guides: [UILayoutGuide] = []
    private let scale: CGFloat

    /// Whether `root`'s subtree needs a solve: a constraint anywhere, or a view placed by layout.
    static func hasConstraints(_ view: UIView) -> Bool {
        if !view.layoutState.constraints.isEmpty { return true }
        if !view.translatesAutoresizingMaskIntoConstraints, view.superview != nil { return true }
        return view.subviews.contains { hasConstraints($0) }
    }

    /// Builds the tableau for `root`'s subtree. `rootSize` fixes the root's size when given
    /// (a layout pass); a fitting solve leaves it to `fit`.
    init(root: UIView, fixRoot: Bool) {
        self.root = root
        scale = UIScreen.main.scale
        let rootVariables = variables(for: root)
        // The root is the origin of its own space.
        solver.add(LayoutConstraintRow(expression: LinearExpression(rootVariables.x), relation: .equal, strength: LayoutStrength.required))
        solver.add(LayoutConstraintRow(expression: LinearExpression(rootVariables.y), relation: .equal, strength: LayoutStrength.required))
        if fixRoot {
            solver.add(LayoutConstraintRow(expression: LinearExpression(rootVariables.width, constant: -root.bounds.width), relation: .equal, strength: LayoutStrength.required))
            solver.add(LayoutConstraintRow(expression: LinearExpression(rootVariables.height, constant: -root.bounds.height), relation: .equal, strength: LayoutStrength.required))
        }
        addGuides(of: root)
        for subview in root.subviews { add(subview) }
        addConstraints(of: root)
    }

    /// A guide the app made (`addLayoutGuide`) is a rectangle of its own in its owner's space,
    /// placed only by the constraints on it; the system guides stay insets of their owner.
    private func addGuides(of view: UIView) {
        for guide in view.layoutState.guides where guide.systemInsets == nil {
            let v = variables(for: guide)
            solver.add(LayoutConstraintRow(expression: LinearExpression(v.width), relation: .greaterThanOrEqual, strength: LayoutStrength.required))
            solver.add(LayoutConstraintRow(expression: LinearExpression(v.height), relation: .greaterThanOrEqual, strength: LayoutStrength.required))
            guides.append(guide)
        }
    }

    private func variables(for item: AnyObject) -> Variables {
        if let existing = variables[ObjectIdentifier(item)] { return existing }
        let made = Variables(x: LayoutVariable("x"), y: LayoutVariable("y"), width: LayoutVariable("w"), height: LayoutVariable("h"))
        variables[ObjectIdentifier(item)] = made
        return made
    }

    /// Adds a view below the root: its frame as required constraints when it translates its
    /// autoresizing mask, else its intrinsic size inequalities; then its subtree.
    private func add(_ view: UIView) {
        let v = variables(for: view)
        if view.translatesAutoresizingMaskIntoConstraints {
            let frame = view.frame
            solver.add(LayoutConstraintRow(expression: LinearExpression(v.x, constant: -frame.minX), relation: .equal, strength: LayoutStrength.required))
            solver.add(LayoutConstraintRow(expression: LinearExpression(v.y, constant: -frame.minY), relation: .equal, strength: LayoutStrength.required))
            solver.add(LayoutConstraintRow(expression: LinearExpression(v.width, constant: -frame.width), relation: .equal, strength: LayoutStrength.required))
            solver.add(LayoutConstraintRow(expression: LinearExpression(v.height, constant: -frame.height), relation: .equal, strength: LayoutStrength.required))
        } else {
            // A stack view's arranged subviews are laid out by the stack (UIKit's stack makes
            // their constraints itself); the solver sizes them but does not place them.
            if !(view.superview is UIStackView) { placed.append(view) }
            // The intrinsic size is the alignment rect's; the frame adds the alignment rect
            // insets (uikit/autolayout/hugging: a segmented control's 31 pt intrinsic height
            // under its 0.5 pt insets makes a 32 pt frame).
            let intrinsic = view._layoutIntrinsicSize
            let insets = view.alignmentRectInsets
            if intrinsic.width >= 0 {
                let width = intrinsic.width + insets.left + insets.right
                addIntrinsic(v.width, width, hugging: view.contentHuggingPriority(for: .horizontal), resistance: view.contentCompressionResistancePriority(for: .horizontal))
            }
            if intrinsic.height >= 0 {
                let height = intrinsic.height + insets.top + insets.bottom
                addIntrinsic(v.height, height, hugging: view.contentHuggingPriority(for: .vertical), resistance: view.contentCompressionResistancePriority(for: .vertical))
            }
            // Sizes are never negative.
            solver.add(LayoutConstraintRow(expression: LinearExpression(v.width), relation: .greaterThanOrEqual, strength: LayoutStrength.required))
            solver.add(LayoutConstraintRow(expression: LinearExpression(v.height), relation: .greaterThanOrEqual, strength: LayoutStrength.required))
        }
        addGuides(of: view)
        for subview in view.subviews { add(subview) }
        addConstraints(of: view)
    }

    private func addIntrinsic(_ variable: LayoutVariable, _ size: CGFloat, hugging: UILayoutPriority, resistance: UILayoutPriority) {
        // width <= intrinsic at the hugging priority; width >= intrinsic at the resistance.
        solver.add(LayoutConstraintRow(expression: LinearExpression(variable, constant: -size), relation: .lessThanOrEqual, strength: LayoutStrength.weight(priority: hugging.rawValue)))
        solver.add(LayoutConstraintRow(expression: LinearExpression(variable, constant: -size), relation: .greaterThanOrEqual, strength: LayoutStrength.weight(priority: resistance.rawValue)))
    }

    private func addConstraints(of holder: UIView) {
        for constraint in holder.layoutState.constraints {
            guard let first = constraint.firstItem, let lhs = expression(of: first, constraint.firstAttribute, in: holder) else { continue }
            var expression = lhs
            if let second = constraint.secondItem, constraint.secondAttribute != .notAnAttribute,
               let rhs = self.expression(of: second, constraint.secondAttribute, in: holder) {
                expression = lhs - rhs * Double(constraint.multiplier)
            }
            expression = expression + Double(-constraint.constant)
            let relation: LayoutRelation
            switch constraint.relation {
            case .equal: relation = .equal
            case .lessThanOrEqual: relation = .lessThanOrEqual
            case .greaterThanOrEqual: relation = .greaterThanOrEqual
            }
            solver.add(LayoutConstraintRow(expression: expression, relation: relation, strength: LayoutStrength.weight(priority: constraint.priority.rawValue)))
        }
    }

    /// The linear expression of an item's attribute in `holder`'s coordinates: a view's own
    /// variables plus the origins of its ancestors below the holder; a guide's owner inset.
    private func expression(of item: AnyObject, _ attribute: NSLayoutConstraint.Attribute, in holder: UIView) -> LinearExpression? {
        let view: UIView
        var insets = UIEdgeInsets.zero
        var isGuide = false
        var ownGuide: UILayoutGuide?
        if let v = item as? UIView {
            view = v
        } else if let guide = item as? UILayoutGuide, let owner = guide.owningView {
            view = owner
            isGuide = true
            if let system = guide.systemInsets {
                insets = system(owner)
            } else {
                ownGuide = guide
            }
        } else {
            return nil
        }
        guard variables[ObjectIdentifier(view)] != nil || view === root || view.isDescendant(of: root) else { return nil }
        let v = variables(for: ownGuide ?? view)
        // The view's origin in the holder's space (an app-made guide's own origin on top).
        var left = LinearExpression()
        var top = LinearExpression()
        if view !== holder {
            var current: UIView? = view
            while let node = current, node !== holder, node !== root || holder === root {
                let nv = variables(for: node)
                left = left + LinearExpression(nv.x)
                top = top + LinearExpression(nv.y)
                if node === root { break }
                current = node.superview
            }
        }
        if ownGuide != nil {
            left = left + LinearExpression(v.x)
            top = top + LinearExpression(v.y)
        }
        var width = LinearExpression(v.width)
        var height = LinearExpression(v.height)
        if isGuide, ownGuide == nil {
            left = left + insets.left
            top = top + insets.top
            width = width - (insets.left + insets.right)
            height = height - (insets.top + insets.bottom)
        }
        let margins = isGuide ? UIEdgeInsets.zero : view.effectiveLayoutMargins
        switch attribute {
        case .left, .leading: return left
        case .right, .trailing: return left + width
        case .top: return top
        case .bottom: return top + height
        case .width: return width
        case .height: return height
        case .centerX: return left + width * 0.5
        case .centerY: return top + height * 0.5
        case .leftMargin, .leadingMargin: return left + margins.left
        case .rightMargin, .trailingMargin: return left + width - margins.right
        case .topMargin: return top + margins.top
        case .bottomMargin: return top + height - margins.bottom
        case .centerXWithinMargins: return left + (width + (margins.left - margins.right)) * 0.5
        case .centerYWithinMargins: return top + (height + (margins.top - margins.bottom)) * 0.5
        case .firstBaseline, .lastBaseline:
            // The baseline sits where it does in the intrinsic height, moving with the centring.
            let intrinsic = view._layoutIntrinsicSize
            let reference = intrinsic.height >= 0 ? intrinsic.height : view.bounds.height
            let baselines = view.textBaselines(in: CGSize(width: max(view.bounds.width, intrinsic.width), height: reference))
            let offset = attribute == .firstBaseline ? baselines.first : baselines.last
            return top + (height - reference) * 0.5 + offset
        case .notAnAttribute: return nil
        }
    }

    /// Solves and moves every placed view to its frame, on the pixel grid of its superview.
    func apply() {
        solver.solve()
        for view in placed {
            let v = variables(for: view)
            let x = round(solver.value(of: v.x)), y = round(solver.value(of: v.y))
            let right = round(solver.value(of: v.x) + solver.value(of: v.width)), bottom = round(solver.value(of: v.y) + solver.value(of: v.height))
            let frame = CGRect(x: x, y: y, width: max(0, right - x), height: max(0, bottom - y))
            if view.frame != frame { view.frame = frame }
        }
        for guide in guides {
            let v = variables(for: guide)
            let x = round(solver.value(of: v.x)), y = round(solver.value(of: v.y))
            let right = round(solver.value(of: v.x) + solver.value(of: v.width)), bottom = round(solver.value(of: v.y) + solver.value(of: v.height))
            guide.layoutFrame = CGRect(x: x, y: y, width: max(0, right - x), height: max(0, bottom - y))
        }
    }

    /// The size the root takes when `target` is proposed at the fitting priorities.
    func fit(_ target: CGSize, horizontal: UILayoutPriority, vertical: UILayoutPriority) -> CGSize {
        let v = variables(for: root)
        solver.add(LayoutConstraintRow(expression: LinearExpression(v.width, constant: -Double(target.width)), relation: .equal, strength: LayoutStrength.weight(priority: horizontal.rawValue)))
        solver.add(LayoutConstraintRow(expression: LinearExpression(v.height, constant: -Double(target.height)), relation: .equal, strength: LayoutStrength.weight(priority: vertical.rawValue)))
        solver.solve()
        return CGSize(width: round(solver.value(of: v.width)), height: round(solver.value(of: v.height)))
    }

    private func round(_ value: Double) -> CGFloat {
        (CGFloat(value) * scale).rounded() / scale
    }

    /// After a solve: gives every wrapping label narrower than its text the width it was
    /// solved to, so a second pass can size its height for that width (UIKit's automatic
    /// preferred layout width). Returns whether a second pass is needed.
    func wrapLabelsForSecondPass() -> Bool {
        var needed = false
        for view in placed {
            guard let label = view as? UILabel, label.numberOfLines != 1, label.preferredMaxLayoutWidth == 0, label.text?.isEmpty == false else { continue }
            let width = round(solver.value(of: variables(for: label).width))
            guard width > 0, width != label.layoutWrapWidth else { continue }
            let unbounded = label.textSize(fitting: nil).width
            if width < unbounded || label.layoutWrapWidth > 0 {
                label.layoutWrapWidth = width
                needed = true
            }
        }
        return needed
    }
}

/// Per-view Auto Layout state, kept out of `UIView`'s declaration.
@MainActor
final class ViewLayoutState {
    var constraints: [NSLayoutConstraint] = []
    var guides: [UILayoutGuide] = []
    var safeAreaGuide: UILayoutGuide?
    var marginsGuide: UILayoutGuide?
    var needsUpdateConstraints = true
}

extension UIView {
    /// Runs the constraint pass for the subtree rooted here: `updateConstraints` where asked,
    /// then a solve that places the constrained views. Called at the start of a root's layout.
    func solveConstraintsIfNeeded() {
        updateConstraintsIfNeeded()
        guard LayoutEngine.hasConstraints(self) else { return }
        let engine = LayoutEngine(root: self, fixRoot: true)
        engine.apply()
        if engine.wrapLabelsForSecondPass() { LayoutEngine(root: self, fixRoot: true).apply() }
    }

    /// The size the subtree's constraints give this view for `targetSize`, or nil when nothing
    /// in it is constrained (callers fall back to intrinsic sizes).
    func constrainedSizeFitting(_ targetSize: CGSize, horizontal: UILayoutPriority, vertical: UILayoutPriority) -> CGSize? {
        guard LayoutEngine.hasConstraints(self) else { return nil }
        updateConstraintsIfNeeded()
        let engine = LayoutEngine(root: self, fixRoot: false)
        let size = engine.fit(targetSize, horizontal: horizontal, vertical: vertical)
        if engine.wrapLabelsForSecondPass() { return LayoutEngine(root: self, fixRoot: false).fit(targetSize, horizontal: horizontal, vertical: vertical) }
        return size
    }
}
