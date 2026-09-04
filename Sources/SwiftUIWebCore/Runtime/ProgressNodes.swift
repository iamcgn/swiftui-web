// ProgressView nodes (Docs/elements/ProgressView.md): the linear bar and the ring/spinner,
// painted with the inactive-window greys the goldens show.

/// The linear bar: a 20 pt row as wide as proposed; an 8 pt pill track with the completed
/// fraction filled from the leading edge (an indeterminate bar shows a short pill at the start).
@MainActor
package final class ProgressBarNode: LeafNode<_ProgressBar> {
    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? PlatformMetrics.progressBarIdealWidth
        return CGSize(width: width, height: PlatformMetrics.progressRowHeight)
    }

    override package var layoutSpacing: ViewSpacing { .plainControl }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        let height = PlatformMetrics.progressBarHeight
        let track = CGRect(x: bounds.minX, y: bounds.midY - height / 2, width: bounds.width, height: height)
        list.append(.fillRRect(track, cornerRadius: height / 2, RGBA(red: 0, green: 0, blue: 0, alpha: PlatformMetrics.progressTrackAlpha)))
        let fillWidth: CGFloat
        if let fraction = view.fraction {
            fillWidth = (track.width * CGFloat(fraction)).rounded()
        } else {
            fillWidth = PlatformMetrics.progressIndeterminateSegment
        }
        guard fillWidth > 0 else { return }
        list.append(.fillRRect(CGRect(x: track.minX, y: track.minY, width: max(fillWidth, height), height: height), cornerRadius: height / 2,
                               RGBA(red: 0, green: 0, blue: 0, alpha: PlatformMetrics.progressFillAlpha)))
    }
}

/// The ring: a square of the diameter; a 5 pt track ring with the completed fraction stroked
/// clockwise from the top with round caps. Without a fraction, the spinner: eight rounded spokes
/// fading around the circle (its animation phase is fixed).
@MainActor
package final class ProgressRingNode: LeafNode<_ProgressRing> {
    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        CGSize(width: view.diameter, height: view.diameter)
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let black = { (alpha: Double) in RGBA(red: 0, green: 0, blue: 0, alpha: alpha) }
        if let fraction = view.fraction {
            let stroke = PlatformMetrics.progressRingStroke * view.diameter / PlatformMetrics.progressRingDiameter(.regular)
            let radius = view.diameter / 2 - stroke / 2
            var track = Path()
            track.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            list.append(.strokePath(track, style: StrokeStyle(lineWidth: stroke), black(PlatformMetrics.progressRingTrackAlpha)))
            guard fraction > 0 else { return }
            var arc = Path()
            arc.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
            list.append(.strokePath(arc, style: StrokeStyle(lineWidth: stroke, lineCap: fraction < 1 ? .round : .butt), black(PlatformMetrics.progressRingFillAlpha)))
        } else {
            let scale = view.diameter / PlatformMetrics.progressRingDiameter(.regular)
            let inner = PlatformMetrics.spinnerInnerRadius * scale, outer = PlatformMetrics.spinnerOuterRadius * scale
            let style = StrokeStyle(lineWidth: PlatformMetrics.spinnerSpokeWidth * scale, lineCap: .round)
            for index in 0..<PlatformMetrics.spinnerSpokes {
                // The darkest spoke points left; the others fade clockwise behind it.
                let angle = Double.pi + Double(index) * 2 * .pi / Double(PlatformMetrics.spinnerSpokes)
                let alpha = PlatformMetrics.spinnerMaxAlpha - (PlatformMetrics.spinnerMaxAlpha - PlatformMetrics.spinnerMinAlpha) * Double(index) / Double(PlatformMetrics.spinnerSpokes - 1)
                var spoke = Path()
                spoke.move(to: CGPoint(x: center.x + inner * CGFloat(_cos(angle)), y: center.y + inner * CGFloat(_sin(angle))))
                spoke.addLine(to: CGPoint(x: center.x + outer * CGFloat(_cos(angle)), y: center.y + outer * CGFloat(_sin(angle))))
                list.append(.strokePath(spoke, style: style, black(alpha)))
            }
        }
    }
}
