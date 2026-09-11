// UIPickerView (Docs/elements/UIKit/DatePicker.md): the spinning-wheel picker with a data
// source and delegate; sized as UIKit sizes it on the iPhone SE simulator (uikit/picker/basic),
// the drum drawn approximately by the date picker's wheel painter.

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
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int)
    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat
    func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat
}

extension UIPickerViewDelegate {
    public func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? { nil }
    public func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {}
    public func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { WheelPainter.rowPitch }
    public func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat { 0 }
}

/// A view that uses a spinning-wheel or slot-machine metaphor to show one or more sets of values.
@MainActor
open class UIPickerView: UIView {
    open weak var dataSource: (any UIPickerViewDataSource)? { didSet { reloadAllComponents() } }
    open weak var delegate: (any UIPickerViewDelegate)? { didSet { reloadAllComponents() } }
    private var selected: [Int] = []

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
        setNeedsDisplay()
    }
    open func reloadComponent(_ component: Int) { setNeedsDisplay() }

    open func selectRow(_ row: Int, inComponent component: Int, animated: Bool) {
        reloadAllComponents()
        guard selected.indices.contains(component) else { return }
        selected[component] = max(0, min(row, numberOfRows(inComponent: component) - 1))
        setNeedsDisplay()
    }

    open func selectedRow(inComponent component: Int) -> Int { selected.indices.contains(component) ? selected[component] : -1 }

    /// A picker sized to fit is 320 × 216 (uikit/picker/basic).
    override open func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: 320, height: 216) }
    override open var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 216) }

    /// Components share the width equally unless the delegate sizes them.
    private func componentWidth(_ component: Int) -> CGFloat {
        let count = max(1, numberOfComponents)
        let requested = delegate?.pickerView(self, widthForComponent: component) ?? 0
        return requested > 0 ? requested : bounds.width / CGFloat(count)
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let bounds = context.absoluteRect(CGRect(origin: .zero, size: self.bounds.size))
        reloadAllComponents()
        var x = bounds.minX
        var columns: [WheelPainter.Column] = []
        for component in 0..<numberOfComponents {
            let width = componentWidth(component)
            let rows = numberOfRows(inComponent: component)
            let current = selectedRow(inComponent: component)
            columns.append(WheelPainter.Column(centre: x + width / 2, rows: { [weak self] offset in
                guard let self else { return nil }
                let row = current + offset
                guard (0..<rows).contains(row) else { return nil }
                return self.delegate?.pickerView(self, titleForRow: row, forComponent: component)
            }))
            x += width
        }
        WheelPainter.paint(columns: columns, in: bounds, style: style, into: &list)
    }

    override func decorateSemantics(_ node: inout SemanticsNode) {
        node.role = .slider
        let titles = (0..<numberOfComponents).compactMap { delegate?.pickerView(self, titleForRow: selectedRow(inComponent: $0), forComponent: $0) }
        if node.label.isEmpty { node.label = titles.joined(separator: " ") }
    }

    /// Assistive technology steps the first component.
    override func accessibilityIncrement() { step(1) }
    override func accessibilityDecrement() { step(-1) }

    private func step(_ delta: Int) {
        guard numberOfComponents > 0 else { return }
        let row = selectedRow(inComponent: 0) + delta
        guard (0..<numberOfRows(inComponent: 0)).contains(row) else { return }
        selectRow(row, inComponent: 0, animated: false)
        delegate?.pickerView(self, didSelectRow: row, inComponent: 0)
    }
}
