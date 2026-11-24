// CAEmitterLayer and CAEmitterCell (Docs/elements/UIKit/Layers.md, "Emitter layers"): a layer
// that emits particles of its cells while it is on screen. Each frame the scene's clock
// advances the layer (as it turns activity indicators): every cell gives birth at its birth
// rate (times the layer's), each particle moves at its velocity under the cell's acceleration
// and grows, fades, recolours and spins at the cell's speeds until its lifetime runs out; the
// layer then paints the living particles as the cell's `contents` image, centred on each
// particle at the particle's scale, angle and alpha.
//
// A value's range varies it uniformly either side of the cell's value (`velocity` ±
// `velocityRange`); the direction is `emissionLongitude` ± `emissionRange` in the layer's
// plane, so a range of π emits in every direction. The layer's coordinates are UIKit's, y
// down: a positive `yAcceleration` pulls particles down the screen. The random numbers come
// from the layer's `seed`, so a layer with the same cells and seed emits the same particles.

#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

public struct CAEmitterLayerEmitterShape: Hashable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let point = CAEmitterLayerEmitterShape(rawValue: "point")
    public static let line = CAEmitterLayerEmitterShape(rawValue: "line")
    public static let rectangle = CAEmitterLayerEmitterShape(rawValue: "rectangle")
    public static let cuboid = CAEmitterLayerEmitterShape(rawValue: "cuboid")
    public static let circle = CAEmitterLayerEmitterShape(rawValue: "circle")
    public static let sphere = CAEmitterLayerEmitterShape(rawValue: "sphere")
}

public struct CAEmitterLayerEmitterMode: Hashable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let points = CAEmitterLayerEmitterMode(rawValue: "points")
    public static let outline = CAEmitterLayerEmitterMode(rawValue: "outline")
    public static let surface = CAEmitterLayerEmitterMode(rawValue: "surface")
    public static let volume = CAEmitterLayerEmitterMode(rawValue: "volume")
}

public struct CAEmitterLayerRenderMode: Hashable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let unordered = CAEmitterLayerRenderMode(rawValue: "unordered")
    public static let oldestFirst = CAEmitterLayerRenderMode(rawValue: "oldestFirst")
    public static let oldestLast = CAEmitterLayerRenderMode(rawValue: "oldestLast")
    public static let backToFront = CAEmitterLayerRenderMode(rawValue: "backToFront")
    public static let additive = CAEmitterLayerRenderMode(rawValue: "additive")
}

/// The description of one kind of particle an emitter layer emits.
@preconcurrency @MainActor
open class CAEmitterCell {
    open var name: String?
    open var isEnabled = true
    /// Particles born per second (times the layer's `birthRate`).
    open var birthRate: Float = 0
    /// Seconds a particle lives, ± `lifetimeRange` (times the layer's `lifetime`).
    open var lifetime: Float = 0
    open var lifetimeRange: Float = 0
    /// The direction particles leave in, radians from the x axis in the layer's plane, ±
    /// `emissionRange`. The latitude (out of the plane) is kept and not used.
    open var emissionLatitude: CGFloat = 0
    open var emissionLongitude: CGFloat = 0
    open var emissionRange: CGFloat = 0
    /// Points per second, ± `velocityRange` (times the layer's `velocity`).
    open var velocity: CGFloat = 0
    open var velocityRange: CGFloat = 0
    /// Points per second per second.
    open var xAcceleration: CGFloat = 0
    open var yAcceleration: CGFloat = 0
    open var zAcceleration: CGFloat = 0
    /// The size the contents image is drawn at, ± `scaleRange`, changing by `scaleSpeed` a
    /// second (times the layer's `scale`).
    open var scale: CGFloat = 1
    open var scaleRange: CGFloat = 0
    open var scaleSpeed: CGFloat = 0
    /// Radians a second, ± `spinRange` (times the layer's `spin`).
    open var spin: CGFloat = 0
    open var spinRange: CGFloat = 0
    /// The colour the particle starts at (its alpha the particle's), each component ± its
    /// range, changing by its speed a second.
    open var color: CGColor? = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    open var redRange: Float = 0
    open var greenRange: Float = 0
    open var blueRange: Float = 0
    open var alphaRange: Float = 0
    open var redSpeed: Float = 0
    open var greenSpeed: Float = 0
    open var blueSpeed: Float = 0
    open var alphaSpeed: Float = 0
    /// The image each particle draws (a CGImage), and its part and pixels per point.
    open var contents: Any?
    open var contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    open var contentsScale: CGFloat = 1
    open var minificationFilter = "linear"
    open var magnificationFilter = "linear"
    open var minificationFilterBias: Float = 0
    /// Cells emitted by each particle: kept, and not emitted.
    open var emitterCells: [CAEmitterCell]?
    open var style: [AnyHashable: Any]?
    open var beginTime: Double = 0
    open var duration: Double = 0
    open var speed: Float = 1
    open var timeOffset: Double = 0
    open var repeatCount: Float = 0
    open var repeatDuration: Double = 0
    open var autoreverses = false

    public init() {}

    open class func defaultValue(forKey key: String) -> Any? { nil }
    open func shouldArchiveValue(forKey key: String) -> Bool { true }
}

/// A layer that emits, animates and draws particles of its cells.
@preconcurrency @MainActor
open class CAEmitterLayer: CALayer {
    open var emitterCells: [CAEmitterCell]? { didSet { startEmitting() } }
    /// Multipliers on every cell's values.
    open var birthRate: Float = 1 { didSet { startEmitting() } }
    open var lifetime: Float = 1
    open var velocity: Float = 1
    open var scale: Float = 1
    open var spin: Float = 1
    /// Where particles are born: the shape's centre, size and kind, in the layer's coordinates.
    open var emitterPosition = CGPoint.zero
    open var emitterZPosition: CGFloat = 0
    open var emitterSize = CGSize.zero
    open var emitterDepth: CGFloat = 0
    open var emitterShape: CAEmitterLayerEmitterShape = .point
    open var emitterMode: CAEmitterLayerEmitterMode = .volume
    open var renderMode: CAEmitterLayerRenderMode = .unordered
    open var preservesDepth = false
    /// The random numbers' seed: a new seed starts the sequence over.
    open var seed: UInt32 = 0 { didSet { random = EmitterRandom(seed: seed) } }

    public required init() { super.init() }
    public override init(layer: Any) {
        super.init(layer: layer)
        guard let other = layer as? CAEmitterLayer else { return }
        emitterCells = other.emitterCells
        birthRate = other.birthRate; lifetime = other.lifetime; velocity = other.velocity
        scale = other.scale; spin = other.spin
        emitterPosition = other.emitterPosition; emitterZPosition = other.emitterZPosition
        emitterSize = other.emitterSize; emitterDepth = other.emitterDepth
        emitterShape = other.emitterShape; emitterMode = other.emitterMode
        renderMode = other.renderMode; preservesDepth = other.preservesDepth; seed = other.seed
        random = EmitterRandom(seed: other.seed)
    }

    /// One living particle, in the layer's coordinates.
    struct Particle {
        var cell: Int
        var position: CGPoint
        var velocity: CGVector
        var acceleration: CGVector
        var age: Double = 0
        var lifetime: Double
        var scale: CGFloat
        var scaleSpeed: CGFloat
        var angle: CGFloat = 0
        var spin: CGFloat
        var color: (r: Float, g: Float, b: Float, a: Float)
        var colorSpeed: (r: Float, g: Float, b: Float, a: Float)
    }

    /// The living particles, oldest first.
    private(set) var particles: [Particle] = []
    /// The fraction of a particle each cell owes from the frames so far.
    private var owed: [ObjectIdentifier: Double] = [:]
    private var random = EmitterRandom(seed: 0)
    private var registered = false
    /// No more than this many particles live at once, whatever the rates.
    static let particleLimit = 4000

    /// Joins the scene's clock while there are particles to make or move.
    private func startEmitting() {
        guard !registered, isEmitting else { return }
        registered = true
        UIKitScene.shared.spinners.append(WeakActivityIndicator(view: self))
        UIKitScene.shared.setNeedsFrame()
    }

    private var isEmitting: Bool {
        birthRate > 0 && (emitterCells ?? []).contains { $0.isEnabled && $0.birthRate > 0 && $0.lifetime + $0.lifetimeRange > 0 }
    }

    /// Advances the particles by `elapsed` seconds: the old ones move and age, the dead go,
    /// and each cell's births for the interval join them, aged by when in it they were born.
    func step(_ elapsed: Double) {
        guard elapsed > 0 else { return }
        let dt = CGFloat(elapsed)
        for i in particles.indices {
            var p = particles[i]
            p.age += elapsed
            p.velocity.dx += p.acceleration.dx * dt
            p.velocity.dy += p.acceleration.dy * dt
            p.position.x += p.velocity.dx * dt
            p.position.y += p.velocity.dy * dt
            p.scale += p.scaleSpeed * dt
            p.angle += p.spin * dt
            p.color.r += p.colorSpeed.r * Float(elapsed)
            p.color.g += p.colorSpeed.g * Float(elapsed)
            p.color.b += p.colorSpeed.b * Float(elapsed)
            p.color.a += p.colorSpeed.a * Float(elapsed)
            particles[i] = p
        }
        particles.removeAll { $0.age >= $0.lifetime }
        for (index, cell) in (emitterCells ?? []).enumerated() where cell.isEnabled {
            let rate = Double(cell.birthRate) * Double(birthRate)
            guard rate > 0 else { owed[ObjectIdentifier(cell)] = 0; continue }
            let due = (owed[ObjectIdentifier(cell)] ?? 0) + rate * elapsed
            let births = Int(due)
            owed[ObjectIdentifier(cell)] = due - Double(births)
            for n in 0..<births where particles.count < Self.particleLimit {
                // Spread over the interval: the first born ages longest.
                let age = elapsed * (1 - (Double(n) + 0.5) / Double(births))
                if let particle = born(cell, index: index, age: age) { particles.append(particle) }
            }
        }
    }

    private func born(_ cell: CAEmitterCell, index: Int, age: Double) -> Particle? {
        let life = Double(max(0, (cell.lifetime + cell.lifetimeRange * random.signed()) * lifetime))
        guard life > age else { return nil }
        let direction = cell.emissionLongitude + cell.emissionRange * CGFloat(random.signed())
        let speed = (cell.velocity + cell.velocityRange * CGFloat(random.signed())) * CGFloat(velocity)
        let rgba = cell.color.flatMap { RGBA(cgColor: $0) } ?? RGBA(r: 255, g: 255, b: 255)
        func component(_ value: Double, _ range: Float) -> Float { min(1, max(0, Float(value) + range * random.signed())) }
        var particle = Particle(
            cell: index,
            position: birthPoint(),
            velocity: CGVector(dx: speed * CGFloat(_cos(Double(direction))), dy: speed * CGFloat(_sin(Double(direction)))),
            acceleration: CGVector(dx: cell.xAcceleration, dy: cell.yAcceleration),
            lifetime: life,
            scale: (cell.scale + cell.scaleRange * CGFloat(random.signed())) * CGFloat(scale),
            scaleSpeed: cell.scaleSpeed * CGFloat(scale),
            spin: (cell.spin + cell.spinRange * CGFloat(random.signed())) * CGFloat(spin),
            color: (component(rgba.red, cell.redRange), component(rgba.green, cell.greenRange), component(rgba.blue, cell.blueRange), component(rgba.alpha, cell.alphaRange)),
            colorSpeed: (cell.redSpeed, cell.greenSpeed, cell.blueSpeed, cell.alphaSpeed))
        // Born `age` seconds ago: moved on by then.
        let t = CGFloat(age)
        particle.age = age
        particle.position.x += particle.velocity.dx * t + particle.acceleration.dx * t * t / 2
        particle.position.y += particle.velocity.dy * t + particle.acceleration.dy * t * t / 2
        particle.velocity.dx += particle.acceleration.dx * t
        particle.velocity.dy += particle.acceleration.dy * t
        particle.scale += particle.scaleSpeed * t
        particle.angle = particle.spin * t
        particle.color.a += particle.colorSpeed.a * Float(age)
        return particle
    }

    /// A point of the emitter shape: the centre for a point, else one on the line, in the
    /// rectangle or circle (or on its edge for the outline mode).
    private func birthPoint() -> CGPoint {
        let c = emitterPosition, w = emitterSize.width, h = emitterSize.height
        switch emitterShape {
        case .line:
            return CGPoint(x: c.x + w / 2 * CGFloat(random.signed()), y: c.y)
        case .rectangle, .cuboid:
            if emitterMode == .outline {
                let perimeter = 2 * (w + h)
                guard perimeter > 0 else { return c }
                var d = CGFloat(random.unit()) * perimeter
                if d < w { return CGPoint(x: c.x - w / 2 + d, y: c.y - h / 2) }
                d -= w
                if d < h { return CGPoint(x: c.x + w / 2, y: c.y - h / 2 + d) }
                d -= h
                if d < w { return CGPoint(x: c.x + w / 2 - d, y: c.y + h / 2) }
                return CGPoint(x: c.x - w / 2, y: c.y + h / 2 - (d - w))
            }
            return CGPoint(x: c.x + w / 2 * CGFloat(random.signed()), y: c.y + h / 2 * CGFloat(random.signed()))
        case .circle, .sphere:
            let radius = w / 2
            let angle = CGFloat(random.unit()) * 2 * .pi
            let r = emitterMode == .outline ? radius : radius * CGFloat(random.unit()).squareRoot()
            return CGPoint(x: c.x + r * CGFloat(_cos(Double(angle))), y: c.y + r * CGFloat(_sin(Double(angle))))
        default:
            return c
        }
    }

    /// Paints the living particles over the layer, each cell's contents image centred on the
    /// particle at its scale, turned by its angle, at its alpha; oldest last for that order.
    func paintParticles(into list: inout DisplayList, context: PaintContext) {
        startEmitting()
        let cells = emitterCells ?? []
        let ordered = renderMode == .oldestLast ? Array(particles.reversed()) : particles
        if renderMode == .additive { list.append(.beginGroup(opacity: 1)) }
        for particle in ordered {
            guard cells.indices.contains(particle.cell), particle.color.a > 0, particle.scale > 0 else { continue }
            let cell = cells[particle.cell]
            #if !canImport(CoreGraphics) || os(WASI)
            guard let image = cell.contents as? CGImage else { continue }
            let pixels = cell.contentsScale > 0 ? cell.contentsScale : 1
            let size = CGSize(width: CGFloat(image.width) / pixels * particle.scale, height: CGFloat(image.height) / pixels * particle.scale)
            let center = context.absoluteRect(CGRect(origin: particle.position, size: .zero)).origin
            let alpha = Double(min(1, particle.color.a))
            if alpha < 1 { list.append(.beginGroup(opacity: alpha)) }
            list.append(.save)
            list.append(.concat(CGAffineTransform(translationX: center.x, y: center.y).rotated(by: particle.angle)))
            for command in image._commands(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)) { list.append(command) }
            list.append(.restore)
            if alpha < 1 { list.append(.endGroup) }
            #else
            _ = cell
            #endif
        }
        if renderMode == .additive { list.append(.endGroup) }
    }
}

extension CAEmitterLayer: ClockAnimating {
    /// Particles to make or move: the scene keeps the frames coming.
    var isAnimating: Bool {
        let animating = isEmitting || !particles.isEmpty
        if !animating { registered = false }
        return animating
    }

    func advance(elapsed: Double) {
        step(elapsed)
        setNeedsDisplay()
    }
}

/// The emitter's random numbers: a xorshift sequence from the layer's seed.
struct EmitterRandom {
    private var state: UInt64
    init(seed: UInt32) { state = UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 | 1 }
    /// A number in 0..<1.
    mutating func unit() -> Float {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Float(state >> 40) / Float(1 << 24)
    }
    /// A number in -1..<1.
    mutating func signed() -> Float { unit() * 2 - 1 }
}
