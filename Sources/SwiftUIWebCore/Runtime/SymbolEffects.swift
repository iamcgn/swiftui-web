// Symbol effects on the image node: effects requested by the environment run on the animation
// clock (frame subscription) and paint the glyph with a scale, rotation, offset or opacity.

extension ImageNode {
    /// Starts, keeps or stops the effects the environment asks for.
    package func updateSymbolEffects() {
        guard case .system = view.source else { return }
        let requests = environment._symbolEffects
        let now = runtime.animationClock
        var running = runningEffects
        // Indefinite effects run while active; a request that disappeared or went inactive stops.
        running.removeAll { effect in
            !effect.discrete && !requests.contains { $0.kind == effect.request.kind && $0.isActive == true && $0.options == effect.request.options }
        }
        for request in requests {
            if let active = request.isActive {
                if active, !running.contains(where: { !$0.discrete && $0.request.kind == request.kind && $0.request.options == request.options }) {
                    running.append(RunningEffect(request: request, start: now, discrete: false))
                }
            } else {
                // Discrete: play once per generation change (the first sight of a value does not play).
                let seen = seenGenerations[request.kind]
                seenGenerations[request.kind] = request.generation
                if let seen, seen != request.generation {
                    running.removeAll { $0.discrete && $0.request.kind == request.kind }
                    running.append(RunningEffect(request: request, start: now, discrete: true))
                }
            }
        }
        runningEffects = running
        if running.isEmpty { runtime.unsubscribeFrames(self) } else { runtime.subscribeFrames(self) }
    }

    package func frameDidAdvance() {
        let now = runtime.animationClock
        runningEffects.removeAll { effect in
            guard effect.discrete else { return false }
            let cycle = Self.cycleDuration(effect.request.kind) / effect.request.options.speed
            guard let count = effect.request.options.repeatCount else { return false }
            return now - effect.start >= cycle * Double(count)
        }
        if runningEffects.isEmpty { runtime.unsubscribeFrames(self) }
        runtime.setNeedsDisplay()
    }

    /// How long one play of an effect takes, in seconds.
    package static func cycleDuration(_ kind: _SymbolEffectKind) -> Double {
        switch kind {
        case .bounce: return 0.5
        case .pulse: return 1.0
        case .variableColor: return 1.2
        case .scale: return 0.35
        case .wiggle: return 0.6
        case .rotate: return 1.0
        case .breathe: return 1.4
        case .appear, .disappear, .replace: return 0.35
        }
    }

    /// The transform (about the glyph's centre) and opacity the running effects give now.
    package func symbolEffectPresentation() -> (transform: CGAffineTransform, opacity: Double) {
        var transform = CGAffineTransform.identity
        var opacity = 1.0
        let now = runtime.animationClock
        for effect in runningEffects {
            let options = effect.request.options
            let cycle = Self.cycleDuration(effect.request.kind) / options.speed
            let elapsed = now - effect.start
            let plays = elapsed / cycle
            if effect.discrete, let count = options.repeatCount, plays >= Double(count) { continue }
            let phase = plays - plays.rounded(.down)     // 0..<1 within the current play
            let wave = _sin(phase * .pi)                  // 0 → 1 → 0
            switch effect.request.kind {
            case .bounce(let up):
                // A quick lift with overshoot, then back.
                let lift = phase < 0.5 ? _sin(phase * .pi) : _sin(phase * .pi) * 0.6
                let scale = 1 + 0.25 * lift
                transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
                    .concatenating(CGAffineTransform(translationX: 0, y: (up ? -1 : 1) * 4 * lift))
            case .pulse:
                opacity *= 1 - 0.6 * wave
            case .variableColor(let reversing):
                // Layers lighting up in turn, as three opacity steps (reversing plays them back down).
                let steps = 3.0
                let step = (reversing ? (phase < 0.5 ? phase * 2 : (1 - phase) * 2) : phase) * steps
                opacity *= 0.4 + 0.6 * (step.rounded(.down) + 1) / steps
            case .scale(let up):
                // Settles at the scaled size with a short ease.
                let settle = min(1, elapsed / cycle)
                let scale = 1 + (up ? 0.2 : -0.2) * (1 - (1 - settle) * (1 - settle) * (1 - settle))
                transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
            case .wiggle(let clockwise, let horizontal):
                let swing = _sin(phase * 2 * .pi) * (1 - phase * 0.5)
                if let clockwise {
                    transform = transform.concatenating(CGAffineTransform(rotationAngle: (clockwise ? 1 : -1) * 0.12 * swing))
                } else if horizontal {
                    transform = transform.concatenating(CGAffineTransform(translationX: 3 * swing, y: 0))
                } else {
                    transform = transform.concatenating(CGAffineTransform(translationX: 0, y: 3 * swing))
                }
            case .rotate(let clockwise):
                transform = transform.concatenating(CGAffineTransform(rotationAngle: (clockwise ? 1 : -1) * 2 * .pi * phase))
            case .breathe:
                let scale = 1 + 0.1 * wave
                transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
                opacity *= 1 - 0.2 * wave
            case .appear, .disappear, .replace:
                break
            }
        }
        return (transform, opacity)
    }
}
