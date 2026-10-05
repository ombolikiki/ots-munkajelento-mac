import Foundation

/// Napi összesítések és jelzések tiszta függvényekként (a mai napot paraméterként kapják, így tesztelhetők).
enum Insights {
    /// Az OTS-be kerülő idő másodpercben: az óra típusok ideje, a fő és az alkalom darabonként 1 óra.
    /// A saját (`EGYEDI_`) kategóriák és az egész napos típusok nem számítanak bele.
    static func officialSeconds(_ entries: [Entry]) -> Int {
        entries.reduce(0) { sum, e in
            e.type.hasPrefix(ActivityType.customPrefix) ? sum : sum + e.creditSeconds
        }
    }

    static func hasWholeDayEntry(_ entries: [Entry]) -> Bool {
        entries.contains { $0.unit == Unit.wholeDay.rawValue }
    }

    enum TargetState: Equatable {
        case exempt          // nem kell napi óraszám (hétvége, jövő, szabadság stb.)
        case reached
        case inProgress      // a mai nap, még nincs meg
        case short           // múltbeli nap, nincs meg
    }

    /// A napi elvárt óraszám (hétfő–péntek) állapota.
    static func targetState(day: Date, entries: [Entry], today: Date, targetHours: Int) -> TargetState {
        let d = DateUtil.startOfDay(day), t = DateUtil.startOfDay(today)
        guard d <= t, DateUtil.isWeekday(d), !hasWholeDayEntry(entries) else { return .exempt }
        if officialSeconds(entries) >= max(1, targetHours) * 3600 { return .reached }
        return d == t ? .inProgress : .short
    }

    /// Hány egymást követő, bejegyzés nélküli nap van a tegnapig (a vasárnapot is számolva).
    /// Ha egyáltalán nincs bejegyzés, 0 (nincs mire emlékeztetni).
    static func consecutiveMissingDays(entryDates: Set<String>, today: Date, maxDays: Int = 366) -> Int {
        guard !entryDates.isEmpty else { return 0 }
        var count = 0
        var d = DateUtil.addDays(DateUtil.startOfDay(today), -1)
        while count < maxDays {
            if entryDates.contains(Fmt.dayFormatter.string(from: d)) { return count }
            count += 1
            d = DateUtil.addDays(d, -1)
        }
        return count
    }
}
