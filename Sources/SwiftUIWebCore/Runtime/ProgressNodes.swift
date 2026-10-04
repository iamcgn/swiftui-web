// ProgressView nodes (Docs/elements/ProgressView.md): the linear bar and the ring/spinner,
// painted with the inactive-window greys the goldens show.

/// The linear bar: a 20 pt row as wide as proposed; an 8 pt pill track with the completed
/// fraction filled from the leading edge (an indeterminate bar shows a short pill at the start).
@MainActor
package final class ProgressBarNode: LeafNode<_ProgressBar>, _FrameSubscriber {
    /// The animation clock when the bar became indeterminate: its segment's phase counts from it.
    private var indeterminateStart: Double?

    override package init(_ context: _NodeContext<_ProgressBar>) {
        super.init(context)
        syncAnimation(previous: nil)
    }

    override package func update(view: _ProgressBar, environment: EnvironmentValues, force: Bool) {
        let previous = self.view.fraction
        super.update(view: view, environment: environment, force: force)
        syncAnimation(previous: previous)
    }

    /// Indeterminate: the segment travels while the bar shows (a frame subscription). A changed
    /// fraction animates under `withAnimation` (the `effect` tween).
    private func syncAnimation(previous: Double?) {
        if view.fraction == nil {
            if indeterminateStart == nil { indeterminateStart = runtime.animationClock }
            runtime.subscribeFrames(self)
        } else {
            indeterminateStart = nil
            runtime.unsubscribeFrames(self)
            if let previous, let fraction = view.fraction, previous != fraction, let animation = runtime.effectiveUpdateAnimation(for: self) {
                let from = presentation?.effect?.value(at: runtime.animationClock).first ?? previous
                let presentation = self.presentation ?? NodePresentation()
                presentation.effect = Tween(from: [from], to: [fraction], animation: animation, start: runtime.animationClock)
                self.presentation = presentation
                runtime.register(animating: self)
            }
        }
    }

    /// The fraction to paint: the tween's value while animating.
    package var presentedFraction: Double? {
        guard let fraction = view.fraction else { return nil }
        return presentation?.effect?.value(at: runtime.animationClock).first ?? fraction
    }

    package func frameDidAdvance() { runtime.setNeedsDisplay() }

    override package func unmount() {
        runtime.unsubscribeFrames(self)
        super.unmount()
    }

    /// The fill colour: iOS's accent (or tint); macOS's grey, or the tint in an active window.
    private var fillColor: RGBA {
        if PlatformMetrics.progressFillsWithAccent || runtime.windowIsActive {
            return (environment._tint ?? Color.accentColor).resolve(in: environment)
        }
        return environment._isDark ? PlatformMetrics.progressFillDark : environment._ink(PlatformMetrics.progressFillAlpha)
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? PlatformMetrics.progressBarIdealWidth
        return CGSize(width: width, height: PlatformMetrics.progressRowHeight)
    }

    override package var layoutSpacing: ViewSpacing { PlatformMetrics.controlsUsePlainSpacing ? ViewSpacing() : .plainControl }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        let height = PlatformMetrics.progressBarHeight
        let track = CGRect(x: bounds.minX, y: bounds.midY - height / 2, width: bounds.width, height: height)
        list.append(.fillRRect(track, cornerRadius: height / 2, PlatformMetrics.progressTrackColor ?? environment._ink(PlatformMetrics.progressTrackAlpha)))
        let fill = fillColor
        if let fraction = presentedFraction {
            let fillWidth = (track.width * CGFloat(fraction)).rounded()
            guard fillWidth > 0 else { return }
            list.append(.fillRRect(CGRect(x: track.minX, y: track.minY, width: max(fillWidth, height), height: height), cornerRadius: height / 2, fill))
        } else {
            // The segment starts at the leading edge (the goldens' first frame) and crosses the
            // track once a period, wrapping (approximate: the real motion is unmeasured).
            // iOS draws no segment (its metric is 0).
            guard PlatformMetrics.progressIndeterminateSegment > 0, track.width > 0 else { return }
            let segment = max(PlatformMetrics.progressIndeterminateSegment, height)
            let elapsed = runtime.animationClock - (indeterminateStart ?? runtime.animationClock)
            let phase = PlatformMetrics.progressIndeterminatePeriod > 0
                ? (elapsed / PlatformMetrics.progressIndeterminatePeriod).truncatingRemainder(dividingBy: 1) : 0
            let x = track.minX + (track.width - segment) * CGFloat(phase)
            list.append(.fillRRect(CGRect(x: x, y: track.minY, width: segment, height: height), cornerRadius: height / 2, fill))
        }
    }
}

/// The ring: a square of the diameter; a 5 pt track ring with the completed fraction stroked
/// clockwise from the top with round caps. Without a fraction, the spinner: eight rounded spokes
/// fading around the circle (its animation phase is fixed).
@MainActor
package final class ProgressRingNode: LeafNode<_ProgressRing>, _FrameSubscriber {
    /// The animation clock when the spinner started: the dark spoke steps clockwise from it.
    private var spinStart: Double?

    override package init(_ context: _NodeContext<_ProgressRing>) {
        super.init(context)
        syncAnimation(previous: nil)
    }

    override package func update(view: _ProgressRing, environment: EnvironmentValues, force: Bool) {
        let previous = self.view.fraction
        super.update(view: view, environment: environment, force: force)
        syncAnimation(previous: previous)
    }

    private func syncAnimation(previous: Double?) {
        if view.fraction == nil {
            if spinStart == nil { spinStart = runtime.animationClock }
            runtime.subscribeFrames(self)
        } else {
            spinStart = nil
            runtime.unsubscribeFrames(self)
            if let previous, let fraction = view.fraction, previous != fraction, let animation = runtime.effectiveUpdateAnimation(for: self) {
                let from = presentation?.effect?.value(at: runtime.animationClock).first ?? previous
                let presentation = self.presentation ?? NodePresentation()
                presentation.effect = Tween(from: [from], to: [fraction], animation: animation, start: runtime.animationClock)
                self.presentation = presentation
                runtime.register(animating: self)
            }
        }
    }

    package var presentedFraction: Double? {
        guard let fraction = view.fraction else { return nil }
        return presentation?.effect?.value(at: runtime.animationClock).first ?? fraction
    }

    /// Which spoke is the darkest now: the first at the start, then clockwise one step every
    /// `spinnerPeriod / spokes` (ProgressViewTests, approximate).
    package var spinnerPhase: Int {
        guard let spinStart, PlatformMetrics.spinnerPeriod > 0 else { return 0 }
        let elapsed = runtime.animationClock - spinStart
        let steps = Int((elapsed / PlatformMetrics.spinnerPeriod * Double(PlatformMetrics.spinnerSpokes)).rounded(.down))
        return ((steps % PlatformMetrics.spinnerSpokes) + PlatformMetrics.spinnerSpokes) % PlatformMetrics.spinnerSpokes
    }

    package func frameDidAdvance() { runtime.setNeedsDisplay() }

    override package func unmount() {
        runtime.unsubscribeFrames(self)
        super.unmount()
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        CGSize(width: view.diameter, height: view.diameter)
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let ink = environment; let black = { (alpha: Double) in ink._ink(alpha) }
        if let fraction = presentedFraction {
            let stroke = PlatformMetrics.progressRingStroke * view.diameter / PlatformMetrics.progressRingDiameter(.regular)
            let radius = view.diameter / 2 - stroke / 2
            var track = Path()
            track.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            list.append(.strokePath(track, style: StrokeStyle(lineWidth: stroke), black(PlatformMetrics.progressRingTrackAlpha)))
            guard fraction > 0 else { return }
            var arc = Path()
            arc.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
            let fillColor = runtime.windowIsActive ? (environment._tint ?? Color.accentColor).resolve(in: environment) : black(PlatformMetrics.progressRingFillAlpha)
            list.append(.strokePath(arc, style: StrokeStyle(lineWidth: stroke, lineCap: fraction < 1 ? .round : .butt), fillColor))
        } else {
            let scale = view.diameter / PlatformMetrics.progressRingDiameter(.regular)
            let inner = PlatformMetrics.spinnerInnerRadius * scale, outer = PlatformMetrics.spinnerOuterRadius * scale
            let style = StrokeStyle(lineWidth: PlatformMetrics.spinnerSpokeWidth * scale, lineCap: .round)
            let phase = spinnerPhase
            for index in 0..<PlatformMetrics.spinnerSpokes {
                // The darkest spoke points left at the start and steps clockwise; the others
                // fade clockwise behind it.
                let angle = Double.pi + Double(index + phase) * 2 * .pi / Double(PlatformMetrics.spinnerSpokes)
                let alpha = PlatformMetrics.spinnerMaxAlpha - (PlatformMetrics.spinnerMaxAlpha - PlatformMetrics.spinnerMinAlpha) * Double(index) / Double(PlatformMetrics.spinnerSpokes - 1)
                var spoke = Path()
                spoke.move(to: CGPoint(x: center.x + inner * CGFloat(_cos(angle)), y: center.y + inner * CGFloat(_sin(angle))))
                spoke.addLine(to: CGPoint(x: center.x + outer * CGFloat(_cos(angle)), y: center.y + outer * CGFloat(_sin(angle))))
                list.append(.strokePath(spoke, style: style, black(alpha)))
            }
        }
    }
}
