// The date formatting core behind `Date.FormatStyle`, `DateFormatter` and the ISO 8601 and
// relative styles on wasm (pf-web-foundation-gaps), platform-neutral so the tests can hold it
// to Foundation's en_US output. Patterns are Unicode LDML patterns (`yMMMd` skeletons become
// patterns through CLDR's `en` availableFormats, as ICU's pattern generator picks them); the
// symbols are English. Other locales format as English (`Locale` is an identifier here).

/// What a pattern needs to know about an instant.
package struct _DateFormatInput {
    package var fields: _DateFields
    package var era: Int
    package var weekOfYear: Int, yearForWeekOfYear: Int, weekOfMonth: Int
    /// Seconds east of GMT at the instant.
    package var offset: Int
    /// The zone's name in `Intl`'s styles ("short", "long", "shortGeneric", "longGeneric", "identifier").
    package var zoneName: (String) -> String

    package init(time: Double, math: _CalendarMath, zoneName: @escaping (String) -> String) {
        fields = math.fields(time)
        era = math.era(time)
        let week = math.weekOfYear(time)
        weekOfYear = week.week
        yearForWeekOfYear = week.year
        weekOfMonth = math.weekOfMonth(time)
        offset = math.zone.offset(at: time)
        self.zoneName = zoneName
    }
}

package enum _DatePattern {
    package static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    package static let shortMonthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    package static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    package static let shortWeekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    package static let shortestWeekdayNames = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    /// A pattern split into literal text and field runs.
    package enum Token: Equatable {
        case literal(String)
        case field(Character, Int)
    }

    package static func tokens(_ pattern: String) -> [Token] {
        var tokens: [Token] = []
        var literal = ""
        var characters = Array(pattern)
        var index = 0
        func flushLiteral() { if !literal.isEmpty { tokens.append(.literal(literal)); literal = "" } }
        while index < characters.count {
            let c = characters[index]
            if c == "'" {
                if index + 1 < characters.count, characters[index + 1] == "'" { literal.append("'"); index += 2; continue }
                index += 1
                while index < characters.count {
                    if characters[index] == "'" {
                        if index + 1 < characters.count, characters[index + 1] == "'" { literal.append("'"); index += 2; continue }
                        break
                    }
                    literal.append(characters[index]); index += 1
                }
                index += 1
            } else if c.isLetter, c.isASCII {
                flushLiteral()
                var count = 1
                while index + count < characters.count, characters[index + count] == c { count += 1 }
                tokens.append(.field(c, count))
                index += count
            } else {
                literal.append(c); index += 1
            }
        }
        flushLiteral()
        characters = []
        return tokens
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(abs(value))
        return (value < 0 ? "-" : "") + String(repeating: "0", count: max(0, width - text.count)) + text
    }

    /// The GMT offset forms: "GMT" / "GMT+2" / "GMT-04:30" (`O`), "GMT+02:00" (`OOOO`),
    /// "+0200" (`Z`), "+02:00" (`xxx`), "Z" for zero with `X`.
    package static func offsetText(_ offset: Int, style: Character, count: Int) -> String {
        let sign = offset < 0 ? "-" : "+"
        let hours = abs(offset) / 3600, minutes = abs(offset) % 3600 / 60
        switch style {
        case "O":
            // ICU writes the zero offset out ("GMT+0", "GMT+00:00") rather than CLDR's bare "GMT".
            return count >= 4 ? "GMT\(sign)\(pad(hours, 2)):\(pad(minutes, 2))" : "GMT\(sign)\(hours)" + (minutes > 0 ? ":\(pad(minutes, 2))" : "")
        case "Z":
            if count >= 5 { return offset == 0 ? "Z" : "\(sign)\(pad(hours, 2)):\(pad(minutes, 2))" }
            if count == 4 { return offsetText(offset, style: "O", count: 4) }
            return "\(sign)\(pad(hours, 2))\(pad(minutes, 2))"
        case "X" where offset == 0: return "Z"
        case "x", "X":
            switch count {
            case 1: return "\(sign)\(pad(hours, 2))" + (minutes > 0 ? pad(minutes, 2) : "")
            case 2, 4: return "\(sign)\(pad(hours, 2))\(pad(minutes, 2))"
            default: return "\(sign)\(pad(hours, 2)):\(pad(minutes, 2))"
            }
        default: return ""
        }
    }

    /// The text of `pattern` for an instant.
    package static func format(_ pattern: String, _ input: _DateFormatInput) -> String {
        format(tokens(pattern), input)
    }

    package static func format(_ tokens: [Token], _ input: _DateFormatInput) -> String {
        let f = input.fields
        var result = ""
        for token in tokens {
            switch token {
            case .literal(let text): result += text
            case .field(let letter, let count):
                switch letter {
                case "G": result += count >= 4 ? (input.era == 0 ? "Before Christ" : "Anno Domini") : count == 5 ? (input.era == 0 ? "B" : "A") : (input.era == 0 ? "BC" : "AD")
                case "y", "u": result += count == 2 ? pad(_Gregorian.floorMod(f.year, 100), 2) : pad(f.year, count)
                case "Y": result += count == 2 ? pad(_Gregorian.floorMod(input.yearForWeekOfYear, 100), 2) : pad(input.yearForWeekOfYear, count)
                case "M", "L":
                    switch count {
                    case 1, 2: result += pad(f.month, count)
                    case 3: result += shortMonthNames[(f.month - 1) % 12]
                    case 4: result += monthNames[(f.month - 1) % 12]
                    default: result += String(monthNames[(f.month - 1) % 12].prefix(1))
                    }
                case "d": result += pad(f.day, count)
                case "D": result += pad(f.dayOfYear, count)
                case "F": result += String((f.day - 1) / 7 + 1)
                case "E", "c", "e":
                    if count <= 2, letter != "E" { result += letter == "e" ? pad(f.weekday, count) : String(f.weekday) } else {
                        switch count {
                        case 1, 2, 3: result += shortWeekdayNames[f.weekday - 1]
                        case 4: result += weekdayNames[f.weekday - 1]
                        case 5: result += String(weekdayNames[f.weekday - 1].prefix(1))
                        default: result += shortestWeekdayNames[f.weekday - 1]
                        }
                    }
                case "a": result += count == 5 ? (f.hour < 12 ? "a" : "p") : (f.hour < 12 ? "AM" : "PM")
                case "b", "B":
                    if f.hour == 12, f.minute == 0, f.second == 0 { result += "noon" } else if f.hour == 0, f.minute == 0, f.second == 0 { result += "midnight" }
                    else if count == 5 { result += f.hour < 12 ? "a" : "p" } else { result += f.hour < 12 ? "AM" : "PM" }
                case "h", "J": result += pad(f.hour % 12 == 0 ? 12 : f.hour % 12, count)   // J: the hour without its period, 12-hour in en
                case "H": result += pad(f.hour, count)
                case "K": result += pad(f.hour % 12, count)
                case "k": result += pad(f.hour == 0 ? 24 : f.hour, count)
                case "m": result += pad(f.minute, count)
                case "s": result += pad(f.second, count)
                case "S":
                    let digits = String(pad(f.nanosecond, 9).prefix(count))
                    result += digits
                case "A": result += pad(((f.hour * 60 + f.minute) * 60 + f.second) * 1000 + f.nanosecond / 1_000_000, count)
                case "Q", "q":
                    let quarter = (f.month - 1) / 3 + 1
                    switch count {
                    case 1, 2: result += pad(quarter, count)
                    case 3: result += "Q\(quarter)"
                    default: result += ["1st quarter", "2nd quarter", "3rd quarter", "4th quarter"][quarter - 1]
                    }
                case "w": result += pad(input.weekOfYear, count)
                case "W": result += String(input.weekOfMonth)
                case "z": result += count >= 4 ? input.zoneName("long") : input.zoneName("short")
                case "v": result += count >= 4 ? input.zoneName("longGeneric") : input.zoneName("shortGeneric")
                case "V": result += count >= 2 ? input.zoneName("identifier") : input.zoneName("short")
                case "O", "Z", "x", "X": result += offsetText(input.offset, style: letter, count: count)
                default: result += String(repeating: letter, count: count)
                }
            }
        }
        return result
    }

    // MARK: Styles

    /// `Date.FormatStyle`'s date styles (1 numeric, 2 abbreviated, 3 long, 4 complete) and time
    /// styles (1 shortened, 2 standard, 3 complete) as `en` patterns, joined with ", " after a
    /// numeric date and " at " after one with a month name.
    package static func stylePattern(date: Int?, time: Int?) -> String {
        let datePattern: String?
        switch date {
        case 1: datePattern = "M/d/y"
        case 2: datePattern = "MMM d, y"
        case 3: datePattern = "MMMM d, y"
        case 4: datePattern = "EEEE, MMMM d, y"
        default: datePattern = nil
        }
        let timePattern: String?
        switch time {
        case 1: timePattern = "h:mm\u{202F}a"
        case 2: timePattern = "h:mm:ss\u{202F}a"
        case 3: timePattern = "h:mm:ss\u{202F}a z"
        default: timePattern = nil
        }
        if datePattern == nil, timePattern == nil { return stylePattern(date: 1, time: 1) }   // both omitted: the default
        return joined(datePattern, timePattern, long: (date ?? 0) >= 2)
    }

    /// `DateFormatter`'s styles (1 short, 2 medium, 3 long, 4 full) as `en` patterns.
    package static func formatterPattern(dateStyle: Int, timeStyle: Int) -> String {
        let datePattern: String?
        switch dateStyle {
        case 1: datePattern = "M/d/yy"
        case 2: datePattern = "MMM d, y"
        case 3: datePattern = "MMMM d, y"
        case 4: datePattern = "EEEE, MMMM d, y"
        default: datePattern = nil
        }
        let timePattern: String?
        switch timeStyle {
        case 1: timePattern = "h:mm\u{202F}a"
        case 2: timePattern = "h:mm:ss\u{202F}a"
        case 3: timePattern = "h:mm:ss\u{202F}a z"
        case 4: timePattern = "h:mm:ss\u{202F}a zzzz"
        default: timePattern = nil
        }
        return joined(datePattern, timePattern, long: dateStyle >= 2)
    }

    private static func joined(_ date: String?, _ time: String?, long: Bool) -> String {
        switch (date, time) {
        case (let d?, let t?): return long ? d + " 'at' " + t : d + ", " + t
        case (let d?, nil): return d
        case (nil, let t?): return t
        case (nil, nil): return ""
        }
    }

    // MARK: Skeletons

    /// CLDR `en` availableFormats: the pattern for a skeleton's set of fields.
    private static let availableFormats: [String: String] = [
        "d": "d", "E": "ccc", "Ed": "E d", "Ehm": "E h:mm\u{202F}a", "EHm": "E HH:mm", "Ehms": "E h:mm:ss\u{202F}a", "EHms": "E HH:mm:ss",
        "Gy": "y G", "GyMd": "M/d/y G", "GyMMM": "MMM y G", "GyMMMd": "MMM d, y G", "GyMMMEd": "E, MMM d, y G",
        "h": "h\u{202F}a", "H": "HH", "hm": "h:mm\u{202F}a", "Hm": "HH:mm", "hms": "h:mm:ss\u{202F}a", "Hms": "HH:mm:ss", "hmsv": "h:mm:ss\u{202F}a v", "Hmsv": "HH:mm:ss v",
        "hmv": "h:mm\u{202F}a v", "Hmv": "HH:mm v", "hmz": "h:mm\u{202F}a z", "Hmz": "HH:mm z", "hmsz": "h:m:s\u{202F}a z", "Hmsz": "HH:mm:ss z",   // ICU leaves hmsz unpadded
        "M": "L", "Md": "M/d", "MEd": "E, M/d", "MMM": "LLL", "MMMd": "MMM d", "MMMEd": "E, MMM d", "MMMMd": "MMMM d", "MMMMEd": "E, MMMM d",
        "ms": "mm:ss", "y": "y", "yM": "M/y", "yMd": "M/d/y", "yMEd": "E, M/d/y", "yMMM": "MMM y", "yMMMd": "MMM d, y", "yMMMEd": "E, MMM d, y",
        "yMMMM": "MMMM y", "yMMMMd": "MMMM d, y", "yMMMMEd": "E, MMMM d, y", "yMMMMEEEEd": "EEEE, MMMM d, y", "yQQQ": "QQQ y", "yQQQQ": "QQQQ y",
        "yw": "'week' w 'of' Y", "MMMMW": "'week' W 'of' MMMM", "D": "D", "Q": "Q", "QQQ": "QQQ", "QQQQ": "QQQQ", "w": "w", "W": "W",
        "m": "m", "s": "s", "G": "G", "a": "a", "z": "z", "v": "v", "O": "O", "ZZZZ": "ZZZZ", "VV": "VV", "yQ": "Q y", "hv": "h\u{202F}a v", "Hv": "HH v",
        "Ehmz": "E h:mm\u{202F}a z", "yMMMMEEEE": "EEEE, MMMM y", "MMMEEEEd": "EEEE, MMM d", "yMMMEEEEd": "EEEE, MMM d, y", "yMEEEEd": "EEEE, M/d/y", "MEEEEd": "EEEE, M/d",
        "Ey": "E y", "Eyd": "E d y", "yd": "d y", "EEEEhm": "EEEE h:mm\u{202F}a", "EEEEHm": "EEEE HH:mm",
    ]

    /// The pattern letters a skeleton may use, in canonical order (ICU's field order). `J` is
    /// the hour without its period marker (`Date.FormatStyle`'s `amPM: .omitted`), 12-hour in `en`.
    private static let fieldOrder: [Character] = ["G", "y", "Q", "M", "w", "W", "E", "d", "D", "F", "a", "h", "H", "J", "m", "s", "S", "v", "z", "O", "Z", "V"]

    /// A canonical skeleton: one run per field, in ICU's order, the hour as `h` or `H`.
    package static func canonical(_ skeleton: String) -> String {
        var runs: [Character: Int] = [:]
        for case .field(let letter, let count) in tokens(skeleton) {
            let key: Character = letter == "L" ? "M" : letter == "c" || letter == "e" ? "E" : letter == "k" ? "H" : letter == "K" ? "h" : letter == "x" || letter == "X" ? "Z" : letter
            runs[key] = max(runs[key] ?? 0, count)
        }
        return fieldOrder.compactMap { letter in runs[letter].map { String(repeating: letter, count: $0) } }.joined()
    }

    /// The pattern ICU's generator picks for a skeleton: the `en` entry with the same fields,
    /// its runs widened or narrowed to the skeleton's, a date part and a time part joined
    /// with the locale's glue when no single entry has both.
    package static func pattern(forSkeleton skeleton: String) -> String {
        let canonical = canonical(skeleton)
        if canonical.isEmpty { return "" }
        if !canonical.contains("J" as Character), let direct = matched(canonical) { return direct }
        // Split into the date fields and the time fields.
        let timeLetters: Set<Character> = ["a", "h", "H", "J", "m", "s", "S"]
        let zoneLetters: Set<Character> = ["v", "z", "O", "Z", "V"]
        var date = "", time = "", zone = ""
        for case .field(let letter, let count) in tokens(canonical) {
            let run = String(repeating: letter, count: count)
            if timeLetters.contains(letter) { time += run } else if zoneLetters.contains(letter) { zone += run } else { date += run }
        }
        let datePattern = date.isEmpty ? nil : matched(date) ?? fallback(date)
        // The zone follows the time (or stands alone), as the generator appends it.
        var timePattern = time.isEmpty ? nil : matched(time) ?? fallback(time)
        if time.contains("J" as Character) {
            // The period marker goes, the 12-hour digits stay.
            let twelve = time.map { $0 == "J" ? "h" : $0 }
            let full = matched(String(twelve)) ?? fallback(String(twelve))
            // (String.replacing and contains(String) are _StringProcessing's and would link the Regex engine.)
            timePattern = full._trimmed([" ", "\u{202F}"]).split(separator: "\u{202F}").first.map { String($0.filter { $0 != "a" }) }?._trimmed([" "])
        }
        if !zone.isEmpty { timePattern = (timePattern.map { $0 + " " } ?? "") + zone }
        switch (datePattern, timePattern) {
        case (let d?, let t?):
            // "{1} 'at' {0}" after a month name, "{1}, {0}" after a numeric date.
            let long = tokens(date).contains { if case .field("M", let count) = $0 { return count >= 3 } else { return false } }
            return long ? d + " 'at' " + t : d + ", " + t
        case (let d?, nil): return d
        case (nil, let t?): return t
        case (nil, nil): return canonical
        }
    }

    /// The `en` entry whose fields are the skeleton's, with the skeleton's widths applied.
    private static func matched(_ canonical: String) -> String? {
        let wanted = tokens(canonical).compactMap { token -> (Character, Int)? in if case .field(let l, let c) = token { return (l, c) } else { return nil } }
        let wantedLetters = Set(wanted.map { $0.0 })
        var best: (String, String)? = nil
        for (key, pattern) in availableFormats {
            let keyFields = tokens(key).compactMap { token -> Character? in if case .field(let l, _) = token { return l == "L" || l == "c" ? (l == "L" ? "M" : "E") : l } else { return nil } }
            guard Set(keyFields) == wantedLetters, keyFields.count == wantedLetters.count else { continue }
            // Prefer the entry whose widths are closest to the skeleton's.
            if best == nil || distance(key, wanted) < distance(best!.0, wanted) { best = (key, pattern) }
        }
        guard let (_, pattern) = best else { return nil }
        return adjusted(pattern, to: wanted)
    }

    private static func distance(_ key: String, _ wanted: [(Character, Int)]) -> Int {
        var total = 0
        for case .field(let letter, let count) in tokens(key) {
            let normalized: Character = letter == "L" ? "M" : letter == "c" ? "E" : letter
            if let want = wanted.first(where: { $0.0 == normalized }) {
                total += abs(want.1 - count)
                // A numeric month and a month name are different fields to the generator.
                if normalized == "M", (want.1 <= 2) != (count <= 2) { total += 10 }
            }
        }
        return total
    }

    /// The pattern with each field run widened or narrowed to the skeleton's count, except that
    /// a numeric month or day stays as the entry wrote it when the skeleton asks for the same
    /// kind (names stay names, numbers stay numbers; two-digit requests pad).
    private static func adjusted(_ pattern: String, to wanted: [(Character, Int)]) -> String {
        var result = ""
        for token in tokens(pattern) {
            switch token {
            case .literal(let text): result += text.contains(where: { $0.isLetter || $0 == "'" }) ? "'" + text + "'" : text
            case .field(let letter, let count):
                let normalized: Character = letter == "L" ? "M" : letter == "c" || letter == "e" ? "E" : letter
                guard let want = wanted.first(where: { $0.0 == normalized }) else { result += String(repeating: letter, count: count); continue }
                var width = count
                switch normalized {
                case "M": width = want.1
                case "E": width = max(want.1, 3)
                case "d", "h", "H", "m", "s", "y", "Y": width = want.1 == 2 ? 2 : (normalized == "y" || normalized == "Y") ? (want.1 == 1 ? count : want.1) : count == 2 ? 2 : want.1
                case "G", "Q", "a", "z", "v", "Z", "O", "V": width = want.1
                default: width = want.1
                }
                if normalized == "m" || normalized == "s" { width = pattern.contains(":" as Character) ? count : width }
                result += String(repeating: letter, count: width)
            }
        }
        return result
    }

    /// A pattern for fields no entry covers: the runs in order, separated by spaces.
    private static func fallback(_ canonical: String) -> String {
        tokens(canonical).compactMap { token -> String? in if case .field(let l, let c) = token { return String(repeating: l, count: c) } else { return nil } }.joined(separator: " ")
    }

    // MARK: Parsing

    /// The fields read from `text` against a pattern (the fields the pattern names), nil when
    /// the text does not fit. Names are matched case-insensitively by prefix.
    package static func parse(_ text: String, pattern: String) -> ParsedFields? {
        var parsed = ParsedFields()
        var rest = Substring(text)
        func skipSpaces() { while let first = rest.first, first == " " || first == "\u{202F}" || first == "\u{00A0}" { rest = rest.dropFirst() } }
        func number(maxDigits: Int) -> Int? {
            skipSpaces()
            var sign = 1
            if rest.first == "-" { sign = -1; rest = rest.dropFirst() }
            let digits = rest.prefix { $0.isASCII && $0.isNumber }.prefix(maxDigits)
            guard !digits.isEmpty, let value = Int(digits) else { return nil }
            rest = rest.dropFirst(digits.count)
            return sign * value
        }
        func name(in names: [String]) -> Int? {
            skipSpaces()
            let lower = rest.lowercased()
            for (index, candidate) in names.enumerated().sorted(by: { $0.element.count > $1.element.count }) where lower.hasPrefix(candidate.lowercased()) {
                rest = rest.dropFirst(candidate.count)
                return index
            }
            return nil
        }
        for token in tokens(pattern) {
            switch token {
            case .literal(let literal):
                skipSpaces()
                let trimmed = literal._trimmed([" ", "\u{202F}", "\u{00A0}"])
                guard trimmed.isEmpty || rest.hasPrefix(trimmed) else { return nil }
                rest = rest.dropFirst(trimmed.count)
            case .field(let letter, let count):
                switch letter {
                case "G": guard let era = name(in: ["BC", "AD", "Before Christ", "Anno Domini"]) else { return nil }; parsed.era = era % 2
                case "y", "u", "Y":
                    guard let value = number(maxDigits: count == 2 ? 2 : 9) else { return nil }
                    parsed.year = count == 2 ? (value < 50 ? 2000 + value : 1900 + value) : value
                case "M", "L":
                    if count >= 3 {
                        guard let index = name(in: monthNames) ?? name(in: shortMonthNames) else { return nil }
                        parsed.month = index + 1
                    } else { guard let value = number(maxDigits: 2) else { return nil }; parsed.month = value }
                case "d": guard let value = number(maxDigits: 2) else { return nil }; parsed.day = value
                case "D": guard let value = number(maxDigits: 3) else { return nil }; parsed.dayOfYear = value
                case "E", "c", "e":
                    if letter != "E", count <= 2 { guard number(maxDigits: 1) != nil else { return nil } } else {
                        guard name(in: weekdayNames) ?? name(in: shortWeekdayNames) != nil else { return nil }
                    }
                case "a", "b", "B":
                    guard let index = name(in: ["AM", "PM", "noon", "midnight", "a", "p"]) else { return nil }
                    parsed.pm = index == 1 || index == 2 || index == 5
                case "h", "K", "J": guard let value = number(maxDigits: 2) else { return nil }; parsed.hour = value % 12; parsed.twelveHour = true
                case "H", "k": guard let value = number(maxDigits: 2) else { return nil }; parsed.hour = value % 24
                case "m": guard let value = number(maxDigits: 2) else { return nil }; parsed.minute = value
                case "s": guard let value = number(maxDigits: 2) else { return nil }; parsed.second = value
                case "S":
                    skipSpaces()
                    let digits = rest.prefix { $0.isASCII && $0.isNumber }
                    guard !digits.isEmpty else { return nil }
                    rest = rest.dropFirst(digits.count)
                    parsed.nanosecond = Int((Double("0." + digits)! * 1e9).rounded())
                case "Q", "q": guard number(maxDigits: 1) != nil || name(in: ["Q1", "Q2", "Q3", "Q4"]) != nil else { return nil }
                case "w", "W": guard number(maxDigits: 2) != nil else { return nil }
                case "z", "v", "V", "O", "Z", "x", "X":
                    skipSpaces()
                    guard let offset = parseOffset(&rest) else { return nil }
                    parsed.offset = offset
                default: break
                }
            }
        }
        skipSpaces()
        guard rest.isEmpty else { return nil }
        return parsed
    }

    /// "Z", "GMT", "UTC", "GMT+2", "GMT-04:30", "+0200", "-04:00", or a zone abbreviation
    /// the parser cannot place (nil offset keeps the style's zone).
    package static func parseOffset(_ rest: inout Substring) -> Int?? {
        if rest.hasPrefix("Z") { rest = rest.dropFirst(); return .some(0) }
        var body = rest
        if body.hasPrefix("GMT") || body.hasPrefix("UTC") { body = body.dropFirst(3) }
        guard let sign = body.first, sign == "+" || sign == "-" else {
            if rest.hasPrefix("GMT") || rest.hasPrefix("UTC") { rest = rest.dropFirst(3); return .some(0) }
            // A name: consume letters and leave the zone as the style's.
            let letters = rest.prefix { $0.isLetter }
            guard !letters.isEmpty else { return nil }
            rest = rest.dropFirst(letters.count)
            return .some(nil)
        }
        body = body.dropFirst()
        let digits = body.prefix { $0.isNumber || $0 == ":" }
        let parts = digits.split(separator: ":")
        var hours = 0, minutes = 0
        if parts.count == 2 { hours = Int(parts[0]) ?? 0; minutes = Int(parts[1]) ?? 0 }
        else if let only = parts.first {
            if only.count > 2 { hours = Int(only.prefix(only.count - 2)) ?? 0; minutes = Int(only.suffix(2)) ?? 0 } else { hours = Int(only) ?? 0 }
        } else { return nil }
        rest = body.dropFirst(digits.count)
        return .some((hours * 3600 + minutes * 60) * (sign == "-" ? -1 : 1))
    }

    package struct ParsedFields {
        package var era: Int?, year: Int?, month: Int?, day: Int?, dayOfYear: Int?
        package var hour: Int?, minute: Int?, second: Int?, nanosecond: Int?
        package var pm: Bool?, twelveHour = false
        /// The offset read, when the text named one; `.some(nil)` for a zone name.
        package var offset: Int?? = nil

        /// The instant the fields name in `math`'s zone (the parsed offset instead when given),
        /// missing fields defaulting as Foundation's parser defaults them.
        package func time(in math: _CalendarMath, reference: Double? = nil) -> Double {
            var hour = self.hour ?? 0
            if twelveHour, pm == true { hour += 12 }
            let referenceFields = reference.map(math.fields)
            let year = self.year ?? referenceFields?.year ?? 1970
            var month = self.month ?? 1, day = self.day ?? 1
            if let dayOfYear, self.month == nil {
                let start = math.system.days(year: year, month: 1, day: 1) + dayOfYear - 1
                let date = math.system.date(days: start)
                month = date.month; day = date.day
            }
            if let offset = offset ?? nil {
                let fixed = _CalendarMath(zone: .fixed(offset), system: math.system, firstWeekday: math.firstWeekday, minimumDaysInFirstWeek: math.minimumDaysInFirstWeek)
                return fixed.time(year: year, month: month, day: day, hour: hour, minute: minute ?? 0, second: second ?? 0, nanosecond: nanosecond ?? 0, era: era)
            }
            return math.time(year: year, month: month, day: day, hour: hour, minute: minute ?? 0, second: second ?? 0, nanosecond: nanosecond ?? 0, era: era)
        }
    }
}

extension StringProtocol {
    /// `trimmingCharacters(in:)` for a few characters, without Foundation.
    package func _trimmed(_ set: Set<Character>) -> String {
        var sub = Substring(self)
        while let first = sub.first, set.contains(first) { sub = sub.dropFirst() }
        while let last = sub.last, set.contains(last) { sub = sub.dropLast() }
        return String(sub)
    }
}

// MARK: - Relative dates

package enum _RelativeDateText {
    package enum Presentation: Hashable, Sendable { case numeric, named }
    package enum UnitsStyle: Hashable, Sendable { case wide, abbreviated, narrow, spellOut }

    /// "2 hours ago", "in 3 days", "yesterday", "now": Foundation's `en` relative forms for the
    /// largest whole unit between the reference and the date (days by calendar day).
    /// `Date.RelativeFormatStyle` rounds to the nearest unit and promotes a count that rounds
    /// up to the next (59 min 59 s is "1 hour"; 59 s stays "59 seconds"); `RelativeDateTimeFormatter`
    /// keeps whole units, with `calendarMonths` deciding months and years.
    package static func text(seconds difference: Double, presentation: Presentation, unitsStyle: UnitsStyle, calendarDays: Int?,
                             calendarMonths: Int? = nil, rounding: Bool = true) -> String {
        let magnitude = abs(difference)
        let future = difference >= 0
        if presentation == .named, difference == 0 { return "now" }
        let units: [(Double, String, String, String)] = [
            (31_536_000, "year", "yr.", "y"), (2_592_000, "month", "mo.", "mo"), (604_800, "week", "wk.", "w"), (86_400, "day", "day", "d"),
            (3600, "hour", "hr.", "h"), (60, "minute", "min.", "m"), (1, "second", "sec.", "s"),
        ]
        var index = units.firstIndex { magnitude >= $0.0 } ?? units.count - 1
        if rounding {
            while index > 0, (magnitude / units[index].0).rounded() * units[index].0 >= units[index - 1].0 { index -= 1 }
        } else if let calendarMonths {
            // Whole calendar months decide the two largest units; weeks and below come from the seconds.
            if abs(calendarMonths) >= 12 { index = 0 } else if abs(calendarMonths) >= 1 { index = 1 } else { index = max(index, 2) }
        }
        for (length, wide, abbreviated, narrow) in units[index...] {
            var count = rounding ? Int((magnitude / length).rounded()) : Int(magnitude / length)
            if !rounding, let calendarMonths, length >= 2_592_000 { count = length == 31_536_000 ? abs(calendarMonths) / 12 : abs(calendarMonths) }
            if rounding, length == 86_400, let calendarDays, abs(calendarDays) >= 1 { count = abs(calendarDays) }
            if presentation == .named, count == 1 {
                switch wide {
                case "day": return future ? "tomorrow" : "yesterday"
                case "week", "month", "year":
                    let name = unitsStyle == .wide || unitsStyle == .spellOut ? wide : abbreviated
                    return (future ? "next " : "last ") + name
                default: break
                }
            }
            let number = unitsStyle == .spellOut ? spelled(count) : String(count)
            switch unitsStyle {
            case .wide, .spellOut:
                let name = count == 1 ? wide : wide + "s"
                return future ? "in \(number) \(name)" : "\(number) \(name) ago"
            case .abbreviated:
                // "1 day ago" keeps the word; the others abbreviate with a period and no plural.
                let name = wide == "day" ? (count == 1 ? "day" : "days") : abbreviated
                return future ? "in \(number) \(name)" : "\(number) \(name) ago"
            case .narrow:
                return future ? "in \(number)\(narrow)" : "\(number)\(narrow) ago"
            }
        }
        return future ? "in 0 seconds" : "0 seconds ago"
    }

    private static func spelled(_ value: Int) -> String {
        let ones = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
        let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
        if value < 20 { return ones[value] }
        if value < 100 { return tens[value / 10] + (value % 10 == 0 ? "" : "-" + ones[value % 10]) }
        if value < 1000 { return ones[value / 100] + " hundred" + (value % 100 == 0 ? "" : " " + spelled(value % 100)) }
        return String(value)
    }
}
