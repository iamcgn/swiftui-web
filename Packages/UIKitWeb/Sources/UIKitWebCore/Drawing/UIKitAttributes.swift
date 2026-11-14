// UIKit's attribute scope for Swift attributed strings (Docs/elements/UIKit/Drawing.md,
// "Documents"): `AttributeScopes.UIKitAttributes` and `\.uiKit`, so an `NSAttributedString`
// read from HTML becomes an `AttributedString` with its fonts, colours and decorations
// (`AttributedString(text, including: \.uiKit)`, as HighlightSwift converts highlighted code),
// and `container.uiKit.foregroundColor` names the keys. Each key is named as its
// `NSAttributedString.Key` is ("NSFont", "NSColor"), so the conversion keeps them and
// `NSAttributedString(attributedString)` gives them back. SwiftUI's `Text` shows the font,
// colours and decorations these keys carry. Natively the scope is Foundation's and UIKit's own.
#if os(WASI)
import WebFoundation

public enum _UIKitFontAttribute: AttributedStringKey {
    public typealias Value = UIFont
    public static let name = "NSFont"
}
public enum _UIKitForegroundColorAttribute: AttributedStringKey {
    public typealias Value = UIColor
    public static let name = "NSColor"
}
public enum _UIKitBackgroundColorAttribute: AttributedStringKey {
    public typealias Value = UIColor
    public static let name = "NSBackgroundColor"
}
public enum _UIKitUnderlineStyleAttribute: AttributedStringKey {
    public typealias Value = NSUnderlineStyle
    public static let name = "NSUnderline"
    public static func _webValue(of object: Any) -> _AttributeValue? { _UIKitLineStyle.value(object) }
}
public enum _UIKitStrikethroughStyleAttribute: AttributedStringKey {
    public typealias Value = NSUnderlineStyle
    public static let name = "NSStrikethrough"
    public static func _webValue(of object: Any) -> _AttributeValue? { _UIKitLineStyle.value(object) }
}
public enum _UIKitUnderlineColorAttribute: AttributedStringKey {
    public typealias Value = UIColor
    public static let name = "NSUnderlineColor"
}
public enum _UIKitStrikethroughColorAttribute: AttributedStringKey {
    public typealias Value = UIColor
    public static let name = "NSStrikethroughColor"
}
public enum _UIKitKernAttribute: AttributedStringKey {
    public typealias Value = CGFloat
    public static let name = "NSKern"
    public static func _webValue(of object: Any) -> _AttributeValue? { _UIKitLineStyle.number(object).map { _AttributeValue($0) } }
}
public enum _UIKitBaselineOffsetAttribute: AttributedStringKey {
    public typealias Value = CGFloat
    public static let name = "NSBaselineOffset"
    public static func _webValue(of object: Any) -> _AttributeValue? { _UIKitLineStyle.number(object).map { _AttributeValue($0) } }
}

/// Attribute values as UIKit stores them: a line style as its raw number, a length as any number.
enum _UIKitLineStyle {
    static func value(_ object: Any) -> _AttributeValue? {
        switch object {
        case let style as NSUnderlineStyle: return style.rawValue == 0 ? nil : _AttributeValue(style)
        case let raw as Int: return raw == 0 ? nil : _AttributeValue(NSUnderlineStyle(rawValue: raw))
        case let number as NSNumber: return number.intValue == 0 ? nil : _AttributeValue(NSUnderlineStyle(rawValue: number.intValue))
        default: return nil
        }
    }

    static func number(_ object: Any) -> CGFloat? {
        switch object {
        case let value as CGFloat: return value
        case let value as Int: return CGFloat(value)
        case let value as Float: return CGFloat(value)
        case let number as NSNumber: return CGFloat(number.doubleValue)
        default: return nil
        }
    }
}

extension AttributeScopes {
    /// The attributes UIKit reads from an attributed string, and Foundation's.
    public struct UIKitAttributes: AttributeScope {
        public typealias FontAttribute = _UIKitFontAttribute
        public typealias ForegroundColorAttribute = _UIKitForegroundColorAttribute
        public typealias BackgroundColorAttribute = _UIKitBackgroundColorAttribute
        public typealias UnderlineStyleAttribute = _UIKitUnderlineStyleAttribute
        public typealias StrikethroughStyleAttribute = _UIKitStrikethroughStyleAttribute
        public typealias UnderlineColorAttribute = _UIKitUnderlineColorAttribute
        public typealias StrikethroughColorAttribute = _UIKitStrikethroughColorAttribute
        public typealias KernAttribute = _UIKitKernAttribute
        public typealias BaselineOffsetAttribute = _UIKitBaselineOffsetAttribute

        // Key paths name the keys; the scope is never instantiated.
        public let font: FontAttribute
        public let foregroundColor: ForegroundColorAttribute
        public let backgroundColor: BackgroundColorAttribute
        public let underlineStyle: UnderlineStyleAttribute
        public let strikethroughStyle: StrikethroughStyleAttribute
        public let underlineColor: UnderlineColorAttribute
        public let strikethroughColor: StrikethroughColorAttribute
        public let kern: KernAttribute
        public let baselineOffset: BaselineOffsetAttribute
        public let foundation: FoundationAttributes

        public static var _webKeys: [any AttributedStringKey.Type] {
            [FontAttribute.self, ForegroundColorAttribute.self, BackgroundColorAttribute.self, UnderlineStyleAttribute.self,
             StrikethroughStyleAttribute.self, UnderlineColorAttribute.self, StrikethroughColorAttribute.self, KernAttribute.self,
             BaselineOffsetAttribute.self] + FoundationAttributes._webKeys
        }
    }

    public var uiKit: UIKitAttributes.Type { UIKitAttributes.self }
}

extension AttributeDynamicLookup {
    // SwiftUI's keys of the same names (`font`, `foregroundColor`) win where both are imported.
    @_disfavoredOverload
    public subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.UIKitAttributes, T>) -> T { self[T.self] }
}
#endif
