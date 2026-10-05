import Foundation

/// Védett dátumszámítások. Szabály (lásd CLAUDE.md): nincs kényszerített kicsomagolás a `Calendar`/`Date`
/// visszatérési értékein; hibánál biztonságos tartalékra váltunk, így a dátumszámolás nem omolhat össze.
enum DateUtil {
    /// Fix gergely naptár (a felhasználó régiójától függetlenül), a helyi időzónával.
    static var gregorian: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        c.locale = Locale(identifier: "hu_HU")
        return c
    }

    static func startOfDay(_ d: Date) -> Date { gregorian.startOfDay(for: d) }

    /// `n` nappal későbbi (vagy korábbi) nap. Hibánál 24 órás tartalék.
    static func addDays(_ d: Date, _ n: Int) -> Date {
        gregorian.date(byAdding: .day, value: n, to: d) ?? d.addingTimeInterval(TimeInterval(n) * 86_400)
    }

    /// Dátum év/hó/nap alapján; érvénytelen értéknél nil (sosem omlik össze).
    static func date(year: Int, month: Int, day: Int) -> Date? {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = 12   // dél: a nyári időszámítás váltása nem tolhatja át a napot
        guard let d = gregorian.date(from: comps) else { return nil }
        let back = gregorian.dateComponents([.year, .month, .day], from: d)
        guard back.year == year, back.month == month, back.day == day else { return nil }   // pl. február 30.
        return gregorian.startOfDay(for: d)
    }

    static func components(_ d: Date) -> (year: Int, month: Int, day: Int) {
        let c = gregorian.dateComponents([.year, .month, .day], from: d)
        return (c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    /// A hét napja: 1 = vasárnap … 7 = szombat.
    static func weekday(_ d: Date) -> Int { gregorian.component(.weekday, from: d) }

    static func isSaturday(_ d: Date) -> Bool { weekday(d) == 7 }
    static func isSunday(_ d: Date) -> Bool { weekday(d) == 1 }
    /// Hétfőtől péntekig.
    static func isWeekday(_ d: Date) -> Bool { (2...6).contains(weekday(d)) }

    /// A hét első napja (0:00) a megadott kezdőnappal (1 = vasárnap, 2 = hétfő).
    static func startOfWeek(_ d: Date, firstWeekday: Int) -> Date {
        let first = (firstWeekday == 1) ? 1 : 2
        let day = startOfDay(d)
        let w = weekday(day)
        let back = (w - first + 7) % 7
        return addDays(day, -back)
    }

    // MARK: Negyedévek

    /// (év, negyedév 1–4)
    static func quarter(of d: Date) -> (year: Int, quarter: Int) {
        let c = components(d)
        return (c.year, (c.month - 1) / 3 + 1)
    }

    static func quarterStart(year: Int, quarter: Int) -> Date? {
        guard (1...4).contains(quarter) else { return nil }
        return date(year: year, month: (quarter - 1) * 3 + 1, day: 1)
    }

    /// A negyedév összes szombatja időrendben (a negyedév első napjától).
    static func saturdays(year: Int, quarter: Int) -> [Date] {
        guard let start = quarterStart(year: year, quarter: quarter) else { return [] }
        let nextYear = quarter == 4 ? year + 1 : year
        let nextQuarter = quarter == 4 ? 1 : quarter + 1
        guard let end = quarterStart(year: nextYear, quarter: nextQuarter) else { return [] }
        var result: [Date] = []
        var d = start
        var guardCount = 0
        while d < end, guardCount < 120 {
            if isSaturday(d) { result.append(d) }
            d = addDays(d, 1)
            guardCount += 1
        }
        return result
    }
}

/// A gyülekezeti létszámjelentő esedékes napjai: minden negyedév második és hetedik szombatja.
enum AttendanceSchedule {
    static let ordinals = [2, 7]

    static func dueDates(year: Int, quarter: Int) -> [Date] {
        let sats = DateUtil.saturdays(year: year, quarter: quarter)
        return ordinals.compactMap { n in sats.indices.contains(n - 1) ? sats[n - 1] : nil }
    }

    /// Az [from, to] zárt tartományba eső esedékes napok, időrendben.
    static func dueDates(from: Date, to: Date) -> [Date] {
        guard from <= to else { return [] }
        let a = DateUtil.quarter(of: from), b = DateUtil.quarter(of: to)
        var y = a.year, q = a.quarter
        var result: [Date] = []
        var guardCount = 0
        while (y < b.year || (y == b.year && q <= b.quarter)), guardCount < 400 {
            for d in dueDates(year: y, quarter: q) where d >= DateUtil.startOfDay(from) && d <= to { result.append(d) }
            q += 1
            if q > 4 { q = 1; y += 1 }
            guardCount += 1
        }
        return result
    }

    static func isDue(_ day: Date) -> Bool {
        let q = DateUtil.quarter(of: day)
        let d0 = DateUtil.startOfDay(day)
        return dueDates(year: q.year, quarter: q.quarter).contains(d0)
    }
}
