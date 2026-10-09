// UIPickerView (Docs/elements/UIKit/DatePicker.md): the spinning-wheel picker with a data
// source and delegate; sized as UIKit sizes it on the iPhone SE simulator (uikit/picker/basic,
// uikit/picker/custom), the drum drawn approximately by the date picker's wheel painter.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// The methods a picker view's data source implements.
@MainActor
public protocol UIPickerViewDataSource: AnyObject {
    func numberOfComponents(in pickerView: UIPickerView) -> Int
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int
}

/// The methods a picker view's delegate implements.
@MainActor
public protocol UIPickerViewDelegate: AnyObject {
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String?
    func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString?
    func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int)
    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat
    func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat
}

extension UIPickerViewDelegate {
    public func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? { nil }
    public func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? { nil }
    /// The default stands for "no view": the picker draws the title.
    public func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView { UIPickerView.noRowView }
    public func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {}
    public func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { WheelPainter.rowPitch }
    public func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat { 0 }
}

/// A view that uses a spinning-wheel or slot-machine metaphor to show one or more sets of values.
@MainActor
open class UIPickerView: UIView {
    /// The sentinel the delegate's default `viewForRow` returns.
    static let noRowView = UIView()

    open weak var dataSource: (any UIPickerViewDataSource)? { didSet { reloadAllComponents() } }
    open weak var delegate: (any UIPickerViewDelegate)? { didSet { reloadAllComponents() } }
    private var selected: [Int] = []
    /// The delegate's row views, kept per component and row and offered back for reuse.
    private var rowViews: [Int: [Int: UIView]] = [:]
    private var spareViews: [Int: UIView] = [:]

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
    }

    open var numberOfComponents: Int { dataSource?.numberOfComponents(in: self) ?? 0 }
    open func numberOfRows(inComponent component: Int) -> Int { dataSource?.pickerView(self, numberOfRowsInComponent: component) ?? 0 }
    open func rowSize(forComponent component: Int) -> CGSize { CGSize(width: componentWidth(component), height: delegate?.pickerView(self, rowHeightForComponent: component) ?? WheelPainter.rowPitch) }

    open func reloadAllComponents() {
        let count = numberOfComponents
        if selected.count != count { selected = Array(repeating: 0, count: count) }
        for (component, views) in rowViews { spareViews[component] = views.values.first }
        rowViews.removeAll()
        setNeedsDisplay()
    }
    open func reloadComponent(_ component: Int) {
        spareViews[component] = rowViews[component]?.values.first
        rowViews[component] = nil
        setNeedsDisplay()
    }

    open func selectRow(_ row: Int, inComponent component: Int, animated: Bool) {
        reloadAllComponents()
        guard selected.indices.contains(component) else { return }
        selected[component] = max(0, min(row, numberOfRows(inComponent: component) - 1))
        setNeedsDisplay()
    }

    open func selectedRow(inComponent component: Int) -> Int { selected.indices.contains(component) ? selected[component] : -1 }

    /// The delegate's view for a row, if it supplies one (fetched once per reload).
    open func view(forRow row: Int, forComponent component: Int) -> UIView? {
        if let view = rowViews[component]?[row] { return view }
        guard let delegate else { return nil }
        let view = delegate.pickerView(self, viewForRow: row, forComponent: component, reusing: spareViews[component])
        guard view !== Self.noRowView else { return nil }
        spareViews[component] = nil
        view.frame = CGRect(origin: .zero, size: rowSize(forComponent: component))
        rowViews[component, default: [:]][row] = view
        return view
    }

    /// A picker sized to fit is 320 × 216 (uikit/picker/basic).
    override open func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: 320, height: 216) }
    override open var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 216) }

    /// Components share the width equally unless the delegate sizes them.
    private func componentWidth(_ component: Int) -> CGFloat {
        let count = max(1, numberOfComponents)
        let requested = delegate?.pickerView(self, widthForComponent: component) ?? 0
        return requested > 0 ? requested : bounds.width / CGFloat(count)
    }

    /// The components' horizontal extents: sized columns sit centred as a group
    /// (uikit/picker/custom: 180 + 80 wide from 30 in).
    private var componentRanges: [Range<CGFloat>] {
        let widths = (0..<numberOfComponents).map(componentWidth)
        var x = ((bounds.width - widths.reduce(0, +)) / 2).rounded()
        return widths.map { width in defer { x += width }; return x..<(x + width) }
    }

    /// The drum turns every component at the tallest row height the delegate gives.
    private var rowHeight: CGFloat {
        (0..<numberOfComponents).map { delegate?.pickerView(self, rowHeightForComponent: $0) ?? WheelPainter.rowPitch }.max() ?? WheelPainter.rowPitch
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let bounds = context.absoluteRect(CGRect(origin: .zero, size: self.bounds.size))
        if selected.count != numberOfComponents { reloadAllComponents() }
        var columns: [WheelPainter.Column] = []
        for (component, range) in componentRanges.enumerated() {
            let rows = numberOfRows(inComponent: component)
            let current = selectedRow(inComponent: component)
            var column = WheelPainter.Column(centre: bounds.minX + (range.lowerBound + range.upperBound) / 2, rows: { [weak self] offset in
                guard let self else { return nil }
                let row = current + offset
                guard (0..<rows).contains(row) else { return nil }
                return self.title(forRow: row, forComponent: component)
            })
            column.view = { [weak self] offset in
                guard let self else { return nil }
                let row = current + offset
                guard (0..<rows).contains(row) else { return nil }
                return self.view(forRow: row, forComponent: component)
            }
            columns.append(column)
        }
        WheelPainter.paint(columns: columns, in: bounds, style: style, rowHeight: rowHeight, into: &list)
    }

    private func title(forRow row: Int, forComponent component: Int) -> String? {
        if let attributed = delegate?.pickerView(self, attributedTitleForRow: row, forComponent: component) { return attributed.string }
        return delegate?.pickerView(self, titleForRow: row, forComponent: component)
    }

    // MARK: Touches: a drag spins the column under the finger by the rows it covers; a tap picks
    // the row under the finger.

    private var dragStart: CGPoint?

    override open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        dragStart = touches.first?.location(in: self)
    }

    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard let start = dragStart, let touch = touches.first else { return }
        dragStart = nil
        let point = touch.location(in: self)
        guard let component = componentRanges.firstIndex(where: { $0.contains(start.x) }) else { return }
        let dragged = abs(point.y - start.y) > 8
        let rows = dragged ? Int(((start.y - point.y) / rowHeight).rounded()) : Int(((point.y - bounds.midY) / rowHeight).rounded())
        guard rows != 0 else { return }
        let row = max(0, min(numberOfRows(inComponent: component) - 1, selectedRow(inComponent: component) + rows))
        guard row != selectedRow(inComponent: component) else { return }
        selected[component] = row
        setNeedsDisplay()
        delegate?.pickerView(self, didSelectRow: row, inComponent: component)
    }

    override open func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        dragStart = nil
    }

    override func decorateSemantics(_ node: inout SemanticsNode) {
        node.role = .slider
        let titles = (0..<numberOfComponents).compactMap { title(forRow: selectedRow(inComponent: $0), forComponent: $0) }
        if node.label.isEmpty { node.label = titles.joined(separator: " ") }
    }

    /// Assistive technology steps the first component.
    override open func accessibilityIncrement() { step(1) }
    override open func accessibilityDecrement() { step(-1) }

    private func step(_ delta: Int) {
        guard numberOfComponents > 0 else { return }
        let row = selectedRow(inComponent: 0) + delta
        guard (0..<numberOfRows(inComponent: 0)).contains(row) else { return }
        selectRow(row, inComponent: 0, animated: false)
        delegate?.pickerView(self, didSelectRow: row, inComponent: 0)
    }
}
