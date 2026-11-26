// Core Text's fonts for wasm. On Apple platforms `CTFont` and `UIFont` are toll-free bridged, so
// here a `CTFont` is UIKitWeb's `UIFont`: the typesetter (Typesetter.swift) reads it under
// `kCTFontAttributeName`, which is "NSFont" on Apple's too, and SwiftUI's `Font(_:)` takes it.
// A font made from a `CGFont` is the bundled font of that PostScript name (the canvas host
// loads the app's font files under their PostScript and family names).
#if os(WASI)
@_exported import WebFoundation
import WebGraphics
import UIKitWebCore

public typealias CTFont = UIFont
public typealias CTFontDescriptor = UIFontDescriptor

/// The attribute keys Core Text reads; the font, kern and paragraph style ones are the same
/// strings as UIKit's.
public let kCTFontAttributeName: CFString = "NSFont"
public let kCTKernAttributeName: CFString = "NSKern"
public let kCTParagraphStyleAttributeName: CFString = "NSParagraphStyle"
public let kCTForegroundColorAttributeName: CFString = "CTForegroundColor"
public let kCTForegroundColorFromContextAttributeName: CFString = "CTForegroundColorFromContext"
public let kCTUnderlineStyleAttributeName: CFString = "NSUnderline"
public let kCTStrokeWidthAttributeName: CFString = "NSStrokeWidth"
public let kCTStrokeColorAttributeName: CFString = "CTStrokeColor"
public let kCTLigatureAttributeName: CFString = "NSLigature"
public let kCTSuperscriptAttributeName: CFString = "NSSuperScript"

/// Core Text's default size, for a size of 0.
private func _size(_ size: CGFloat) -> CGFloat { size > 0 ? size : 12 }

/// The font of a PostScript, full or family name at `size` (12 for 0); the matrix is ignored.
public func CTFontCreateWithName(_ name: CFString, _ size: CGFloat, _ matrix: UnsafePointer<CGAffineTransform>?) -> CTFont {
    UIFont(name: name, size: _size(size)) ?? UIFont.systemFont(ofSize: _size(size))
}

/// The font a descriptor describes, at `size` (the descriptor's own for 0).
public func CTFontCreateWithFontDescriptor(_ descriptor: CTFontDescriptor, _ size: CGFloat, _ matrix: UnsafePointer<CGAffineTransform>?) -> CTFont {
    UIFont(descriptor: descriptor, size: size)
}

/// The font of a graphics font's PostScript name; the system font when it has none.
public func CTFontCreateWithGraphicsFont(_ graphicsFont: CGFont, _ size: CGFloat, _ matrix: UnsafePointer<CGAffineTransform>?,
                                         _ attributes: CTFontDescriptor?) -> CTFont {
    guard let name = graphicsFont.postScriptName, let font = UIFont(name: name, size: _size(size)) else {
        return UIFont.systemFont(ofSize: _size(size))
    }
    return font
}

/// The same face at another size (the font's own for 0).
public func CTFontCreateCopyWithAttributes(_ font: CTFont, _ size: CGFloat, _ matrix: UnsafePointer<CGAffineTransform>?,
                                           _ attributes: CTFontDescriptor?) -> CTFont {
    size > 0 ? font.withSize(size) : font
}

public func CTFontCopyFontDescriptor(_ font: CTFont) -> CTFontDescriptor { font.fontDescriptor }
public func CTFontCopyPostScriptName(_ font: CTFont) -> CFString { font.fontName }
public func CTFontCopyFamilyName(_ font: CTFont) -> CFString { font.familyName }
public func CTFontCopyFullName(_ font: CTFont) -> CFString { font.fontName }
public func CTFontCopyDisplayName(_ font: CTFont) -> CFString { font.fontName }
public func CTFontGetSize(_ font: CTFont) -> CGFloat { font.pointSize }
public func CTFontGetAscent(_ font: CTFont) -> CGFloat { font.ascender }
/// Positive, as Core Text's is (UIKit's descender is negative).
public func CTFontGetDescent(_ font: CTFont) -> CGFloat { -font.descender }
public func CTFontGetLeading(_ font: CTFont) -> CGFloat { font.leading }
public func CTFontGetCapHeight(_ font: CTFont) -> CGFloat { font.capHeight }
public func CTFontGetXHeight(_ font: CTFont) -> CGFloat { font.xHeight }
#endif
