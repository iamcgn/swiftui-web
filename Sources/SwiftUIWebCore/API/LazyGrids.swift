// Lazy grids (Docs/elements/Lazy.md): `GridItem` tracks (fixed, flexible, adaptive) and the
// `LazyVGrid`/`LazyHGrid` layout that flows cells across them; section headers and footers take
// a line of their own. The `_LazyContainer` around the layout makes a `ForEach` inside create
// its cells as they scroll into view and pins the sections' headers and footers.

/// A description of a row or a column in a lazy grid.
public struct GridItem: Sendable {
    /// The size in the minor axis of one or more rows or columns in a grid layout.
    public enum Size: Sendable {
        case fixed(CGFloat)
        case flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity)
        case adaptive(minimum: CGFloat, maximum: CGFloat = .infinity)
    }

    public var size: Size
    /// The spacing to the next item along the minor axis (8 when nil).
    public var spacing: CGFloat?
    /// The alignment of cells within this track (the grid's when nil).
    public var alignment: Alignment?

    public init(_ size: Size = .flexible(), spacing: CGFloat? = nil, alignment: Alignment? = nil) {
        self.size = size
        self.spacing = spacing
        self.alignment = alignment
    }
}

/// A container view that arranges its child views in a grid that grows vertically.
public struct LazyVGrid<Content: View>: View {
    package let columns: [GridItem]
    package let alignment: HorizontalAlignment
    package let spacing: CGFloat?
    package let pinnedViews: PinnedScrollableViews
    package let content: Content

    public init(columns: [GridItem], alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
                pinnedViews: PinnedScrollableViews = [], @ViewBuilder content: () -> Content) {
        self.columns = columns
        self.alignment = alignment
        self.spacing = spacing
        self.pinnedViews = pinnedViews
        self.content = content()
    }

    public var body: some View {
        _LazyContainer(axis: .vertical, pinnedViews: pinnedViews) {
            _LazyGridLayout(axis: .vertical, tracks: columns, alignment: Alignment(horizontal: alignment, vertical: .center), spacing: spacing) { content }
        }
    }
}

/// A container view that arranges its child views in a grid that grows horizontally.
public struct LazyHGrid<Content: View>: View {
    package let rows: [GridItem]
    package let alignment: VerticalAlignment
    package let spacing: CGFloat?
    package let pinnedViews: PinnedScrollableViews
    package let content: Content

    public init(rows: [GridItem], alignment: VerticalAlignment = .center, spacing: CGFloat? = nil,
                pinnedViews: PinnedScrollableViews = [], @ViewBuilder content: () -> Content) {
        self.rows = rows
        self.alignment = alignment
        self.spacing = spacing
        self.pinnedViews = pinnedViews
        self.content = content()
    }

    public var body: some View {
        _LazyContainer(axis: .horizontal, pinnedViews: pinnedViews) {
            _LazyGridLayout(axis: .horizontal, tracks: rows, alignment: Alignment(horizontal: .center, vertical: alignment), spacing: spacing) { content }
        }
    }
}

/// The grid: tracks across the minor axis (columns of a vertical grid), lines along the major
/// axis; cells flow line by line. Fixed tracks take their size, flexible tracks share what is
/// left equally (each clamped to its bounds, the remainder is not redistributed), an adaptive
/// track becomes as many tracks of the shared width as fit. The grid takes the proposed size
/// along the minor axis and positions the tracks in it by its alignment.
public struct _LazyGridLayout: Sendable {
    package let axis: Axis
    package let tracks: [GridItem]
    package let alignment: Alignment
    package let spacing: CGFloat?

    package init(axis: Axis, tracks: [GridItem], alignment: Alignment, spacing: CGFloat?) {
        self.axis = axis
        self.tracks = tracks
        self.alignment = alignment
        self.spacing = spacing
    }

    package struct Track {
        package var size: CGFloat
        package var spacingAfter: CGFloat
        package var alignment: Alignment?
    }

    /// The resolved tracks for the space across the minor axis (nil: the tracks' own sizes).
    package func resolvedTracks(in available: CGFloat?) -> [Track] {
        let defaultSpacing = PlatformMetrics.gridItemSpacing
        var fixed: CGFloat = 0
        var spacingTotal: CGFloat = 0
        var flexible = 0
        for (index, item) in tracks.enumerated() {
            if index < tracks.count - 1 { spacingTotal += item.spacing ?? defaultSpacing }
            switch item.size {
            case .fixed(let size): fixed += size
            case .flexible, .adaptive: flexible += 1
            }
        }
        var result: [Track] = []
        for (index, item) in tracks.enumerated() {
            let spacingAfter = index < tracks.count - 1 ? item.spacing ?? defaultSpacing : 0
            switch item.size {
            case .fixed(let size):
                result.append(Track(size: size, spacingAfter: spacingAfter, alignment: item.alignment))
            case .flexible(let minimum, let maximum):
                let share = available.map { max(0, ($0 - fixed - spacingTotal) / CGFloat(flexible)) } ?? minimum
                result.append(Track(size: min(max(share, minimum), maximum), spacingAfter: spacingAfter, alignment: item.alignment))
            case .adaptive(let minimum, let maximum):
                let gap = item.spacing ?? defaultSpacing
                let room = available.map { max(0, ($0 - fixed - spacingTotal) / CGFloat(flexible)) } ?? minimum
                let count = max(1, Int(((room + gap) / (minimum + gap)).rounded(.down)))
                let size = min(max((room - gap * CGFloat(count - 1)) / CGFloat(count), minimum), maximum)
                for slot in 0..<count {
                    result.append(Track(size: size, spacingAfter: slot < count - 1 ? gap : spacingAfter, alignment: item.alignment))
                }
            }
        }
        return result
    }

    package struct Cell {
        var line: Int
        /// The track, or nil for a section header or footer spanning the grid (`lazy/grid-sections`).
        var track: Int?
    }

    package struct Plan {
        var tracks: [Track]
        /// Each line's extent along the major axis.
        var lines: [CGFloat]
        var cells: [Cell]
        var lineSpacing: CGFloat
        var minor: CGFloat        // the tracks' total across the minor axis
        var major: CGFloat        // the lines' total along the major axis
        /// The grid's extent across the minor axis: the proposal, else the tracks' total.
        var fullMinor: CGFloat

        func cellProposal(_ cell: Cell, axis: Axis) -> ProposedViewSize {
            let extent = cell.track.map { tracks[$0].size } ?? fullMinor
            return axis == .vertical ? ProposedViewSize(width: extent, height: nil) : ProposedViewSize(width: nil, height: extent)
        }
    }

    @MainActor package func plan(proposal: ProposedViewSize, subviews: LayoutSubviews) -> Plan {
        let available = (axis == .vertical ? proposal.width : proposal.height).flatMap { $0.isFinite ? $0 : nil }
        let tracks = resolvedTracks(in: available)
        let lineSpacing = spacing ?? PlatformMetrics.gridItemSpacing
        let minor = tracks.reduce(0) { $0 + $1.size + $1.spacingAfter }
        let fullMinor = available ?? minor
        var lines: [CGFloat] = []
        var cells: [Cell] = []
        var trackCursor = 0
        for subview in subviews {
            let cell: Cell
            if _lazySectionRole(of: subview.node, in: subview.container) != nil {
                // A header or footer: a line of its own across the whole grid.
                trackCursor = 0
                lines.append(0)
                cell = Cell(line: lines.count - 1, track: nil)
            } else {
                if trackCursor == 0 { lines.append(0) }
                cell = Cell(line: lines.count - 1, track: trackCursor)
                trackCursor = (trackCursor + 1) % tracks.count
            }
            let plan = Plan(tracks: tracks, lines: lines, cells: [], lineSpacing: lineSpacing, minor: minor, major: 0, fullMinor: fullMinor)
            let size = subview.sizeThatFits(plan.cellProposal(cell, axis: axis))
            let extent = axis == .vertical ? size.height : size.width
            lines[cell.line] = max(lines[cell.line], extent)
            cells.append(cell)
            if cell.track == nil { trackCursor = 0 }
        }
        let major = lines.reduce(0, +) + lineSpacing * CGFloat(max(0, lines.count - 1))
        return Plan(tracks: tracks, lines: lines, cells: cells, lineSpacing: lineSpacing, minor: minor, major: major, fullMinor: fullMinor)
    }
}

extension _LazyGridLayout: Layout {
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let plan = plan(proposal: proposal, subviews: subviews)
        if axis == .vertical {
            let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? plan.minor
            return CGSize(width: width, height: plan.major)
        } else {
            let height = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? plan.minor
            return CGSize(width: plan.major, height: height)
        }
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let plan = plan(proposal: proposal, subviews: subviews)
        // The tracks sit in the minor extent by the grid's alignment.
        let minorExtent = axis == .vertical ? bounds.width : bounds.height
        let minorStart: CGFloat
        let minorAlignment = axis == .vertical ? alignment.horizontal : .center
        if axis == .vertical {
            switch minorAlignment {
            case .leading: minorStart = 0
            case .trailing: minorStart = minorExtent - plan.minor
            default: minorStart = (minorExtent - plan.minor) / 2
            }
        } else {
            switch alignment.vertical {
            case .top: minorStart = 0
            case .bottom: minorStart = minorExtent - plan.minor
            default: minorStart = (minorExtent - plan.minor) / 2
            }
        }
        var trackOffsets: [CGFloat] = []
        var offset = minorStart
        for track in plan.tracks {
            trackOffsets.append(offset)
            offset += track.size + track.spacingAfter
        }
        var lineStarts: [CGFloat] = []
        var majorOffset: CGFloat = 0
        for extent in plan.lines {
            lineStarts.append(majorOffset)
            majorOffset += extent + plan.lineSpacing
        }
        for (index, subview) in subviews.enumerated() {
            let planCell = plan.cells[index]
            let line = planCell.line
            let cellAlignment = planCell.track.flatMap { plan.tracks[$0].alignment } ?? alignment
            let minorStartOfCell = planCell.track.map { trackOffsets[$0] } ?? 0
            let minorSize = planCell.track.map { plan.tracks[$0].size } ?? minorExtent
            let cell: CGRect
            if axis == .vertical {
                cell = CGRect(x: bounds.minX + minorStartOfCell, y: bounds.minY + lineStarts[line], width: minorSize, height: plan.lines[line])
            } else {
                cell = CGRect(x: bounds.minX + lineStarts[line], y: bounds.minY + minorStartOfCell, width: plan.lines[line], height: minorSize)
            }
            let cellProposal = plan.cellProposal(planCell, axis: axis)
            let size = subview.sizeThatFits(cellProposal)
            let x: CGFloat
            switch cellAlignment.horizontal {
            case .leading: x = cell.minX
            case .trailing: x = cell.maxX - size.width
            default: x = cell.midX - size.width / 2
            }
            let y: CGFloat
            switch cellAlignment.vertical {
            case .top: y = cell.minY
            case .bottom: y = cell.maxY - size.height
            default: y = cell.midY - size.height / 2
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: cellProposal)
        }
    }
}
