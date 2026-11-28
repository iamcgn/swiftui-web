// Shaders: an app's shader calls build (ShaderLibrary's dynamic members, the argument kinds, the
// three effects on a view and on a visual effect, a shader as a fill). A view under a shader effect
// paints as it would without it, a shader fill paints nothing, and compile(as:) throws.
import Testing
import SwiftUI
import SwiftUIWebCore

#if !os(WASI)
@Suite @MainActor struct ShaderTests {
    private func commands<V: View>(_ view: V) -> [DisplayCommand] {
        let r = Runtime()
        r.mount(view)
        r.layout(in: CGSize(width: 100, height: 100))
        return r.render(scale: 2).commands
    }

    private func visibleFills(_ commands: [DisplayCommand]) -> Int {
        commands.filter {
            switch $0 {
            case .fillRect(_, let c), .fillRRect(_, _, let c), .fillPath(_, let c, _): c.alpha > 0
            case .fillGradient: true
            default: false
            }
        }.count
    }

    @Test func aLibrarysMembersAreItsFunctions() {
        let shader = ShaderLibrary.reelBlur(.float(2.5), .float2(CGSize(width: 3, height: 4)), .boundingRect)
        #expect(shader.function.name == "reelBlur")
        #expect(shader.function.library == .default)
        #expect(shader.arguments == [.float(2.5), .float2(3, 4), .boundingRect])
        #expect(shader.arguments != [.float(2.5), .float2(4, 3), .boundingRect])
        let other = ShaderLibrary(data: Data([1, 2, 3])).ripple()
        #expect(other.function.library != .default)
        #expect(other.function == ShaderFunction(library: ShaderLibrary(data: Data([1, 2, 3])), name: "ripple"))
        #expect(Shader(function: other.function, arguments: [.color(.red), .floatArray([1, 2])]).arguments.count == 2)
    }

    @Test func aViewUnderAShaderEffectPaintsAsWithoutIt() {
        let plain = commands(Color.red.frame(width: 40, height: 40))
        let shader = ShaderLibrary.shine(.float2(CGPoint(x: 1, y: 2)), .float(0))
        #expect(commands(Color.red.frame(width: 40, height: 40).colorEffect(shader)) == plain)
        #expect(commands(Color.red.frame(width: 40, height: 40).distortionEffect(shader, maxSampleOffset: .zero)) == plain)
        #expect(commands(Color.red.frame(width: 40, height: 40).layerEffect(shader, maxSampleOffset: CGSize(width: 4, height: 4))) == plain)
        let viaVisualEffect = commands(Color.red.frame(width: 40, height: 40).visualEffect { content, proxy in
            content.layerEffect(ShaderLibrary.reelDrum(.float2(proxy.size)), maxSampleOffset: .zero).opacity(0.5)
        })
        #expect(viaVisualEffect.contains { if case .beginGroup(let o) = $0 { o == 0.5 } else { false } })
    }

    @Test func aShaderFillPaintsNothing() {
        #expect(visibleFills(commands(Rectangle().fill(Color.red).frame(width: 40, height: 40))) == 1)
        #expect(visibleFills(commands(Rectangle().fill(ShaderLibrary.sky(.float(1))).frame(width: 40, height: 40))) == 0)
    }

    @Test func compilingAShaderThrows() async {
        await #expect(throws: _ShaderUnavailable.self) {
            try await ShaderLibrary.memberCardPaper().compile(as: .colorEffect)
        }
    }
}
#endif
