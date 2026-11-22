// `NSDataDetector` on wasm (AcknowList's license parser: the first link in a license's text,
// `NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)`). Foundation's
// detectors are Apple's data-detection engine; this one finds links only, by a scan of the
// UTF-16 code units (the ranges an `NSString` indexes by), and finds nothing for the other
// kinds a detector may be asked for (dates, addresses, phone numbers, transit information).
//
// A link is what Foundation's link detector takes for one in running text: an address with a
// scheme (`https://…`, `ftp://…`), one starting `www.` (an `http` URL), an email address
// (a `mailto:` URL) or a bare host on a common top-level domain (`github.com/…`, an `http`
// URL), with sentence punctuation after it left off. Foundation's subclasses
// `NSRegularExpression`; that class is final here, so the detector stands alone with the same
// matching methods.
#if os(WASI)
/// Foundation's name for the bit set of `NSTextCheckingResult.CheckingType` raw values.
public typealias NSTextCheckingTypes = UInt64
public let NSTextCheckingAllSystemTypes: NSTextCheckingTypes = 0xffff_ffff
public let NSTextCheckingAllCustomTypes: NSTextCheckingTypes = 0xffff_ffff << 32
public let NSTextCheckingAllTypes: NSTextCheckingTypes = .max

/// A specialized regular expression object that matches natural language text for
/// predefined data patterns (links, here).
public final class NSDataDetector: @unchecked Sendable {
    /// The checking types the detector was made for.
    public let checkingTypes: NSTextCheckingTypes

    public struct _Error: Error, CustomStringConvertible {
        public let description: String
    }

    /// A detector for `checkingTypes`; throws when none of them is a kind a data detector
    /// finds (date, address, link, phone number, transit information), as Foundation's does.
    public init(types checkingTypes: NSTextCheckingTypes) throws {
        let detectable: NSTextCheckingResult.CheckingType = [.date, .address, .link, .phoneNumber, .transitInformation]
        guard checkingTypes & detectable.rawValue != 0 else {
            throw _Error(description: "NSDataDetector: none of the checking types \(checkingTypes) is one a data detector finds")
        }
        self.checkingTypes = checkingTypes
    }

    /// Every link in the range of the string, in order.
    public func matches(in string: String, options: NSRegularExpression.MatchingOptions = [], range: NSRange) -> [NSTextCheckingResult] {
        guard checkingTypes & NSTextCheckingResult.CheckingType.link.rawValue != 0 else { return [] }
        let units = Array(string.utf16)
        let start = max(0, min(range.location, units.count))
        let end = max(start, min(range.location + range.length, units.count))
        var results: [NSTextCheckingResult] = []
        var index = start
        while index < end {
            if index == start || !_LinkScan.isWordUnit(units[index - 1]),
               let found = _LinkScan.link(in: units, at: index, end: end) {
                if !options.contains(.anchored) || index == start {
                    results.append(.linkCheckingResult(range: NSRange(location: index, length: found.length), url: found.url))
                }
                index += found.length
            } else {
                index += 1
            }
        }
        return results
    }

    public func firstMatch(in string: String, options: NSRegularExpression.MatchingOptions = [], range: NSRange) -> NSTextCheckingResult? {
        matches(in: string, options: options, range: range).first
    }

    public func numberOfMatches(in string: String, options: NSRegularExpression.MatchingOptions = [], range: NSRange) -> Int {
        matches(in: string, options: options, range: range).count
    }

    public func rangeOfFirstMatch(in string: String, options: NSRegularExpression.MatchingOptions = [], range: NSRange) -> NSRange {
        firstMatch(in: string, options: options, range: range)?.range ?? .notFound
    }

    public func enumerateMatches(in string: String, options: NSRegularExpression.MatchingOptions = [], range: NSRange,
                                 using block: (NSTextCheckingResult?, NSRegularExpression.MatchingFlags, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var stop = ObjCBool(false)
        for match in matches(in: string, options: options, range: range) {
            block(match, [], &stop)
            if stop.boolValue { break }
        }
    }
}

/// The link scan over UTF-16 code units.
enum _LinkScan {
    static func isLetter(_ u: UInt16) -> Bool { (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) }
    static func isDigit(_ u: UInt16) -> Bool { u >= 0x30 && u <= 0x39 }
    static func isWordUnit(_ u: UInt16) -> Bool { isLetter(u) || isDigit(u) || u == 0x5F || u > 0x7F }
    static func lower(_ u: UInt16) -> UInt16 { u >= 0x41 && u <= 0x5A ? u + 0x20 : u }

    /// A host's characters: letters, digits, hyphens and dots (and anything beyond ASCII, for
    /// internationalized names).
    static func isHostUnit(_ u: UInt16) -> Bool { isLetter(u) || isDigit(u) || u == 0x2D || u == 0x2E || u > 0x7F }

    /// What may run on in an address after its host: anything but space, controls and the
    /// characters that delimit an address in text (`<`, `>`, `"`, backtick, braces, `|`, `\`, `^`).
    static func isAddressUnit(_ u: UInt16) -> Bool {
        if u <= 0x20 || u == 0x7F { return false }
        switch u {
        case 0x22, 0x3C, 0x3E, 0x60, 0x7B, 0x7D, 0x7C, 0x5C, 0x5E: return false
        case 0x00A0, 0x2028, 0x2029, 0x3000: return false
        default: return true
        }
    }

    /// An email's local part: letters, digits and `. _ % + -`.
    static func isLocalUnit(_ u: UInt16) -> Bool {
        isLetter(u) || isDigit(u) || u == 0x2E || u == 0x5F || u == 0x25 || u == 0x2B || u == 0x2D
    }

    /// The top-level domains a bare host is taken as a link for.
    static let domains: Set<String> = ["com", "org", "net", "edu", "gov", "io", "dev", "app", "co", "me", "info", "biz",
                                       "uk", "de", "fr", "jp", "ca", "au", "us", "eu", "ly", "gl", "gg", "xyz", "ai"]

    /// The link starting at `index`: its length in code units and its URL.
    static func link(in units: [UInt16], at index: Int, end: Int) -> (length: Int, url: URL)? {
        // `mailto:` and the address: the scheme is part of the link.
        let mailto: [UInt16] = [0x6D, 0x61, 0x69, 0x6C, 0x74, 0x6F, 0x3A]
        if index + mailto.count < end, (0..<mailto.count).allSatisfy({ lower(units[index + $0]) == mailto[$0] }),
           let found = emailLink(in: units, at: index + mailto.count, end: end) {
            return (found.0 + mailto.count, found.1)
        }
        if let found = schemeLink(in: units, at: index, end: end) { return found }
        if let found = emailLink(in: units, at: index, end: end) { return found }
        return hostLink(in: units, at: index, end: end)
    }

    /// `scheme://rest`, a scheme of a letter then letters, digits, `+`, `-` or `.`.
    static func schemeLink(in units: [UInt16], at index: Int, end: Int) -> (Int, URL)? {
        guard isLetter(units[index]) else { return nil }
        var cursor = index + 1
        while cursor < end, isLetter(units[cursor]) || isDigit(units[cursor]) || units[cursor] == 0x2B || units[cursor] == 0x2D || units[cursor] == 0x2E {
            cursor += 1
        }
        guard cursor - index >= 2, cursor + 3 < end, units[cursor] == 0x3A, units[cursor + 1] == 0x2F, units[cursor + 2] == 0x2F,
              isAddressUnit(units[cursor + 3]) else { return nil }
        return address(in: units, from: index, after: cursor + 3, end: end, prefix: "")
    }

    /// `www.host…`, an `http` URL.
    static func hostLink(in units: [UInt16], at index: Int, end: Int) -> (Int, URL)? {
        var cursor = index
        while cursor < end, isHostUnit(units[cursor]) { cursor += 1 }
        // The host without a trailing dot (the end of a sentence).
        var hostEnd = cursor
        while hostEnd > index, units[hostEnd - 1] == 0x2E { hostEnd -= 1 }
        guard hostEnd > index else { return nil }
        let host = String(decoding: units[index..<hostEnd], as: UTF16.self)
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, !labels.contains(where: \.isEmpty) else { return nil }
        let isWWW = labels[0].lowercased() == "www" && labels.count >= 3
        guard isWWW || domains.contains(labels[labels.count - 1].lowercased()) else { return nil }
        // A bare host's labels are letters, digits and hyphens.
        if !isWWW {
            for label in labels where label.utf16.contains(where: { !(isLetter($0) || isDigit($0) || $0 == 0x2D) }) { return nil }
        }
        if hostEnd < end, units[hostEnd] == 0x40 { return nil }
        return address(in: units, from: index, after: hostEnd, end: end, prefix: "http://")
    }

    /// `local@host.domain`, a `mailto:` URL.
    static func emailLink(in units: [UInt16], at index: Int, end: Int) -> (Int, URL)? {
        guard isLocalUnit(units[index]), units[index] != 0x2E else { return nil }
        var cursor = index
        while cursor < end, isLocalUnit(units[cursor]) { cursor += 1 }
        guard cursor < end, units[cursor] == 0x40, units[cursor - 1] != 0x2E else { return nil }
        let hostStart = cursor + 1
        var hostEnd = hostStart
        while hostEnd < end, isLetter(units[hostEnd]) || isDigit(units[hostEnd]) || units[hostEnd] == 0x2D || units[hostEnd] == 0x2E {
            hostEnd += 1
        }
        while hostEnd > hostStart, units[hostEnd - 1] == 0x2E || units[hostEnd - 1] == 0x2D { hostEnd -= 1 }
        guard hostEnd > hostStart else { return nil }
        let host = String(decoding: units[hostStart..<hostEnd], as: UTF16.self)
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, !labels.contains(where: \.isEmpty), let tld = labels.last, tld.count >= 2,
              tld.utf16.allSatisfy(isLetter) else { return nil }
        let text = String(decoding: units[index..<hostEnd], as: UTF16.self)
        guard let url = URL(string: "mailto:" + text) else { return nil }
        return (hostEnd - index, url)
    }

    /// The address from `start`, running on from `after` over address characters, without
    /// trailing sentence punctuation or a closing bracket it did not open.
    static func address(in units: [UInt16], from start: Int, after: Int, end: Int, prefix: String) -> (Int, URL)? {
        var cursor = after
        while cursor < end, isAddressUnit(units[cursor]) { cursor += 1 }
        while cursor > after {
            let last = units[cursor - 1]
            switch last {
            case 0x2E, 0x2C, 0x3B, 0x3A, 0x21, 0x3F, 0x27, 0x2A:
                cursor -= 1
                continue
            case 0x29, 0x5D:
                let open: UInt16 = last == 0x29 ? 0x28 : 0x5B
                var opens = 0, closes = 0
                for u in units[start..<cursor] { if u == open { opens += 1 } else if u == last { closes += 1 } }
                if closes > opens { cursor -= 1; continue }
            default: break
            }
            break
        }
        let text = String(decoding: units[start..<cursor], as: UTF16.self)
        guard let url = URL(string: prefix + text) else { return nil }
        return (cursor - start, url)
    }
}
#endif
