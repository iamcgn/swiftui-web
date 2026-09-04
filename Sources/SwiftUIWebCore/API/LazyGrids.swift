// Lazy grids (Docs/elements/Lazy.md): `GridItem` tracks (fixed, flexible, adaptive) and the
// `LazyVGrid`/`LazyHGrid` layout that flows cells across them, eagerly.

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
        _LazyGridLayout(axis: .vertical, tracks: columns, alignment: Alignment(horizontal: alignment, vertical: .center), spacing: spacing) { content }
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
        _LazyGridLayout(axis: .horizontal, tracks: rows, alignment: Alignment(horizontal: .center, vertical: alignment), spacing: spacing) { content }
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

    package struct Plan {
        var tracks: [Track]
        /// Each line's extent along the major axis.
        var lines: [CGFloat]
        var lineSpacing: CGFloat
        var minor: CGFloat        // the tracks' total across the minor axis
        var major: CGFloat        // the lines' total along the major axis
    }

    @MainActor package func plan(proposal: ProposedViewSize, subviews: LayoutSubviews) -> Plan {
        let available = axis == .vertical ? proposal.width : proposal.height
        let tracks = resolvedTracks(in: available.flatMap { $0.isFinite ? $0 : nil })
        let lineSpacing = spacing ?? PlatformMetrics.gridItemSpacing
        var lines: [CGFloat] = []
        for (index, subview) in subviews.enumerated() {
            let track = tracks[index % tracks.count]
            let cellProposal = axis == .vertical ? ProposedViewSize(width: track.size, height: nil) : ProposedViewSize(width: nil, height: track.size)
            let size = subview.sizeThatFits(cellProposal)
            let extent = axis == .vertical ? size.height : size.width
            let line = index / tracks.count
            if line < lines.count { lines[line] = max(lines[line], extent) } else { lines.append(extent) }
        }
        let minor = tracks.reduce(0) { $0 + $1.size + $1.spacingAfter }
        let major = lines.reduce(0, +) + lineSpacing * CGFloat(max(0, lines.count - 1))
        return Plan(tracks: tracks, lines: lines, lineSpacing: lineSpacing, minor: minor, major: major)
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
        var majorOffset: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let trackIndex = index % plan.tracks.count
            let line = index / plan.tracks.count
            if trackIndex == 0, line > 0 { majorOffset += plan.lines[line - 1] + plan.lineSpacing }
            let track = plan.tracks[trackIndex]
            let cellAlignment = track.alignment ?? alignment
            let cell: CGRect
            if axis == .vertical {
                cell = CGRect(x: bounds.minX + trackOffsets[trackIndex], y: bounds.minY + majorOffset, width: track.size, height: plan.lines[line])
            } else {
                cell = CGRect(x: bounds.minX + majorOffset, y: bounds.minY + trackOffsets[trackIndex], width: plan.lines[line], height: track.size)
            }
            let cellProposal = axis == .vertical ? ProposedViewSize(width: track.size, height: nil) : ProposedViewSize(width: nil, height: track.size)
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
