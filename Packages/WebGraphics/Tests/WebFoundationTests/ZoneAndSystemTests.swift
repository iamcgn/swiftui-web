// pf-web-foundation-gaps: named zones learnt from a host (here Foundation's zones stand in
// for the browser's `Intl`), the calendar arithmetic across daylight saving, wrapping
// addition, and every arithmetical calendar system held to Foundation's.
import Testing
import Foundation
@testable import WebFoundation

/// Installs Foundation's zones as the host for the suite's duration.
private func withFoundationZones<R>(_ body: () throws -> R) rethrows -> R {
    _ZoneCache.hostOffset = { identifier, time in
        TimeZone(identifier: identifier)?.secondsFromGMT(for: Date(timeIntervalSince1970: time))
    }
    _ZoneCache.shared.forget()
    defer { _ZoneCache.hostOffset = nil; _ZoneCache.shared.forget() }
    return try body()
}

@Suite(.serialized) struct ZoneRuleTests {
    static let zones = ["America/New_York", "Europe/Berlin", "Australia/Lord_Howe", "Asia/Kolkata", "Pacific/Auckland", "America/Sao_Paulo", "Africa/Casablanca"]

    /// Instants around the transitions of 2020–2027 and a spread of others.
    static func samples(in zone: TimeZone) -> [Double] {
        var times: [Double] = []
        var cursor = Date(timeIntervalSince1970: 1_577_836_800)   // 2020-01-01
        while cursor.timeIntervalSince1970 < 1_830_297_600, let next = zone.nextDaylightSavingTimeTransition(after: cursor) {   // 2028-01-01
            for delta in [-7200.0, -3601, -1, 0, 1, 3599, 7200] { times.append(next.timeIntervalSince1970 + delta) }
            cursor = next.addingTimeInterval(60)
        }
        var generator = CalendarMathTests.SplitMix(seed: 7)
        times += (0..<300).map { _ in Double(Int(generator.next() % (60 * 366 * 86400))) }
        return times
    }

    @Test func offsetsFollowTheHostThroughTransitions() {
        withFoundationZones {
            for name in Self.zones {
                let zone = TimeZone(identifier: name)!
                let rule = _ZoneRule.named(name)
                for time in Self.samples(in: zone) {
                    let date = Date(timeIntervalSince1970: time)
                    #expect(rule.offset(at: time) == zone.secondsFromGMT(for: date), "\(name) \(time)")
                    // Casablanca's standard time is UTC in the tz database while +01 holds most of the year; the
                    // host's offsets cannot tell, so its saving offset is the one difference accepted.
                    if name != "Africa/Casablanca" {
                        #expect(rule.offset(at: time) - rule.standardOffset(at: time) == Int(zone.daylightSavingTimeOffset(for: date)), "dst \(name) \(time)")
                    }
                }
                let next = zone.nextDaylightSavingTimeTransition(after: Date(timeIntervalSince1970: 1_700_000_000))
                #expect(rule.nextTransition(after: 1_700_000_000) == next?.timeIntervalSince1970, "next \(name)")
            }
            #expect(!_ZoneCache.shared.knows("Mars/Olympus_Mons") && _ZoneCache.shared.knows("Europe/Paris"))
        }
    }

    @Test func calendarFieldsAndCompositionAcrossDaylightSaving() {
        withFoundationZones {
            for name in Self.zones {
                let zone = TimeZone(identifier: name)!
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = zone
                let math = _CalendarMath(zone: .named(name))
                for time in Self.samples(in: zone) {
                    let date = Date(timeIntervalSince1970: time)
                    let f = math.fields(time)
                    let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
                    let ours: [Int] = [f.year, f.month, f.day, f.hour, f.minute, f.second, f.weekday]
                    let theirs: [Int] = [c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!, c.weekday!]
                    #expect(ours == theirs, "\(name) \(time)")
                    #expect(math.startOfDay(time) == calendar.startOfDay(for: date).timeIntervalSince1970, "start of day \(name) \(time)")
                    // Wall clocks that exist come back; the gap and the overlap resolve as Foundation's.
                    let rebuilt = math.time(year: f.year, month: f.month, day: f.day, hour: f.hour, minute: f.minute, second: f.second)
                    #expect(rebuilt == calendar.date(from: c)!.timeIntervalSince1970, "rebuild \(name) \(time)")
                    for (unit, component) in [(_CalendarUnit.day, Calendar.Component.day), (.weekOfYear, .weekOfYear), (.month, .month), (.hour, .hour)] {
                        for value in [1, -1, 3] {
                            #expect(math.adding(unit, value, to: time) == calendar.date(byAdding: component, value: value, to: date)!.timeIntervalSince1970, "\(name) + \(value) \(component) at \(time)")
                        }
                    }
                }
                // A wall clock in the spring gap moves forward; one in the autumn overlap is its first occurrence.
                if name == "America/New_York" {
                    #expect(math.time(year: 2026, month: 3, day: 8, hour: 2, minute: 30) == calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 2, minute: 30))!.timeIntervalSince1970)
                    #expect(math.time(year: 2026, month: 11, day: 1, hour: 1, minute: 30) == calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 1, minute: 30))!.timeIntervalSince1970)
                }
            }
        }
    }

    @Test func wrappingAdditionMatchesFoundation() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US")
        let math = _CalendarMath(offset: 0)
        let units: [(_CalendarUnit, Calendar.Component)] = [(.hour, .hour), (.minute, .minute), (.second, .second), (.day, .day), (.month, .month),
                                                             (.weekday, .weekday), (.year, .year), (.weekOfMonth, .weekOfMonth), (.weekOfYear, .weekOfYear), (.weekdayOrdinal, .weekdayOrdinal)]
        for time in CalendarMathTests.samples where time > 0 {
            let date = Date(timeIntervalSince1970: time.rounded(.down))
            for (unit, component) in units {
                for value in [1, 5, -1, 13, -40] {
                    let ours = math.addingWrapped(unit, value, to: time.rounded(.down))
                    let theirs = calendar.date(byAdding: component, value: value, to: date, wrappingComponents: true)!.timeIntervalSince1970
                    #expect(ours == theirs, "\(component) + \(value) at \(time)")
                }
            }
        }
    }
}

@Suite struct CalendarSystemTests {
    static let systems: [(Calendar.Identifier, _CalendarSystem)] = [
        (.buddhist, .buddhist), (.japanese, .japanese), (.republicOfChina, .republicOfChina), (.islamicCivil, .islamicCivil),
        (.islamicTabular, .islamicTabular), (.persian, .persian), (.hebrew, .hebrew), (.coptic, .coptic),
        (.ethiopicAmeteMihret, .ethiopicAmeteMihret), (.ethiopicAmeteAlem, .ethiopicAmeteAlem), (.indian, .indian),
    ]

    /// Days since 1970 between 1900 and 2100, plus year boundaries of each system around now.
    static var days: [Int] {
        var generator = CalendarMathTests.SplitMix(seed: 3)
        var days = (0..<500).map { _ in Int(generator.next() % (200 * 366)) - 70 * 365 }
        days += [0, 20_000, 20_454 /* 2026-01-01 */, 20_742, 19_723, 21_000]
        return days
    }

    @Test(arguments: systems) func fieldsAndDayCountsMatchFoundation(_ pair: (Calendar.Identifier, _CalendarSystem)) {
        var calendar = Calendar(identifier: pair.0)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US")
        let system = pair.1
        for day in Self.days {
            let date = Date(timeIntervalSince1970: Double(day) * 86400 + 43200)
            let theirs = calendar.dateComponents([.era, .year, .month, .day], from: date)
            if pair.0 == .japanese, theirs.era! < 232 { continue }   // eras before Meiji are not modelled
            let ours = system.date(days: day)
            let ourTriple: [Int] = [ours.year, ours.month, ours.day], theirTriple: [Int] = [theirs.year!, theirs.month!, theirs.day!]
            #expect(ourTriple == theirTriple, "\(pair.0) day \(day)")
            #expect(system.era(days: day) == theirs.era!, "\(pair.0) era \(day)")
            #expect(system.days(year: ours.year, month: ours.month, day: ours.day, era: theirs.era) == day, "\(pair.0) round trip \(day)")
            #expect(system.daysInMonth(year: ours.year, month: ours.month, era: theirs.era) == calendar.range(of: .day, in: .month, for: date)!.count, "\(pair.0) month length \(day)")
            #expect(system.daysInYear(ours.year, era: theirs.era) == calendar.range(of: .day, in: .year, for: date)!.count, "\(pair.0) year length \(day)")
            #expect(system.monthsInYear(ours.year) == calendar.range(of: .month, in: .year, for: date)!.count, "\(pair.0) months \(day)")
            // Adding months steps the way Foundation steps (the Hebrew leap slot skipped).
            for count in [1, -1, 7, 14] {
                let stepped = Date(timeIntervalSince1970: Double(_CalendarMath(zone: .fixed(0), system: system).adding(.month, count, to: Double(day) * 86400 + 43200)))
                #expect(stepped == calendar.date(byAdding: .month, value: count, to: date)!, "\(pair.0) + \(count) months at \(day)")
            }
        }
    }

    @Test func gregorianDerivedSystemsAgreeWithTheCivilDate() {
        func triple(_ date: (year: Int, month: Int, day: Int)) -> [Int] { [date.year, date.month, date.day] }
        #expect(triple(_Gregorian.civil(days: 20_454)) == [2026, 1, 1])
        #expect(triple(_CalendarSystem.buddhist.date(days: 20_454)) == [2569, 1, 1])
        #expect(triple(_CalendarSystem.japanese.date(days: 20_454)) == [8, 1, 1] && _CalendarSystem.japanese.era(days: 20_454) == 236)
        #expect(triple(_CalendarSystem.republicOfChina.date(days: 20_454)) == [115, 1, 1])
        #expect(_CalendarSystem.gregorian.days(year: 2026, month: 14, day: 35) == _Gregorian.days(year: 2027, month: 3, day: 7))
    }
}
