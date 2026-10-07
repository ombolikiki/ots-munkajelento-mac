import Foundation

// MARK: - Kézi felvitel az OTS-be: számítások
// A nézetektől független, tesztelhető logika. A számítás megegyezik a skill szabályaival
// (napi összegzés típusonként, a napi óraösszeg felfelé kerekítése, fő/alkalom darabszám, Munkahely lista).

/// Az OTS Havi munkajelentő egy napja (egy sor a táblázatban).
struct OTSWorkRow: Equatable {
    var date: Date
    var key: String                 // YYYY-MM-DD
    var workplace: String           // Munkahely mező szövege (SZABADNAP, MUNKASZÜNETI NAP, !!! előtag is lehet)
    var holiday: Bool               // Szabadság? jelölőnégyzet
    var values: [String: Int]       // típuskód → szám (óra, alkalom vagy fő); csak a nem nulla értékek
    var hasData: Bool               // van-e OTS-be vihető bejegyzés
    var notes: [String]             // magyarázat (8-ra korlátozva, saját kategória, üres nap…)

    var isEmpty: Bool { workplace.isEmpty && !holiday && values.isEmpty }
    /// A nap OTS-sorának szövege, a pipa érvényességének ellenőrzéséhez (ha változik a tartalom, a pipa érvényét veszti).
    var signature: String {
        workplace + "|" + (holiday ? "1" : "0") + "|" + values.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }
}

/// A Költségelszámolás egy napja (egy sor).
struct OTSCostRow: Equatable {
    var date: Date
    var key: String
    var routes: [[String]]          // minden Utazás bejegyzés útvonala (Indulás, Munkahely(ek), Érkezés)
    /// Ugyanezek a útvonalak pontos címekkel a Google Maps számára (az OTS-be a `routes` települései kerülnek).
    var mapRoutes: [[RoutePoint]] = []
    var activity: String
    var route: String { routes.map { $0.joined(separator: " - ") }.joined(separator: " ; ") }
    var multiple: Bool { routes.count > 1 }
    var signature: String { route + "|" + activity }
}

/// Az útvonal egy pontja: a település neve (az OTS-be ez kerül) és ha van, a pontos cím (a Google Mapsnek).
struct RoutePoint: Equatable {
    var name: String
    var address: String?
}

/// A létszámjelentő egy sora: esedékes nap és gyülekezet, a jelentés (ha van).
struct OTSAttendanceRow: Equatable {
    var date: Date
    var key: String
    var congregation: String
    var report: AttendanceReport?
    var id: String { key + "|" + congregation }
    var signature: String {
        guard let r = report else { return "-" }
        return [r.sabbathSchool.children, r.sabbathSchool.adults, r.sabbathSchool.guests,
                r.worship.children, r.worship.adults, r.worship.guests].map(String.init).joined(separator: ",")
    }
}

enum OTSManual {
    /// Az OTS Havi munkajelentő számoszlopai, a táblázat sorrendjében.
    static let columns: [ActivityType] = [
        .preaching, .visiting, .officeWork, .meeting, .evangelisation, .bibleHour, .missionVisiting,
        .training, .heldTraining, .administration, .preparing, .travel
    ]
    static let maxValue = 8

    /// A hónap napjai (0:00), sosem omlik össze érvénytelen hónapra sem.
    static func monthDays(year: Int, month: Int) -> [Date] {
        guard let first = DateUtil.date(year: year, month: month, day: 1) else { return [] }
        var result: [Date] = []
        var d = first
        var n = 0
        while DateUtil.components(d).month == month, n < 32 {
            result.append(d)
            d = DateUtil.addDays(d, 1)
            n += 1
        }
        return result
    }

    static func previousMonth(year: Int, month: Int) -> (year: Int, month: Int) { month <= 1 ? (year - 1, 12) : (year, month - 1) }
    static func nextMonth(year: Int, month: Int) -> (year: Int, month: Int) { month >= 12 ? (year + 1, 1) : (year, month + 1) }

    static func chronological(_ entries: [Entry]) -> [Entry] {
        entries.enumerated().sorted {
            switch ($0.element.start, $1.element.start) {
            case let (a?, b?): return a == b ? $0.offset < $1.offset : a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return $0.offset < $1.offset
            }
        }.map { $0.element }
    }

    /// Az útvonal pontjai: Indulás, Munkahely(ek), Érkezés. Az üres Indulás/Érkezés helyére a székhely kerül,
    /// az egymás melletti azonos pontok összevonódnak.
    static func routePoints(_ e: Entry, home: String) -> [String] {
        let dep = (e.departure ?? "").trimmingCharacters(in: .whitespaces)
        let arr = (e.arrival ?? "").trimmingCharacters(in: .whitespaces)
        let mids = e.workplace.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var points: [String] = []
        for p in [dep.isEmpty ? home : dep] + mids + [arr.isEmpty ? home : arr] where !p.isEmpty {
            if let last = points.last, last.caseInsensitiveCompare(p) == .orderedSame { continue }
            points.append(p)
        }
        return points
    }

    /// Az útvonal pontjai pontos címekkel: a Munkahely(ek) pontjaihoz a bejegyzés `Cím` mezőjének azonos településű címei
    /// kerülnek (sorrendben, egy cím egyszer); az Indulás és az Érkezés pontját a bejegyzés saját `Indulás cím` és `Érkezés cím` mezője adja (ha van). Az azonos nevű szomszédos pontok összevonódnak, ha a későbbinek nincs külön címe.
    static func routeDetail(_ e: Entry, home: String) -> [RoutePoint] {
        let dep = (e.departure ?? "").trimmingCharacters(in: .whitespaces)
        let arr = (e.arrival ?? "").trimmingCharacters(in: .whitespaces)
        let mids = e.workplace.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var pool = (e.address ?? "").components(separatedBy: " - ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var points: [RoutePoint] = []
        func add(_ p: RoutePoint) {
            guard !p.name.isEmpty else { return }
            // Az azonos nevű szomszédos pont összevonódik, ha a későbbi nem ad új információt (nincs külön címe).
            if let last = points.last, p.address == nil, last.name.caseInsensitiveCompare(p.name) == .orderedSame { return }
            points.append(p)
        }
        add(RoutePoint(name: dep.isEmpty ? home : dep, address: dep.isEmpty ? nil : e.departureAddress))
        for m in mids where !m.isEmpty {
            var found: String?
            if let i = pool.firstIndex(where: { (CalendarParser.place($0).settlement.map { CalendarParser.fold($0) } ?? "") == CalendarParser.fold(m) }) {
                found = pool.remove(at: i)
            }
            add(RoutePoint(name: m, address: found))
        }
        add(RoutePoint(name: arr.isEmpty ? home : arr, address: arr.isEmpty ? nil : e.arrivalAddress))
        return points
    }

    /// Munkahely mező: a nap bejegyzéseinek különböző helyei időrendben (az Utazás Munkahely(ek) elemei külön-külön).
    static func workplaceList(_ entries: [Entry]) -> [String] {
        var places: [String] = []
        for e in chronological(entries) {
            // Utazásnál a Munkahely(ek) lista, vagy ha a munkahely az Indulás volt, az Indulás.
            let parts = e.type == ActivityType.travel.code
                ? (e.workplaceIsDeparture ? [(e.departure ?? "").trimmingCharacters(in: .whitespaces)]
                                          : e.workplace.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                : [e.workplace.trimmingCharacters(in: .whitespaces)]
            for p in parts where !p.isEmpty && !places.contains(where: { $0.caseInsensitiveCompare(p) == .orderedSame }) {
                places.append(p)
            }
        }
        return places
    }

    /// Egy nap sora a Havi munkajelentőben.
    /// - Parameters:
    ///   - rules: az üres napok jelölése úgy, ahogy a skill írná: hétköznap, szombat és vasárnap is `!!!` (a vasárnap sem magától szabadnap:
    ///     szabadnapot Szabadnap bejegyzés jelöl). A sorokat a skill nem egészíti ki 8 órára.
    static func workRow(day: Date, entries: [Entry], rules: Bool, today: Date) -> OTSWorkRow {
        let d0 = DateUtil.startOfDay(day)
        var row = OTSWorkRow(date: d0, key: Fmt.dayFormatter.string(from: d0), workplace: "", holiday: false, values: [:], hasData: false, notes: [])
        let dayEntries = entries.filter { $0.date == row.key }
        let custom = dayEntries.filter { $0.type.hasPrefix(ActivityType.customPrefix) }
        let official = dayEntries.filter { !$0.type.hasPrefix(ActivityType.customPrefix) }
        let timed = official.filter { $0.unit != Unit.wholeDay.rawValue }
        let wholeDay = official.filter { $0.unit == Unit.wholeDay.rawValue }
        if !custom.isEmpty { row.notes.append("\(custom.count) saját kategóriás bejegyzés nem vihető az OTS-be") }

        if d0 > DateUtil.startOfDay(today) { return row }   // jövőbeli nap: üres

        // egész napos típusok
        if wholeDay.contains(where: { $0.type == ActivityType.holiday.code }) { row.holiday = true; row.hasData = true }
        if wholeDay.contains(where: { $0.type == ActivityType.dayOff.code }) { row.workplace = "SZABADNAP"; row.hasData = true }
        if wholeDay.contains(where: { $0.type == ActivityType.publicHoliday.code }) { row.workplace = "MUNKASZÜNETI NAP"; row.hasData = true }
        if row.hasData { return row }

        if timed.isEmpty {
            if rules {   // OTS-szempontból üres nap
                row.workplace = "!!!"
                row.notes.append("üres nap: !!! jelölés")
            }
            return row
        }

        row.hasData = true
        var sums: [String: Int] = [:]          // óra típusoknál másodperc
        var counts: [String: Int] = [:]        // alkalom/fő típusoknál darab
        for e in timed {
            switch e.unit {
            case Unit.hours.rawValue: sums[e.type, default: 0] += max(0, e.durationSeconds)
            default: counts[e.type, default: 0] += max(1, e.quantity ?? 1)
            }
        }
        var values: [String: Int] = [:]
        for (t, s) in sums where s > 0 { values[t] = (s + 3599) / 3600 }   // a napi összeget kerekítjük felfelé
        for (t, c) in counts where c > 0 { values[t] = c }
        for (t, v) in values where v > maxValue {
            row.notes.append("\(ActivityType.lookup(code: t)?.label ?? t): \(v) helyett \(maxValue) (legfeljebb \(maxValue) vihető fel)")
            values[t] = maxValue
        }

        row.workplace = workplaceList(timed).joined(separator: ", ")
        row.values = values.filter { $0.value > 0 }
        return row
    }

    // MARK: Költségelszámolás

    static func costRows(entries: [Entry], year: Int, month: Int, home: String) -> [OTSCostRow] {
        var rows: [OTSCostRow] = []
        for day in monthDays(year: year, month: month) {
            let key = Fmt.dayFormatter.string(from: day)
            let dayEntries = chronological(entries.filter { $0.date == key })
            let travel = dayEntries.filter { $0.type == ActivityType.travel.code }
            guard !travel.isEmpty else { continue }
            let routes = travel.map { routePoints($0, home: home) }.filter { !$0.isEmpty }
            let mapRoutes = travel.filter { !routePoints($0, home: home).isEmpty }.map { routeDetail($0, home: home) }
            // A Költségelszámolás Tevékenység mezőjét kizárólag az Utazás bejegyzések Tevékenysége adja (más kategóriából nem veszünk át szöveget).
            var texts: [String] = []
            for e in travel {
                let t = e.activity.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty, !texts.contains(t) { texts.append(t) }
            }
            rows.append(OTSCostRow(date: day, key: key, routes: routes, mapRoutes: mapRoutes, activity: texts.joined(separator: "; ")))
        }
        return rows
    }

    /// Google Maps többpontos útvonal-hivatkozás (autós útvonal, a pontok sorrendjében).
    static func mapsURL(_ points: [String]) -> URL? {
        let parts = points.compactMap { $0.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) }
        guard parts.count >= 2 else { return nil }
        return URL(string: "https://www.google.com/maps/dir/" + parts.joined(separator: "/"))
    }

    /// Google Maps útvonal pontos címekkel: a címet csak akkor használja, ha `useAddress` igazat ad rá (a geokódolós ellenőrzés
    /// eredménye); különben a település neve kerül a hivatkozásba.
    static func mapsURL(_ points: [RoutePoint], useAddress: (String) -> Bool) -> URL? {
        mapsURL(points.map { p in
            if let a = p.address, useAddress(a) { return a }
            return p.name
        })
    }

    // MARK: Létszámjelentő

    /// A hónap esedékes szombatjai (a regisztrált gyülekezetenként egy-egy sor), a hónapban rögzített, de nem esedékes napi jelentésekkel együtt.
    static func attendanceRows(reports: [AttendanceReport], congregations: [String], year: Int, month: Int) -> [OTSAttendanceRow] {
        let days = monthDays(year: year, month: month)
        guard let first = days.first, let last = days.last else { return [] }
        let due = AttendanceSchedule.dueDates(from: first, to: last)
        var keys = due.map { Fmt.dayFormatter.string(from: $0) }
        let prefix = String(Fmt.dayFormatter.string(from: first).prefix(7))
        for r in reports where r.date.hasPrefix(prefix) && !keys.contains(r.date) { keys.append(r.date) }
        keys.sort()
        var rows: [OTSAttendanceRow] = []
        for k in keys {
            guard let day = Fmt.dayFormatter.date(from: k) else { continue }
            var names = congregations
            for r in reports where r.date == k && !names.contains(where: { $0.caseInsensitiveCompare(r.congregation) == .orderedSame }) {
                names.append(r.congregation)
            }
            for c in names {
                let rep = reports.first { $0.date == k && $0.congregation.caseInsensitiveCompare(c) == .orderedSame }
                rows.append(OTSAttendanceRow(date: DateUtil.startOfDay(day), key: k, congregation: c, report: rep))
            }
        }
        return rows
    }
}
