// `Locale`'s decimal and grouping separators on wasm, as CLDR has them. They live here, beside
// `Locale`, rather than with WebFoundationFormats' tables, so a module that only needs them
// (MapKit's distance formatter) doesn't link the formatting module (a megabyte, compressed).
#if os(WASI)
extension Locale {
    /// The character the locale writes between a number's whole part and its fraction ("." for
    /// en_US, "," for de_DE and fr_FR), as CLDR has it: by language, with the regions that write
    /// numbers otherwise. Formatting here still writes en_US numbers; this answers the locale,
    /// for apps that read it (OldOS's calculator).
    public var decimalSeparator: String? { Locale._separators(languageCode, regionCode).decimal }

    /// The character the locale writes between groups of a number's whole part ("," for en_US,
    /// "." for de_DE, a narrow no-break space for fr_FR), as CLDR has it.
    public var groupingSeparator: String? { Locale._separators(languageCode, regionCode).grouping }

    static func _separators(_ language: String?, _ region: String?) -> (decimal: String, grouping: String) {
        let nbsp = "\u{00A0}", narrow = "\u{202F}", apostrophe = "\u{2019}"
        let region = region?.uppercased() ?? ""
        switch (language?.lowercased() ?? "en", region) {
        case ("de", "CH"), ("de", "LI"), ("it", "CH"), ("en", "CH"), ("rm", _): return (".", apostrophe)
        case ("de", "AT"): return (",", nbsp)
        case ("fr", "CA"): return (",", nbsp)
        case ("fr", _): return (",", narrow)
        case ("es", "MX"), ("es", "US"), ("es", "PE"), ("es", "DO"), ("es", "GT"), ("es", "HN"), ("es", "NI"),
             ("es", "PA"), ("es", "PR"), ("es", "SV"), ("es", "419"):
            return (".", ",")
        case ("pt", "BR"): return (",", ".")
        case ("pt", _): return (",", nbsp)
        case ("en", "ZA"): return (",", nbsp)
        case ("en", "DE"): return (",", ".")
        case ("de", _), ("es", _), ("it", _), ("nl", _), ("da", _), ("tr", _), ("el", _), ("ro", _), ("hr", _),
             ("sl", _), ("id", _), ("vi", _), ("ca", _), ("eu", _), ("gl", _), ("sr", _), ("mk", _), ("is", _),
             ("az", _), ("ka", _), ("af", _), ("bs", _):
            return (",", ".")
        case ("ru", _), ("pl", _), ("uk", _), ("cs", _), ("sk", _), ("sv", _), ("nb", _), ("no", _), ("nn", _),
             ("fi", _), ("hu", _), ("bg", _), ("et", _), ("lv", _), ("lt", _), ("be", _), ("kk", _), ("hy", _),
             ("sq", _), ("uz", _), ("ky", _):
            return (",", nbsp)
        default: return (".", ",")
        }
    }
}
#endif
