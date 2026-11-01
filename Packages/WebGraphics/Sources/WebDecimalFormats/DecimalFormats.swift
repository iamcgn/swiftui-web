// `Decimal`'s formatting on wasm (decision 0017): `Decimal.FormatStyle` with its `Percent` and
// `Currency` styles, `.formatted()` and the `.number`, `.percent` and `.currency(code:)`
// shorthands. English output, as the other stand-ins; held to Foundation's output on macOS and
// Linux by the root package's FrameworkTests.
//
// A module of its own because naming `Decimal` links Foundation's Decimal and what it reaches
// (3.4 MB, AttributedString and the collections among them) into every bundle that links the
// module. `import Foundation` (Packages/Shadows) re-exports it only when the app enables the
// DecimalFormatting trait, which Tools/Traits/traits.py asks of an app that names Decimal and so
// already ships it (decision 0024).
#if os(WASI)
import WebFoundation

extension Decimal {
    /// The decimal as a `Double`, through its exact text.
    fileprivate var _double: Double { Double(description) ?? 0 }

    /// A structure that converts between decimal values and their textual representations.
    public struct FormatStyle: WebFoundation.FormatStyle, Hashable, Sendable {
        var core = _NumberFormatting()
        public init() {}
        public init(locale: Locale) {}
        public func format(_ value: Decimal) -> String { core.format(value._double) }
        public func precision(_ precision: NumberFormatStyleConfiguration.Precision) -> Self { var copy = self; copy.core = core.precision(precision); return copy }
        public func grouping(_ grouping: NumberFormatStyleConfiguration.Grouping) -> Self { var copy = self; copy.core = core.grouping(grouping); return copy }
        public func locale(_ locale: Locale) -> Self { self }

        /// The decimal as a percentage (0.25 → "25%").
        public struct Percent: WebFoundation.FormatStyle, Hashable, Sendable {
            var core = _NumberFormatting(style: .percent)
            public init() {}
            public init(locale: Locale) {}
            public func format(_ value: Decimal) -> String { core.format(value._double) }
            public func precision(_ precision: NumberFormatStyleConfiguration.Precision) -> Self { var copy = self; copy.core = core.precision(precision); return copy }
            public func grouping(_ grouping: NumberFormatStyleConfiguration.Grouping) -> Self { var copy = self; copy.core = core.grouping(grouping); return copy }
            public func locale(_ locale: Locale) -> Self { self }
        }

        /// The decimal as an amount of a currency (12.5 → "$12.50").
        public struct Currency: WebFoundation.FormatStyle, Hashable, Sendable {
            var core: _NumberFormatting
            public init(code: String, locale: Locale = .current) { core = _NumberFormatting(style: .currency(code)) }
            public func format(_ value: Decimal) -> String { core.format(value._double) }
            public func precision(_ precision: NumberFormatStyleConfiguration.Precision) -> Self { var copy = self; copy.core = core.precision(precision); return copy }
            public func grouping(_ grouping: NumberFormatStyleConfiguration.Grouping) -> Self { var copy = self; copy.core = core.grouping(grouping); return copy }
            public func locale(_ locale: Locale) -> Self { self }
        }
    }

    /// The decimal formatted by `style`.
    public func formatted<S: WebFoundation.FormatStyle>(_ style: S) -> S.FormatOutput where S.FormatInput == Decimal { style.format(self) }
    /// The decimal formatted the default way ("1,234.5").
    public func formatted() -> String { FormatStyle().format(self) }
}

extension FormatStyle where Self == Decimal.FormatStyle {
    public static var number: Decimal.FormatStyle { Decimal.FormatStyle() }
}
extension FormatStyle where Self == Decimal.FormatStyle.Percent {
    public static var percent: Decimal.FormatStyle.Percent { Decimal.FormatStyle.Percent() }
}
extension FormatStyle where Self == Decimal.FormatStyle.Currency {
    public static func currency(code: String) -> Decimal.FormatStyle.Currency { Decimal.FormatStyle.Currency(code: code) }
}


#endif
