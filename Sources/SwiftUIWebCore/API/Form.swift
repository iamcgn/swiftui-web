/// A container for grouping controls used for data entry, such as in settings or inspectors.
///
/// macOS behaviour measured in `Docs/elements/Form.md`. The automatic style in a hosted window is
/// `.columns`: labels right-aligned in a column, controls at the widest label + 8, rows spaced
/// like a `VStack`, the form its content's size. `.grouped` fills its space with cards of
/// full-width rows (label leading, control trailing) inset 20 pt, separated by 1 pt lines.
public struct Form<Content: View>: View {
    package let content: Content

    /// Creates a form with the provided content.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @Environment(\.formStyle) private var style

    public var body: some View {
        switch style._kind {
        case .columns:
            _FormColumnsLayout { content.environment(\._formStyle, .columns) }
        case .grouped:
            ScrollView(.vertical) {
                _FormGroupedContent(content: AnyView(content.environment(\._formStyle, .grouped)))
                    .padding(PlatformMetrics.formGroupedInset)
            }
        }
    }
}

// MARK: - Styles

/// How a form lays its rows out.
public enum _FormStyleKind: Sendable {
    case columns, grouped
}

/// The appearance and behavior of a form.
public protocol FormStyle: Sendable {
    var _kind: _FormStyleKind { get }
}

/// The default form style (`.columns` on macOS).
public struct AutomaticFormStyle: FormStyle {
    public init() {}
    public var _kind: _FormStyleKind { .columns }
}

/// A non-scrolling form style with a trailing aligned column of labels next to a leading
/// aligned column of values.
public struct ColumnsFormStyle: FormStyle {
    public init() {}
    public var _kind: _FormStyleKind { .columns }
}

/// A form style with grouped rows.
public struct GroupedFormStyle: FormStyle {
    public init() {}
    public var _kind: _FormStyleKind { .grouped }
}

extension FormStyle where Self == AutomaticFormStyle {
    public static var automatic: AutomaticFormStyle { AutomaticFormStyle() }
}
extension FormStyle where Self == ColumnsFormStyle {
    public static var columns: ColumnsFormStyle { ColumnsFormStyle() }
}
extension FormStyle where Self == GroupedFormStyle {
    public static var grouped: GroupedFormStyle { GroupedFormStyle() }
}

package struct FormStyleKey: EnvironmentKey {
    package static let defaultValue: any FormStyle = AutomaticFormStyle()
}

package struct InFormKey: EnvironmentKey {
    package static let defaultValue: _FormStyleKind? = nil
}

extension EnvironmentValues {
    package var formStyle: any FormStyle {
        get { self[FormStyleKey.self] }
        set { self[FormStyleKey.self] = newValue }
    }

    /// The style of the form this view is a row of, if any (controls lay out as form rows).
    package var _formStyle: _FormStyleKind? {
        get { self[InFormKey.self] }
        set { self[InFormKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for forms in a view hierarchy.
    nonisolated public func formStyle<S: FormStyle>(_ style: S) -> some View {
        environment(\.formStyle, style)
    }
}

// MARK: - Columns layout

extension HorizontalAlignment {
    package enum _FormControlColumn: AlignmentID {
        package static func defaultValue(in context: ViewDimensions) -> CGFloat { context[HorizontalAlignment.leading] }
    }

    /// Where a form row's control starts: its label's width plus the gap; the leading edge for
    /// rows without a label.
    package static let _formControlColumn = HorizontalAlignment(_FormControlColumn.self)
}

/// The columns form: every row's `_formControlColumn` guide meets at the widest label + gap; a
/// row is proposed its own guide plus the control column's width and placed so the guides align.
public struct _FormColumnsLayout: Layout {
    public init() {}

    public static var layoutProperties: LayoutProperties {
        var properties = LayoutProperties()
        properties.stackOrientation = .vertical
        return properties
    }

    private struct Plan {
        var column: CGFloat
        var guides: [CGFloat]
        var sizes: [CGSize]
        var proposals: [ProposedViewSize]
        var gaps: [CGFloat]
        var size: CGSize
    }

    private func plan(proposal: ProposedViewSize, subviews: Subviews) -> Plan {
        let guides = subviews.map { $0.dimensions(in: .unspecified)[HorizontalAlignment._formControlColumn] }
        let column = guides.max() ?? 0
        var sizes: [CGSize] = []
        var proposals: [ProposedViewSize] = []
        for (subview, guide) in zip(subviews, guides) {
            let width = proposal.width.map { max(0, guide + $0 - column) }
            let p = ProposedViewSize(width: width, height: nil)
            proposals.append(p)
            sizes.append(subview.sizeThatFits(p))
        }
        let gaps = StackLayoutEngine.spacings(subviews, axis: .vertical, explicit: nil)
        let width = zip(guides, sizes).map { column - $0 + $1.width }.max() ?? 0
        let height = sizes.reduce(0) { $0 + $1.height } + gaps.reduce(0, +)
        return Plan(column: column, guides: guides, sizes: sizes, proposals: proposals, gaps: gaps, size: CGSize(width: width, height: height))
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.isEmpty ? .zero : plan(proposal: proposal, subviews: subviews).size
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let plan = plan(proposal: proposal, subviews: subviews)
        var y = bounds.minY + (bounds.height - plan.size.height) / 2
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + plan.column - plan.guides[index], y: y), anchor: .topLeading, proposal: plan.proposals[index])
            y += plan.sizes[index].height + (index < plan.gaps.count ? plan.gaps[index] : 0)
        }
    }

    public typealias AnimatableData = EmptyAnimatableData
}

// MARK: - Rows

/// How a labelled control row aligns its label and control.
public enum _FormRowMode: Sendable {
    /// Label, 8 pt, control; both centred vertically and snapped to the pixel grid (Stepper).
    case centered
    /// Label, 8 pt, control; the label's baseline on the control's first text baseline (TextField).
    case firstTextBaseline
    /// The macOS form slider row: a 16 pt label 7 pt down, the track 1 pt down, 23 pt tall.
    case sliderColumns
    /// A grouped form row: the label at the leading edge, the control at the trailing edge.
    case grouped
}

/// A control's label and the control itself, laid out as a form row (`FormLabeledRowNode`); its
/// `_formControlColumn` guide is the label's width plus the gap.
public struct _FormLabeledRow: View {
    package let label: AnyView?
    package let content: AnyView
    package let mode: _FormRowMode

    package init(label: AnyView?, content: AnyView, mode: _FormRowMode) {
        self.label = label
        self.content = content
        self.mode = mode
    }

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_FormLabeledRow>) -> TypedNode<_FormLabeledRow> {
        FormLabeledRowNode(context)
    }
}

/// The sections of a grouped form as cards (`FormGroupedNode`).
public struct _FormGroupedContent: View {
    package let content: AnyView
    package init(content: AnyView) { self.content = content }

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_FormGroupedContent>) -> TypedNode<_FormGroupedContent> {
        FormGroupedNode(context)
    }
}
