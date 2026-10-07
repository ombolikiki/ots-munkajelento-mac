import Foundation

/// Egy futó Pomodoro-munkamenet mentett állapota: ebből áll helyre a munkamenet, ha az alkalmazás váratlanul leáll.
struct PomoSessionRecord: Codable {
    /// A munkamenet elején elkészített bejegyzés (a mezők ekkor rögzülnek; az idő mezői a lezáráskor íródnak).
    var template: Entry
    var start: Date
    /// A legutóbbi életjel: ha az app váratlanul leáll, a munkamenet ennyi idővel zárul.
    var lastAlive: Date
}

/// A Pomodoro-munkamenet tiszta logikája (tesztelhető): egy munkamenet = a pomók és a szünetek együtt, egyetlen bejegyzés.
enum PomoSession {
    /// A 30 másodpercnél rövidebb munkamenetet véletlen kattintásnak vesszük, nem rögzül.
    static let minSeconds: TimeInterval = 30

    /// A [start, end] tartomány éjfélnél darabolva (a nyári időszámítás is helyes: a naptár helyi éjfeléhez igazodik).
    static func segments(from start: Date, to end: Date, calendar: Calendar = .current) -> [(start: Date, end: Date)] {
        guard end > start else { return [] }
        var result: [(Date, Date)] = []
        var cur = start
        var guardCount = 0
        while cur < end, guardCount < 14 {   // egy munkamenet nem tart két hétig
            guardCount += 1
            let dayStart = calendar.startOfDay(for: cur)
            let nextMidnight = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
            let segEnd = min(end, max(nextMidnight, cur.addingTimeInterval(1)))
            result.append((cur, segEnd))
            cur = segEnd
        }
        return result.map { (start: $0.0, end: $0.1) }
    }

    /// A munkamenetből készülő bejegyzések: egy, vagy éjfélen átnyúlás esetén több (mindegyik a saját napján, saját időtartammal).
    /// A 30 másodpercnél rövidebb munkamenetből nem lesz bejegyzés.
    static func entries(template: Entry, start: Date, end: Date, calendar: Calendar = .current) -> [Entry] {
        guard end.timeIntervalSince(start) >= minSeconds else { return [] }
        return segments(from: start, to: end, calendar: calendar).compactMap { seg in
            let secs = Int(seg.end.timeIntervalSince(seg.start).rounded())
            guard secs >= 1 else { return nil }
            var e = template
            e.id = UUID()
            e.date = Fmt.dayFormatter.string(from: seg.start)
            e.start = seg.start
            e.end = seg.end
            e.durationSeconds = secs
            e.source = "pomodoro"
            return e
        }
    }
}
