// Gauge nodes (Docs/elements/Gauge.md): the capacity bars, the accessory track with its knob,
// and the accessory rings, painted with the greys, the tint and the marker the goldens show.

/// A gauge bar, as wide as proposed. Capacity: a 16 pt bar with 1.5 pt corners, the track black
/// 18/255 and the fraction filled in the tint (green by default). Accessory capacity: an 8 pt
/// capsule, black 15/255 under black 85/255. Accessory linear: an 8 pt capsule track in the
/// primary black with a knob (a 4 pt-radius dot in an 8 pt-radius white halo) at the fraction.
@MainActor
package final class GaugeBarNode: LeafNode<_GaugeBar> {
    private var height: CGFloat {
        view.kind == .capacity ? PlatformMetrics.gaugeBarHeight : PlatformMetrics.gaugeAccessoryBarHeight
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? PlatformMetrics.progressBarIdealWidth
        return CGSize(width: width, height: height)
    }

    override package var layoutSpacing: ViewSpacing { .plainControl }

    private func black(_ alpha: Double) -> RGBA { RGBA(red: 0, green: 0, blue: 0, alpha: alpha) }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        let fraction = CGFloat(min(max(view.fraction, 0), 1))
        switch view.kind {
        case .capacity:
            let radius = PlatformMetrics.gaugeBarCornerRadius
            list.append(.fillRRect(bounds, cornerRadius: radius, black(PlatformMetrics.gaugeTrackAlpha)))
            let width = bounds.width * fraction
            guard width > 0 else { return }
            let tint = (environment._tint ?? Color.green).resolve(in: environment)
            list.append(.fillRRect(CGRect(x: bounds.minX, y: bounds.minY, width: max(width, 2 * radius), height: bounds.height), cornerRadius: radius, tint))
        case .accessoryCapacity:
            let radius = bounds.height / 2
            list.append(.fillRRect(bounds, cornerRadius: radius, black(PlatformMetrics.progressTrackAlpha)))
            let width = bounds.width * fraction
            guard width > 0 else { return }
            list.append(.fillRRect(CGRect(x: bounds.minX, y: bounds.minY, width: max(width, bounds.height), height: bounds.height), cornerRadius: radius,
                                   black(PlatformMetrics.progressFillAlpha)))
        case .accessoryLinear:
            let radius = bounds.height / 2
            list.append(.fillRRect(bounds, cornerRadius: radius, black(PlatformMetrics.gaugePrimaryAlpha)))
            let knob = PlatformMetrics.gaugeKnobRadius, halo = PlatformMetrics.gaugeKnobHaloRadius
            let x = bounds.minX + knob + (bounds.width - 2 * knob) * fraction
            list.append(.fillRRect(CGRect(x: x - halo, y: bounds.midY - halo, width: 2 * halo, height: 2 * halo), cornerRadius: halo,
                                   RGBA(red: 1, green: 1, blue: 1, alpha: 1)))
            list.append(.fillRRect(CGRect(x: x - knob, y: bounds.midY - knob, width: 2 * knob, height: 2 * knob), cornerRadius: knob,
                                   black(PlatformMetrics.gaugePrimaryAlpha)))
        }
    }
}

/// The accessory ring: a 58 pt square with a 6 pt ring at radius 26. Open: an arc of 270°
/// centred on the bottom (242° with bounds labels), round caps, in the primary black, with the
/// marker (a 2.5 pt dot in a 4.5 pt white halo) at the fraction along it. Capacity: a black
/// 30 % track ring under the primary arc from the top, clockwise, round-capped.
@MainActor
package final class GaugeRingNode: LeafNode<_GaugeRing> {
    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        CGSize(width: PlatformMetrics.gaugeRingDiameter, height: PlatformMetrics.gaugeRingDiameter)
    }

    /// Screen angles (clockwise, 0 at the right): the open arc starts at the bottom left.
    package var arc: (start: Double, sweep: Double) {
        let trim = view.trimmed ? PlatformMetrics.gaugeRingTrimDegrees : 0
        return (135 + trim, 270 - 2 * trim)
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = PlatformMetrics.gaugeRingRadius
        let stroke = StrokeStyle(lineWidth: PlatformMetrics.gaugeRingStroke, lineCap: .round)
        let primary = RGBA(red: 0, green: 0, blue: 0, alpha: PlatformMetrics.gaugePrimaryAlpha)
        let fraction = min(max(view.fraction, 0), 1)
        if view.capacity {
            var track = Path()
            track.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
            list.append(.strokePath(track, style: StrokeStyle(lineWidth: PlatformMetrics.gaugeRingStroke), RGBA(red: 0, green: 0, blue: 0, alpha: PlatformMetrics.gaugeRingTrackAlpha)))
            guard fraction > 0 else { return }
            var arc = Path()
            arc.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
            list.append(.strokePath(arc, style: stroke, primary))
        } else {
            let (start, sweep) = arc
            var path = Path()
            path.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(start + sweep), clockwise: false)
            list.append(.strokePath(path, style: stroke, primary))
            let angle = (start + sweep * fraction) * .pi / 180
            let marker = CGPoint(x: center.x + radius * CGFloat(_cos(angle)), y: center.y + radius * CGFloat(_sin(angle)))
            let halo = PlatformMetrics.gaugeMarkerHaloRadius, dot = PlatformMetrics.gaugeMarkerRadius
            list.append(.fillRRect(CGRect(x: marker.x - halo, y: marker.y - halo, width: 2 * halo, height: 2 * halo), cornerRadius: halo,
                                   RGBA(red: 1, green: 1, blue: 1, alpha: 1)))
            list.append(.fillRRect(CGRect(x: marker.x - dot, y: marker.y - dot, width: 2 * dot, height: 2 * dot), cornerRadius: dot, primary))
        }
    }
}
