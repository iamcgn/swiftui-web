/// A resolved gradient for the display list, in absolute coordinates.
public struct DisplayGradient: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case linear(start: CGPoint, end: CGPoint)
        case radial(center: CGPoint, startRadius: CGFloat, endRadius: CGFloat)
        /// A radial gradient between two circles that need not share a centre (CoreGraphics's
        /// `drawRadialGradient`, Canvas2D's `createRadialGradient`).
        case focalRadial(startCenter: CGPoint, startRadius: CGFloat, endCenter: CGPoint, endRadius: CGFloat)
        case angular(center: CGPoint, startAngle: Double)
    }

    public struct Stop: Equatable, Sendable {
        public var location: Double
        public var color: RGBA
        public init(location: Double, color: RGBA) {
            self.location = location
            self.color = color
        }
    }

    public var kind: Kind
    public var stops: [Stop]

    public init(kind: Kind, stops: [Stop]) {
        self.kind = kind
        self.stops = stops
    }
}
