// Layer effect fixtures: `shadow` paints outside the frame without changing layout, `zIndex`
// reorders overlapping siblings, and `hidden` keeps a view's space while drawing nothing.
import SwiftUI
import FixtureKit

public enum EffectsFixtures {
    public static let shadow = Fixture("effects/shadow", size: CGSize(width: 360, height: 260)) {
        VStack(spacing: 50) {
            HStack(spacing: 60) {
                Color.red.frame(width: 60, height: 60).shadow(radius: 8).probe("default")
                Color.blue.frame(width: 60, height: 60).shadow(color: .black, radius: 4, x: 6).probe("offset")
                Circle().fill(Color.green).frame(width: 60, height: 60).shadow(color: .blue.opacity(0.5), radius: 0, x: 4).probe("hard")
            }
            .probe("row1")
            HStack(spacing: 60) {
                Text("Shadow").font(.title).shadow(radius: 2).probe("text")
                RoundedRectangle(cornerRadius: 12).fill(Color.orange).frame(width: 90, height: 50).shadow(color: .purple, radius: 12).probe("rounded")
                Color.gray.frame(width: 60, height: 60).opacity(0.5).shadow(radius: 6).probe("faded")
            }
            .probe("row2")
        }
        .probe("stack")
    }

    /// Black squares on a transparent background: the golden's alpha across each edge gives
    /// the blur profile (Docs/elements/Effects.md).
    public static let shadowProfile = Fixture("effects/shadow-profile", size: CGSize(width: 360, height: 160)) {
        HStack(spacing: 60) {
            Color.black.frame(width: 60, height: 60).shadow(color: .black, radius: 10).probe("blur10")
            Color.black.frame(width: 60, height: 60).shadow(color: .black, radius: 4, x: 10).probe("blur4")
            Color.black.frame(width: 60, height: 60).shadow(color: .red, radius: 0, x: 5).probe("sharp")
        }
        .probe("row")
    }

    /// Vertical offsets. The harness's offscreen window draws them upwards (a CoreGraphics
    /// base-space offset), unlike a window on screen, so this fixture's pixels are not compared.
    public static let shadowOffset = Fixture("effects/shadow-offset", size: CGSize(width: 360, height: 160)) {
        HStack(spacing: 60) {
            Color.blue.frame(width: 60, height: 60).shadow(color: .black, radius: 4, x: 6, y: 6).probe("offset")
            Color.black.frame(width: 60, height: 60).shadow(color: .red, radius: 0, x: 5, y: 5).probe("sharp")
            Text("Shadow").font(.title).shadow(radius: 2, y: 2).probe("text")
        }
        .probe("row")
    }

    public static let zIndex = Fixture("effects/zindex", size: CGSize(width: 320, height: 240)) {
        VStack(spacing: 30) {
            ZStack {
                Color.red.frame(width: 80, height: 80).offset(x: -25, y: -15).zIndex(2).probe("red")
                Color.blue.frame(width: 80, height: 80).probe("blue")
                Color.green.frame(width: 80, height: 80).offset(x: 25, y: 15).zIndex(1).probe("green")
                Color.yellow.frame(width: 120, height: 120).zIndex(-1).probe("yellow")
            }
            .probe("zstack")
            HStack(spacing: -30) {
                Color.orange.frame(width: 70, height: 50).probe("first")
                Color.purple.frame(width: 70, height: 50).zIndex(1).probe("middle")
                Color.mint.frame(width: 70, height: 50).probe("last")
            }
            .probe("hstack")
        }
        .probe("stack")
    }

    public static let hidden = Fixture("effects/hidden", size: CGSize(width: 240, height: 200)) {
        VStack(spacing: 10) {
            Text("Above").probe("above")
            Color.red.frame(width: 80, height: 30).hidden().probe("hidden")
            Text("Below").probe("below")
            HStack(spacing: 8) {
                Button("Ghost") {}.hidden().probe("ghostButton")
                Color.blue.frame(width: 40, height: 20).probe("visible")
            }
            .probe("row")
            Color.green.frame(width: 60, height: 20).opacity(0).probe("transparent")
        }
        .probe("stack")
    }


    // MARK: Colour effects

    /// Known sRGB inputs for measuring the colour filters (Docs/elements/Effects.md).
    static let samples: [Color] = [
        Color(red: 0.8, green: 0.4, blue: 0.2),
        Color(red: 0.2, green: 0.6, blue: 0.9),
        Color(red: 0.5, green: 0.5, blue: 0.5),
        Color(red: 1, green: 0, blue: 0),
        Color(red: 0.8, green: 0.4, blue: 0.2).opacity(0.5),
    ]

    static func swatchGrid<V: View>(_ name: String, columns: [String], @ViewBuilder cell: @escaping @Sendable (Color, Int) -> V) -> Fixture {
        Fixture(name, size: CGSize(width: 40 * columns.count + 20, height: 40 * samples.count + 20), content: {
            VStack(spacing: 10) {
                ForEach(0..<samples.count, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(0..<columns.count, id: \.self) { column in
                            cell(samples[row], column).frame(width: 30, height: 30).probe("\(columns[column])-\(row)")
                        }
                    }
                }
            }
            .probe("grid")
        }).rasterized()
    }

    public static let brightness = swatchGrid("effects/brightness", columns: ["plain", "b02", "b05", "bneg", "c05", "c15", "c2"]) { color, column in
        switch column {
        case 0: color
        case 1: color.brightness(0.2)
        case 2: color.brightness(0.5)
        case 3: color.brightness(-0.3)
        case 4: color.contrast(0.5)
        case 5: color.contrast(1.5)
        default: color.contrast(2)
        }
    }

    public static let saturation = swatchGrid("effects/saturation", columns: ["plain", "s05", "s2", "s025", "g05", "g1", "h90", "h200"]) { color, column in
        switch column {
        case 0: color
        case 1: color.saturation(0.5)
        case 2: color.saturation(2)
        case 3: color.saturation(0.25)
        case 4: color.grayscale(0.5)
        case 5: color.grayscale(1)
        case 6: color.hueRotation(.degrees(90))
        default: color.hueRotation(.degrees(200))
        }
    }

    public static let colorMap = swatchGrid("effects/color-map", columns: ["plain", "invert", "mulBlue", "mulHalf", "lumAlpha", "chain"]) { color, column in
        switch column {
        case 0: color
        case 1: color.colorInvert()
        case 2: color.colorMultiply(Color(red: 0, green: 0.5, blue: 1))
        case 3: color.colorMultiply(Color(red: 1, green: 1, blue: 1).opacity(0.5))
        case 4: color.luminanceToAlpha()
        default: color.saturation(0).brightness(0.2).colorInvert()
        }
    }

    /// Effects over a coloured background and on text: the alpha-changing filters composite
    /// with what is behind, and text keeps its layout.
    public static let colorText = Fixture("effects/color-text", size: CGSize(width: 360, height: 200), content: {
        ZStack {
            Color(red: 0.1, green: 0.2, blue: 0.3).frame(width: 340, height: 180).probe("background")
            VStack(spacing: 12) {
                HStack(spacing: 20) {
                    Text("Bright").font(.title).foregroundStyle(Color(red: 0.8, green: 0.4, blue: 0.2)).brightness(0.3).probe("bright")
                    Text("Gray").font(.title).foregroundStyle(Color(red: 0.8, green: 0.4, blue: 0.2)).grayscale(1).probe("gray")
                    Text("Invert").font(.title).foregroundStyle(Color(red: 0.8, green: 0.4, blue: 0.2)).colorInvert().probe("invert")
                }
                .probe("row1")
                HStack(spacing: 20) {
                    Circle().fill(Color(red: 0.8, green: 0.4, blue: 0.2)).frame(width: 40, height: 40).luminanceToAlpha().probe("lumCircle")
                    Text("Hue").padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(Color(red: 0.9, green: 0.2, blue: 0.3))).hueRotation(.degrees(120)).probe("capsule")
                    Image(systemName: "star.fill").font(.largeTitle).foregroundStyle(Color.yellow).saturation(0).probe("symbol")
                    RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.2, green: 0.6, blue: 0.9)).frame(width: 60, height: 40).colorMultiply(Color(red: 1, green: 0.5, blue: 0.5)).probe("multiplied")
                }
                .probe("row2")
            }
            .probe("stack")
        }
        .probe("zstack")
    }).rasterized()

    /// Gaussian blur: the edge profile of a square, `opaque`, text, and the frame it keeps.
    public static let blur = Fixture("effects/blur", size: CGSize(width: 360, height: 200), content: {
        VStack(spacing: 30) {
            HStack(spacing: 50) {
                Color.black.frame(width: 50, height: 50).blur(radius: 6).probe("blur6")
                Color(red: 0.8, green: 0.4, blue: 0.2).frame(width: 50, height: 50).blur(radius: 3, opaque: true).probe("opaque3")
                Color.blue.frame(width: 50, height: 50).blur(radius: 0).probe("blur0")
            }
            .probe("row1")
            HStack(spacing: 30) {
                Text("Blurred").font(.title).blur(radius: 2).probe("text")
                HStack(spacing: 0) {
                    Color.red.frame(width: 30, height: 40)
                    Color.green.frame(width: 30, height: 40)
                }
                .blur(radius: 4)
                .probe("pair")
            }
            .probe("row2")
        }
        .probe("stack")
    }).rasterized()

    /// Blend modes over a two-colour background.
    static let blendModes: [(String, BlendMode)] = [
        ("normal", .normal), ("multiply", .multiply), ("screen", .screen), ("overlay", .overlay), ("darken", .darken), ("lighten", .lighten),
        ("colorDodge", .colorDodge), ("colorBurn", .colorBurn), ("softLight", .softLight), ("hardLight", .hardLight), ("difference", .difference),
        ("exclusion", .exclusion), ("hue", .hue), ("saturation", .saturation), ("color", .color), ("luminosity", .luminosity),
        ("sourceAtop", .sourceAtop), ("destinationOver", .destinationOver), ("destinationOut", .destinationOut), ("plusDarker", .plusDarker), ("plusLighter", .plusLighter),
    ]

    public static let blend = Fixture("effects/blend", size: CGSize(width: 380, height: 220), content: {
        ZStack {
            HStack(spacing: 0) {
                Color(red: 0.2, green: 0.6, blue: 0.9).frame(width: 160)
                Color(red: 0.9, green: 0.9, blue: 0.2).frame(width: 200)
            }
            .probe("background")
            VStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { column in
                            let index = row * 7 + column
                            Color(red: 0.8, green: 0.4, blue: 0.2).opacity(index == 20 ? 0.5 : 1)
                                .frame(width: 44, height: 44)
                                .blendMode(blendModes[index].1)
                                .probe(blendModes[index].0)
                        }
                    }
                }
            }
            .probe("grid")
        }
        .frame(width: 380, height: 220)
        .probe("zstack")
    }).rasterized()

    // MARK: Masks and compositing

    /// `mask`: the content shows through the mask's alpha; the mask is laid out like an overlay.
    public static let mask = Fixture("effects/mask", size: CGSize(width: 400, height: 220), content: {
        VStack(spacing: 30) {
            HStack(spacing: 30) {
                Color.red.frame(width: 80, height: 80).mask { Circle() }.probe("circle")
                LinearGradient(colors: [.blue, .green], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 120, height: 80)
                    .mask { Text("Mask").font(.system(size: 40, weight: .bold)) }
                    .probe("gradientText")
                Color.blue.frame(width: 80, height: 80).mask(alignment: .topLeading) { Rectangle().frame(width: 40, height: 40) }.probe("aligned")
            }
            .probe("row1")
            HStack(spacing: 30) {
                Color.green.frame(width: 80, height: 80).mask { Circle().opacity(0.5) }.probe("half")
                Color.purple.frame(width: 120, height: 50)
                    .mask { LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing) }
                    .probe("fade")
                Text("Masked text").mask { Rectangle().frame(width: 50) }.probe("text")
            }
            .probe("row2")
        }
        .probe("stack")
    }).rasterized()

    /// Two overlapping circles under an effect, with and without a compositing group: SwiftUI
    /// applies opacity, shadows and blend modes to each element unless the group composites them.
    static func pair() -> some View {
        ZStack {
            Circle().fill(Color.red).frame(width: 50, height: 50).offset(x: -12)
            Circle().fill(Color.blue).frame(width: 50, height: 50).offset(x: 12)
        }
        .frame(width: 80, height: 60)
    }

    public static let compositing = Fixture("effects/compositing", size: CGSize(width: 420, height: 300), content: {
        ZStack {
            Color(red: 0.9, green: 0.9, blue: 0.6).frame(width: 400, height: 280)
            VStack(spacing: 20) {
                HStack(spacing: 20) {
                    pair().opacity(0.5).probe("opacity")
                    pair().compositingGroup().opacity(0.5).probe("opacityGroup")
                    pair().shadow(color: .black, radius: 3, x: 6).probe("shadow")
                    pair().compositingGroup().shadow(color: .black, radius: 3, x: 6).probe("shadowGroup")
                }
                .probe("row1")
                HStack(spacing: 20) {
                    pair().blendMode(.multiply).probe("blend")
                    pair().compositingGroup().blendMode(.multiply).probe("blendGroup")
                    pair().blur(radius: 3).probe("blur")
                    pair().drawingGroup().blur(radius: 3).probe("blurGroup")
                }
                .probe("row2")
                HStack(spacing: 20) {
                    Text("Label").padding(8).background(Color.white).shadow(color: .black, radius: 2, x: 4).probe("labelShadow")
                    Text("Label").padding(8).background(Color.white).compositingGroup().shadow(color: .black, radius: 2, x: 4).probe("labelShadowGroup")
                    pair().colorInvert().probe("invert")
                    pair().opacity(0.5).colorInvert().probe("invertOpacity")
                }
                .probe("row3")
            }
            .probe("stack")
        }
        .probe("zstack")
    }).rasterized()

    public static let all: [Fixture] = [shadow, shadowProfile, shadowOffset, zIndex, hidden, brightness, saturation, colorMap, colorText, blur, blend, mask, compositing]
}
