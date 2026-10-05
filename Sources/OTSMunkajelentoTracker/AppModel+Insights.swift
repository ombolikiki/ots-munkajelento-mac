import Foundation

// MARK: - Visszatekintés, kitöltetlen és hiányos napok, emlékeztetők

extension Insights {
    /// A visszatekintési időszak első napja. `lookback`: "7" | "14" | "30" | "prevMonth" | "thisMonth".
    static func lookbackStart(_ lookback: String, today: Date) -> Date {
        let t = DateUtil.startOfDay(today)
        let c = DateUtil.components(t)
        switch lookback {
        case "thisMonth":
            return DateUtil.date(year: c.year, month: c.month, day: 1) ?? t
        case "prevMonth":
            let (y, m) = c.month == 1 ? (c.year - 1, 12) : (c.year, c.month - 1)
            return DateUtil.date(year: y, month: m, day: 1) ?? t
        default:
            return DateUtil.addDays(t, -(Int(lookback) ?? 30))
        }
    }

    /// A tartományba (a mai napot nem számítva) eső napok, amelyekhez nincs bejegyzés (a vasárnapot is beleértve).
    static func missingDays(entryDates: Set<String>, lookback: String, today: Date) -> [Date] {
        let t = DateUtil.startOfDay(today)
        var result: [Date] = []
        var d = lookbackStart(lookback, today: t)
        var guardCount = 0
        while d < t, guardCount < 800 {
            if !entryDates.contains(Fmt.dayFormatter.string(from: d)) { result.append(d) }
            d = DateUtil.addDays(d, 1)
            guardCount += 1
        }
        return result
    }

    /// Azok a múltbeli napok a tartományban, amelyeken van bejegyzés, de nincs meg az elvárt óraszám.
    static func shortDays(entriesByDate: [String: [Entry]], lookback: String, today: Date, targetHours: Int) -> [Date] {
        let t = DateUtil.startOfDay(today)
        var result: [Date] = []
        var d = lookbackStart(lookback, today: t)
        var guardCount = 0
        while d < t, guardCount < 800 {
            if let list = entriesByDate[Fmt.dayFormatter.string(from: d)], !list.isEmpty,
               targetState(day: d, entries: list, today: t, targetHours: targetHours) == .short {
                result.append(d)
            }
            d = DateUtil.addDays(d, 1)
            guardCount += 1
        }
        return result
    }

    /// A létszámjelentő esedékes napjai a tartományban (a mai napot is beleértve), amelyekhez nincs teljes jelentés.
    static func pendingAttendance(reports: [AttendanceReport], congregations: [String], lookback: String, today: Date) -> [Date] {
        guard !congregations.isEmpty else { return [] }
        let t = DateUtil.startOfDay(today)
        let due = AttendanceSchedule.dueDates(from: lookbackStart(lookback, today: t), to: t)
        return due.filter { day in
            let key = Fmt.dayFormatter.string(from: day)
            let have = Set(reports.filter { $0.date == key }.map { $0.congregation.lowercased() })
            return !congregations.allSatisfy { have.contains($0.lowercased()) }
        }
    }
}

extension AppModel {
    var entriesByDate: [String: [Entry]] { Dictionary(grouping: entries, by: { $0.date }) }
    var entryDateSet: Set<String> { Set(entries.map { $0.date }) }

    func missingDays(lookback: String) -> [Date] {
        Insights.missingDays(entryDates: entryDateSet, lookback: lookback, today: Date())
    }

    var targetHours: Int { max(1, ud.integer(forKey: "target.hours")) }

    func targetState(on day: Date) -> Insights.TargetState {
        Insights.targetState(day: day, entries: entries(on: day), today: Date(), targetHours: targetHours)
    }

    func officialSeconds(on day: Date) -> Int { Insights.officialSeconds(entries(on: day)) }

    func shortDays(lookback: String) -> [Date] {
        Insights.shortDays(entriesByDate: entriesByDate, lookback: lookback, today: Date(), targetHours: targetHours)
    }

    /// Hány egymást követő kitöltetlen nap van tegnapig.
    var consecutiveMissing: Int { Insights.consecutiveMissingDays(entryDates: entryDateSet, today: Date()) }

    /// Igaz, ha az emlékeztető be van kapcsolva, és elérte a megadott napszámot.
    var reminderActive: Bool {
        guard ud.bool(forKey: "reminder.enabled") else { return false }
        return consecutiveMissing >= max(1, ud.integer(forKey: "reminder.days"))
    }
}

// MARK: - Gyülekezeti létszámjelentő

extension AppModel {
    var attendanceEnabled: Bool { ud.bool(forKey: "attendance.enabled") && !attendanceCongregations.isEmpty }

    /// A regisztrált gyülekezetek betöltése; a kézzel szerkesztett vagy hibás lista (üres elemek, kis-nagybetű szerinti duplikátumok) megtisztítva.
    func loadAttendanceCongregations() {
        var seen = Set<String>()
        attendanceCongregations = (ud.stringArray(forKey: "attendance.congregations") ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    private func storeCongregations(_ list: [String]) {
        attendanceCongregations = list
        ud.set(list, forKey: "attendance.congregations")
    }

    func addAttendanceCongregation(_ name: String) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !attendanceCongregations.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else { return }
        storeCongregations(attendanceCongregations + [t])
    }

    func removeAttendanceCongregation(_ name: String) {
        storeCongregations(attendanceCongregations.filter { $0 != name })
    }

    func moveAttendanceCongregation(_ name: String, by delta: Int) {
        guard let i = attendanceCongregations.firstIndex(of: name) else { return }
        let j = i + delta
        guard attendanceCongregations.indices.contains(j) else { return }
        var list = attendanceCongregations
        list.swapAt(i, j)
        storeCongregations(list)
    }

    // MARK: Fájlkezelés

    func loadAttendanceFromDisk() {
        guard FileManager.default.fileExists(atPath: attendanceFileURL.path) else { return }
        do {
            let result = try AttendanceCSV.decode(Data(contentsOf: attendanceFileURL))
            attendance = result.reports
            attendanceLastModified = modificationDate(of: attendanceFileURL)
            if !result.warnings.isEmpty {
                lastError = "\(result.warnings.count) sor kimaradt a létszámjelentő fájlból: " + result.warnings.prefix(2).joined(separator: "; ")
            }
        } catch {
            lastError = "A létszámjelentő fájl nem olvasható: \(error.localizedDescription)"
        }
    }

    func reloadAttendanceIfChanged() {
        guard FileManager.default.fileExists(atPath: attendanceFileURL.path),
              let mod = modificationDate(of: attendanceFileURL), mod != attendanceLastModified else { return }
        loadAttendanceFromDisk()
    }

    func saveAttendance() {
        // Ha nincs mit menteni és a fájl sincs meg, ne hozzunk létre üres fájlt.
        if attendance.isEmpty, !FileManager.default.fileExists(atPath: attendanceFileURL.path) { return }
        do {
            try FileManager.default.createDirectory(at: attendanceFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try AttendanceCSV.encode(attendance).write(to: attendanceFileURL, options: .atomic)
            attendanceLastModified = modificationDate(of: attendanceFileURL)
        } catch {
            lastError = "Mentési hiba (létszámjelentő): \(error.localizedDescription)"
        }
    }

    // MARK: Műveletek

    func reports(on day: Date) -> [AttendanceReport] {
        let key = Fmt.dayFormatter.string(from: day)
        return attendanceCongregations.compactMap { c in
            attendance.first { $0.date == key && $0.congregation.caseInsensitiveCompare(c) == .orderedSame }
        }
    }

    /// Egy nap jelentéseinek mentése (a megadott gyülekezetek régi jelentését lecseréli).
    func saveReports(day: Date, reports newOnes: [AttendanceReport]) {
        guard !isFuture(day) else {
            lastError = "Jövőbeli napra nem lehet létszámjelentőt rögzíteni."
            return
        }
        let key = Fmt.dayFormatter.string(from: day)
        attendance.removeAll { r in
            r.date == key && newOnes.contains { $0.congregation.caseInsensitiveCompare(r.congregation) == .orderedSame }
        }
        attendance.append(contentsOf: newOnes.map { var r = $0; r.date = key; return r })
        attendance.sort { ($0.date, $0.congregation) < ($1.date, $1.congregation) }
        saveAttendance()
    }

    /// Az esedékes, még hiányos jelentésű napok a visszatekintési időszakban (a mai napot is beleértve).
    func pendingAttendanceDates(lookback: String) -> [Date] {
        guard attendanceEnabled else { return [] }
        return Insights.pendingAttendance(reports: attendance, congregations: attendanceCongregations, lookback: lookback, today: Date())
    }

    func isAttendanceDue(on day: Date) -> Bool { attendanceEnabled && AttendanceSchedule.isDue(day) }
}
