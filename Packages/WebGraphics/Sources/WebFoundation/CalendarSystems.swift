// The calendar systems behind `Calendar` on wasm (pf-web-foundation-gaps): conversions between
// day counts since 1970-01-01 and a system's year, month and day, with the month lengths and
// eras Foundation reports. The arithmetical calendars follow Reingold and Dershowitz
// (*Calendrical Calculations*) and ICU where Foundation follows ICU (the Persian and Indian
// algorithms, the Hebrew month slots, the Japanese era numbers). Platform-neutral so the
// tests can hold every system to Foundation's on macOS.

package enum _CalendarSystem: Hashable, Sendable {
    case gregorian, buddhist, japanese, republicOfChina, islamicCivil, islamicTabular, persian, hebrew, coptic,
         ethiopicAmeteMihret, ethiopicAmeteAlem, indian

    // MARK: Epochs (days since 1970-01-01 of the system's day 1)

    /// Rata Die 1 (0001-01-01 proleptic Gregorian) as days since 1970.
    private static let rataDieOffset = -719163
    private static let islamicCivilEpoch = 227015 + rataDieOffset
    private static let islamicTabularEpoch = 227014 + rataDieOffset
    private static let hebrewEpoch = -1373427 + rataDieOffset
    private static let copticEpoch = 103605 + rataDieOffset
    private static let ethiopicEpoch = 2796 + rataDieOffset
    /// Julian day number 1948320 as days since 1970 (JDN 2440588).
    private static let persianEpoch = 1948320 - 2440588

    /// A Japanese era: Foundation's era number, its name and the Gregorian day it began.
    package struct JapaneseEra: Sendable {
        package let number: Int, name: String, start: Int
    }
    /// The eras from Meiji on (Foundation numbers the historical eras from 1 = Taika).
    package static let japaneseEras: [JapaneseEra] = [
        JapaneseEra(number: 232, name: "Meiji", start: _Gregorian.days(year: 1868, month: 9, day: 8)),
        JapaneseEra(number: 233, name: "Taisho", start: _Gregorian.days(year: 1912, month: 7, day: 30)),
        JapaneseEra(number: 234, name: "Showa", start: _Gregorian.days(year: 1926, month: 12, day: 25)),
        JapaneseEra(number: 235, name: "Heisei", start: _Gregorian.days(year: 1989, month: 1, day: 8)),
        JapaneseEra(number: 236, name: "Reiwa", start: _Gregorian.days(year: 2019, month: 5, day: 1)),
    ]

    // MARK: Conversions

    /// The year, month and day of a day count. Gregorian-derived systems give the year of
    /// the current era (Japanese years count from the era's start, Minguo years from 1912).
    package func date(days: Int) -> (year: Int, month: Int, day: Int) {
        switch self {
        case .gregorian:
            let c = _Gregorian.civil(days: days)
            return (c.year, c.month, c.day)
        case .buddhist:
            let c = _Gregorian.civil(days: days)
            return (c.year + 543, c.month, c.day)
        case .japanese:
            let c = _Gregorian.civil(days: days)
            guard let era = Self.japaneseEras.last(where: { $0.start <= days }) else { return (c.year, c.month, c.day) }
            return (c.year - _Gregorian.civil(days: era.start).year + 1, c.month, c.day)
        case .republicOfChina:
            let c = _Gregorian.civil(days: days)
            return (c.year >= 1912 ? c.year - 1911 : 1912 - c.year, c.month, c.day)
        case .islamicCivil, .islamicTabular:
            let epoch = self == .islamicCivil ? Self.islamicCivilEpoch : Self.islamicTabularEpoch
            let year = _Gregorian.floorDiv(30 * (days - epoch) + 10646, 10631)
            let yearStart = Self.islamicDays(epoch: epoch, year: year, month: 1, day: 1)
            let month = min(12, Int((Double(days - yearStart - 29) / 29.5).rounded(.up)) + 1)
            let monthStart = Self.islamicDays(epoch: epoch, year: year, month: max(1, month), day: 1)
            return (year, max(1, month), days - monthStart + 1)
        case .persian:
            let since = days - Self.persianEpoch
            let year = 1 + _Gregorian.floorDiv(33 * since + 3, 12053)
            let yearStart = 365 * (year - 1) + _Gregorian.floorDiv(8 * year + 21, 33)
            let dayOfYear = since - yearStart
            let month = dayOfYear < 216 ? dayOfYear / 31 : (dayOfYear - 6) / 30
            return (year, month + 1, dayOfYear - Self.persianMonthStarts[month] + 1)
        case .hebrew:
            // 64-bit: the product passes 2^31 (wasm's Int is 32 bits wide).
            let approximate = Int((Int64(98496) * Int64(days - Self.hebrewEpoch)).quotientAndRemainder(dividingBy: 35975351).quotient) - 2
            var year = approximate
            while Self.hebrewNewYear(year + 1) <= days { year += 1 }
            var month = 1
            for next in 2...13 where Self.hebrewMonthExists(next, in: year) {
                guard Self.hebrewDays(year: year, month: next, day: 1) <= days else { break }
                month = next
            }
            return (year, month, days - Self.hebrewDays(year: year, month: month, day: 1) + 1)
        case .coptic, .ethiopicAmeteMihret, .ethiopicAmeteAlem:
            let epoch = self == .coptic ? Self.copticEpoch : Self.ethiopicEpoch
            let year = _Gregorian.floorDiv(4 * (days - epoch) + 1463, 1461)
            let month = (days - Self.alexandrianDays(epoch: epoch, year: year, month: 1, day: 1)) / 30 + 1
            let day = days - Self.alexandrianDays(epoch: epoch, year: year, month: month, day: 1) + 1
            return (self == .ethiopicAmeteAlem ? year + 5500 : year, month, day)
        case .indian:
            let c = _Gregorian.civil(days: days)
            var gregorianYear = c.year
            if days < Self.indianNewYear(gregorianYear: gregorianYear) { gregorianYear -= 1 }
            let dayOfYear = days - Self.indianNewYear(gregorianYear: gregorianYear)
            let starts = Self.indianMonthStarts(gregorianYear: gregorianYear)
            let month = (starts.lastIndex { $0 <= dayOfYear } ?? 0)
            return (gregorianYear - 78, month + 1, dayOfYear - starts[month] + 1)
        }
    }

    /// Foundation's era of a day count: 0 or 1 for the two-era systems (Gregorian, Minguo,
    /// Coptic), the Japanese era's number, ICU's constant for the others (Amete Mihret is 1,
    /// the single eras are 0).
    package func era(days: Int) -> Int {
        switch self {
        case .gregorian: return _Gregorian.civil(days: days).year > 0 ? 1 : 0
        case .japanese: return Self.japaneseEras.last(where: { $0.start <= days })?.number ?? 231
        case .republicOfChina: return _Gregorian.civil(days: days).year >= 1912 ? 1 : 0
        case .coptic: return days >= Self.copticEpoch ? 1 : 0
        case .ethiopicAmeteMihret: return 1
        case .buddhist, .islamicCivil, .islamicTabular, .persian, .hebrew, .ethiopicAmeteAlem, .indian: return 0
        }
    }

    /// The Gregorian year a Japanese or Minguo year falls in, for the era given (the current
    /// Japanese era and the Minguo era when nil).
    package func civilYear(year: Int, era: Int?) -> Int {
        switch self {
        case .japanese:
            let eraInfo = era.flatMap { number in Self.japaneseEras.first { $0.number == number } } ?? Self.japaneseEras.last!
            return _Gregorian.civil(days: eraInfo.start).year + year - 1
        case .republicOfChina: return era == 0 ? 1912 - year : year + 1911
        case .buddhist: return year - 543
        case .gregorian: return era == 0 ? 1 - year : year
        default: return year
        }
    }

    /// The day count of a date; months past the year carry into the next, days past the
    /// month into the next. `era` picks the Japanese era the year counts in (the current
    /// one when nil) and the side of the Gregorian and Minguo epochs.
    package func days(year: Int, month: Int, day: Int, era: Int? = nil) -> Int {
        // A month in range is a slot of this year (a Hebrew Adar I slot in a common year is
        // Adar); one out of range carries over existing months.
        let (y, m) = month >= 1 && month <= monthsInYear(year)
            ? (year, self == .hebrew && month == 6 && !Self.hebrewIsLeap(year) ? 7 : month)
            : monthsAfter(year: year, month: 1, count: month - 1)
        switch self {
        case .gregorian, .buddhist, .japanese, .republicOfChina:
            return _Gregorian.days(year: civilYear(year: y, era: era), month: m, day: 1) + day - 1
        case .islamicCivil: return Self.islamicDays(epoch: Self.islamicCivilEpoch, year: y, month: m, day: day)
        case .islamicTabular: return Self.islamicDays(epoch: Self.islamicTabularEpoch, year: y, month: m, day: day)
        case .persian: return Self.persianEpoch + 365 * (y - 1) + _Gregorian.floorDiv(8 * y + 21, 33) + Self.persianMonthStarts[m - 1] + day - 1
        case .hebrew: return Self.hebrewDays(year: y, month: m, day: day)
        case .coptic: return Self.alexandrianDays(epoch: Self.copticEpoch, year: y, month: m, day: day)
        case .ethiopicAmeteMihret: return Self.alexandrianDays(epoch: Self.ethiopicEpoch, year: y, month: m, day: day)
        case .ethiopicAmeteAlem: return Self.alexandrianDays(epoch: Self.ethiopicEpoch, year: y - 5500, month: m, day: day)
        case .indian: return Self.indianNewYear(gregorianYear: y + 78) + Self.indianMonthStarts(gregorianYear: y + 78)[m - 1] + day - 1
        }
    }

    // MARK: Lengths

    /// Whether years are Gregorian years counted from another epoch (the arithmetic then runs
    /// on the civil year, so eras and the Japanese era boundaries fall out of it).
    package var isGregorianDerived: Bool {
        switch self {
        case .gregorian, .buddhist, .japanese, .republicOfChina: return true
        default: return false
        }
    }

    package func monthsInYear(_ year: Int) -> Int {
        switch self {
        case .coptic, .ethiopicAmeteMihret, .ethiopicAmeteAlem, .hebrew: return 13
        default: return 12
        }
    }

    /// The year and month `count` months after a month; the Hebrew year's unused Adar I slot
    /// is skipped, as Foundation skips it.
    package func monthsAfter(year: Int, month: Int, count: Int) -> (year: Int, month: Int) {
        if self == .hebrew {
            var y = year, m = month, remaining = count
            let step = remaining >= 0 ? 1 : -1
            while remaining != 0 {
                m += step
                if m > 13 { m = 1; y += 1 } else if m < 1 { m = 13; y -= 1 }
                if m == 6, !Self.hebrewIsLeap(y) { m += step; if m < 1 { m = 13; y -= 1 } }
                remaining -= step
            }
            return (y, m)
        }
        let months = monthsInYear(year)
        let index = month - 1 + count
        return (year + _Gregorian.floorDiv(index, months), _Gregorian.floorMod(index, months) + 1)
    }

    /// The month's length; `era` matters to the Gregorian-derived systems, whose years count
    /// within an era.
    package func daysInMonth(year: Int, month: Int, era: Int? = nil) -> Int {
        switch self {
        case .gregorian, .buddhist, .japanese, .republicOfChina: return _Gregorian.daysInMonth(year: civilYear(year: year, era: era), month: month)
        case .islamicCivil, .islamicTabular:
            if month == 12 { return (14 + 11 * year) % 30 < 11 ? 30 : 29 }
            return month % 2 == 1 ? 30 : 29
        case .persian:
            if month <= 6 { return 31 }
            if month <= 11 { return 30 }
            return _Gregorian.floorMod(25 * year + 11, 33) < 8 ? 30 : 29
        case .hebrew: return Self.hebrewMonthLength(month, in: year)
        case .coptic, .ethiopicAmeteMihret: return month == 13 ? (_Gregorian.floorMod(year, 4) == 3 ? 6 : 5) : 30
        case .ethiopicAmeteAlem: return month == 13 ? (_Gregorian.floorMod(year - 5500, 4) == 3 ? 6 : 5) : 30
        case .indian:
            if month == 1 { return _Gregorian.isLeap(year + 78) ? 31 : 30 }
            return month <= 6 ? 31 : 30
        }
    }

    package func daysInYear(_ year: Int, era: Int? = nil) -> Int {
        switch self {
        case .gregorian, .buddhist, .japanese, .republicOfChina: return _Gregorian.isLeap(civilYear(year: year, era: era)) ? 366 : 365
        default: return days(year: year + 1, month: 1, day: 1) - days(year: year, month: 1, day: 1)
        }
    }

    // MARK: Islamic (tabular)

    private static func islamicDays(epoch: Int, year: Int, month: Int, day: Int) -> Int {
        epoch - 1 + (year - 1) * 354 + _Gregorian.floorDiv(3 + 11 * year, 30) + 29 * (month - 1) + month / 2 + day
    }

    // MARK: Persian (ICU's arithmetic)

    private static let persianMonthStarts = [0, 31, 62, 93, 124, 155, 186, 216, 246, 276, 306, 336]

    // MARK: Hebrew

    package static func hebrewIsLeap(_ year: Int) -> Bool { _Gregorian.floorMod(7 * year + 1, 19) < 7 }

    private static func hebrewElapsedDays(_ year: Int) -> Int {
        let monthsElapsed = Int64(_Gregorian.floorDiv(235 * year - 234, 19))
        let partsElapsed = 12084 + 13753 * monthsElapsed   // 64-bit: past 2^31 for current years
        var day = Int(29 * monthsElapsed + partsElapsed / 25920)
        if _Gregorian.floorMod(3 * (day + 1), 7) < 3 { day += 1 }
        return day
    }

    private static func hebrewYearLengthCorrection(_ year: Int) -> Int {
        let ny0 = hebrewElapsedDays(year - 1), ny1 = hebrewElapsedDays(year), ny2 = hebrewElapsedDays(year + 1)
        if ny2 - ny1 == 356 { return 2 }
        if ny1 - ny0 == 382 { return 1 }
        return 0
    }

    private static func hebrewNewYear(_ year: Int) -> Int { hebrewEpoch + hebrewElapsedDays(year) + hebrewYearLengthCorrection(year) }

    private static func hebrewDaysInYear(_ year: Int) -> Int { hebrewNewYear(year + 1) - hebrewNewYear(year) }

    /// Foundation's month slots: 1 Tishri, 2 Heshvan, 3 Kislev, 4 Tevet, 5 Shevat, 6 Adar I
    /// (leap years only), 7 Adar (Adar II), 8 Nisan, 9 Iyar, 10 Sivan, 11 Tammuz, 12 Av, 13 Elul.
    package static func hebrewMonthExists(_ month: Int, in year: Int) -> Bool { month != 6 || hebrewIsLeap(year) }

    package static func hebrewMonthLength(_ month: Int, in year: Int) -> Int {
        let length = hebrewDaysInYear(year)
        switch month {
        case 2: return length == 355 || length == 385 ? 30 : 29   // Heshvan is long in a complete year
        case 3: return length == 353 || length == 383 ? 29 : 30   // Kislev is short in a deficient year
        case 4, 7, 9, 11, 13: return 29
        case 6: return hebrewIsLeap(year) ? 30 : 0
        default: return 30
        }
    }

    private static func hebrewDays(year: Int, month: Int, day: Int) -> Int {
        var days = hebrewNewYear(year) + day - 1
        for m in 1..<month where hebrewMonthExists(m, in: year) { days += hebrewMonthLength(m, in: year) }
        return days
    }

    // MARK: Coptic and Ethiopic

    private static func alexandrianDays(epoch: Int, year: Int, month: Int, day: Int) -> Int {
        epoch - 1 + 365 * (year - 1) + _Gregorian.floorDiv(year, 4) + 30 * (month - 1) + day
    }

    // MARK: Indian national (Saka)

    /// Chaitra 1 of the Saka year that begins in `gregorianYear`: March 22, or the 21st in a
    /// Gregorian leap year.
    private static func indianNewYear(gregorianYear: Int) -> Int {
        _Gregorian.days(year: gregorianYear, month: 3, day: _Gregorian.isLeap(gregorianYear) ? 21 : 22)
    }

    private static func indianMonthStarts(gregorianYear: Int) -> [Int] {
        let first = _Gregorian.isLeap(gregorianYear) ? 31 : 30
        var starts = [0, first]
        for length in [31, 31, 31, 31, 31, 30, 30, 30, 30, 30] { starts.append(starts.last! + length) }
        return starts
    }
}
