import Foundation
import SwiftUI
import AppKit
import EventKit

// Önellenőrző teszt: a scripts/selftest.sh építi és futtatja (Xcode/XCTest nélkül).
// Minden teszt külön, ideiglenes mappában fut, a valódi adatokhoz nem nyúl.

let tmp = ProcessInfo.processInfo.environment["OTS_SUPPORT_DIR"] ?? NSTemporaryDirectory() + "ots-selftest"
UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
for k in UserDefaults.standard.dictionaryRepresentation().keys { UserDefaults.standard.removeObject(forKey: k) }
UserDefaults.standard.set(tmp + "/data/bejegyzesek.csv", forKey: "dataFile")
_ = NSApplication.shared

var failures = 0
var total = 0
func check(_ name: String, _ ok: Bool, _ extra: String = "") {
    total += 1
    if !ok { failures += 1; print("HIBA", name, extra) }
}
func section(_ s: String) { print("— \(s)") }

let cal = DateUtil.gregorian
func d(_ y: Int, _ m: Int, _ day: Int) -> Date { DateUtil.date(year: y, month: m, day: day) ?? Date(timeIntervalSince1970: 0) }
func ymd(_ x: Date) -> String { Fmt.dayFormatter.string(from: x) }

// MARK: Dátumszámítás

section("Dátumszámítás (\(TimeZone.current.identifier))")
check("érvénytelen dátum nil", DateUtil.date(year: 2026, month: 2, day: 30) == nil && DateUtil.date(year: 2026, month: 13, day: 1) == nil && DateUtil.date(year: 0, month: 1, day: 1) == nil)
check("szökőnap érvényes", DateUtil.date(year: 2028, month: 2, day: 29) != nil && DateUtil.date(year: 2027, month: 2, day: 29) == nil)
check("addDays évhatáron", ymd(DateUtil.addDays(d(2026, 12, 31), 1)) == "2027-01-01" && ymd(DateUtil.addDays(d(2027, 1, 1), -1)) == "2026-12-31")
check("addDays nyári időszámítás váltásán át napra pontos", ymd(DateUtil.addDays(d(2026, 3, 28), 2)) == "2026-03-30" && ymd(DateUtil.addDays(d(2026, 10, 24), 2)) == "2026-10-26")

for year in 2024...2035 {
    for q in 1...4 {
        let sats = DateUtil.saturdays(year: year, quarter: q)
        let tag = "\(year)/Q\(q)"
        check("\(tag): 12–14 szombat", (12...14).contains(sats.count), "\(sats.count)")
        check("\(tag): mind szombat", sats.allSatisfy { DateUtil.isSaturday($0) })
        let due = AttendanceSchedule.dueDates(year: year, quarter: q)
        check("\(tag): két esedékes nap", due.count == 2)
        if due.count == 2 {
            check("\(tag): szombat és a negyedévben van", DateUtil.isSaturday(due[0]) && DateUtil.isSaturday(due[1]) && DateUtil.quarter(of: due[0]) == (year, q) && DateUtil.quarter(of: due[1]) == (year, q))
            let diff = cal.dateComponents([.day], from: due[0], to: due[1]).day ?? -1
            check("\(tag): 35 nap a két dátum között", diff == 35, "\(diff)")
            check("\(tag): a második szombat a 8–14. nap egyike a negyedévből" , {
                guard let qs = DateUtil.quarterStart(year: year, quarter: q) else { return false }
                let n = (cal.dateComponents([.day], from: qs, to: due[0]).day ?? -1) + 1
                return (8...14).contains(n) || (due[0] == sats[1] && (2...14).contains(n))
            }())
        }
    }
}
let known: [(Int, Int, String, String)] = [(2026, 3, "2026-07-11", "2026-08-15"), (2026, 4, "2026-10-10", "2026-11-14"), (2027, 1, "2027-01-09", "2027-02-13")]
for k in known {
    let due = AttendanceSchedule.dueDates(year: k.0, quarter: k.1).map(ymd)
    check("ismert példa \(k.0)/Q\(k.1)", due == [k.2, k.3], "\(due)")
}
check("dueDates tartományon át, évhatárral", AttendanceSchedule.dueDates(from: d(2026, 12, 1), to: d(2027, 2, 28)).map(ymd) == ["2027-01-09", "2027-02-13"])
check("dueDates üres/fordított tartomány", AttendanceSchedule.dueDates(from: d(2026, 5, 1), to: d(2026, 4, 1)).isEmpty)
check("isDue", AttendanceSchedule.isDue(d(2026, 10, 10)) && !AttendanceSchedule.isDue(d(2026, 10, 17)) && !AttendanceSchedule.isDue(d(2026, 10, 11)))
check("hét kezdete hétfővel évhatáron", ymd(DateUtil.startOfWeek(d(2026, 1, 1), firstWeekday: 2)) == "2025-12-29")
check("hét kezdete vasárnappal évhatáron", ymd(DateUtil.startOfWeek(d(2026, 1, 1), firstWeekday: 1)) == "2025-12-28")
check("hét kezdete: vasárnap hétfővel", ymd(DateUtil.startOfWeek(d(2026, 10, 4), firstWeekday: 2)) == "2026-09-28" && ymd(DateUtil.startOfWeek(d(2026, 10, 4), firstWeekday: 1)) == "2026-10-04")
check("hét kezdete: szombat vasárnappal", ymd(DateUtil.startOfWeek(d(2026, 10, 3), firstWeekday: 1)) == "2026-09-27")
check("hét kezdete: érvénytelen kezdőnap tartalékra vált", ymd(DateUtil.startOfWeek(d(2026, 10, 7), firstWeekday: 5)) == "2026-10-05")
check("lookback: e hónap", ymd(Insights.lookbackStart("thisMonth", today: d(2026, 10, 3))) == "2026-10-01")
check("lookback: előző hónap januárban", ymd(Insights.lookbackStart("prevMonth", today: d(2027, 1, 5))) == "2026-12-01")
check("lookback: napok és ismeretlen érték", ymd(Insights.lookbackStart("14", today: d(2026, 3, 1))) == "2026-02-15" && ymd(Insights.lookbackStart("x", today: d(2026, 3, 31))) == "2026-03-01")

// MARK: Összesítések és jelzések

section("Összesítések")
func entry(_ type: ActivityType, secs: Int = 0, q: Int? = nil, date: String = "2026-10-05", place: String = "Győr", act: String = "x") -> Entry {
    Entry(id: UUID(), date: date, start: nil, end: nil, durationSeconds: secs, workplace: place, type: type.code, typeLabel: type.label,
          unit: type.unit.rawValue, quantity: q, activity: act, source: "manual")
}
let day8 = [entry(.meeting, secs: 5 * 3600), entry(.missionVisiting, q: 2), entry(.preaching, q: 1)]
check("fő és alkalom 1 óra", Insights.officialSeconds(day8) == 8 * 3600)
let custom = ActivityType(code: "EGYEDI_X", group: "Egyéni", shortLabel: "X", label: "X", unit: .hours, isCustom: true)
check("saját kategória nem számít", Insights.officialSeconds([entry(.meeting, secs: 3600), entry(custom, secs: 7200)]) == 3600)
let mon = d(2026, 10, 5), sat = d(2026, 10, 10), sun = d(2026, 10, 11), today = d(2026, 10, 7)
check("hétfő 8 óra: kész", Insights.targetState(day: mon, entries: day8, today: today, targetHours: 8) == .reached)
check("hétfő 3 óra: hiányzik", Insights.targetState(day: mon, entries: [entry(.meeting, secs: 3 * 3600)], today: today, targetHours: 8) == .short)
check("üres hétköznap: hiányzik", Insights.targetState(day: mon, entries: [], today: today, targetHours: 8) == .short)
check("üres szombat és vasárnap jelez (piros), a hétvégén nincs napi óraszám", Insights.targetState(day: sat, entries: [], today: d(2026, 10, 14), targetHours: 8) == .short && Insights.targetState(day: sun, entries: [], today: d(2026, 10, 14), targetHours: 8) == .short)
check("hétvégén bármilyen bejegyzés elég (nem 8 óra)", Insights.targetState(day: sat, entries: [entry(.preaching, q: 1)], today: d(2026, 10, 14), targetHours: 8) == .exempt && Insights.targetState(day: sun, entries: [entry(.meeting, secs: 600)], today: d(2026, 10, 14), targetHours: 8) == .exempt)
check("hétvégén a szabadnap kitöltöttnek számít", Insights.targetState(day: sun, entries: [entry(.dayOff)], today: d(2026, 10, 14), targetHours: 8) == .exempt)
check("a mai üres hétvégi nap folyamatban (narancs), a jövőbeli mentes", Insights.targetState(day: sat, entries: [], today: sat, targetHours: 8) == .inProgress && Insights.targetState(day: sun, entries: [], today: sat, targetHours: 8) == .exempt)
check("szabadság mentes", Insights.targetState(day: mon, entries: [entry(.holiday)], today: today, targetHours: 8) == .exempt)
check("mai nap folyamatban", Insights.targetState(day: today, entries: [entry(.meeting, secs: 3600)], today: today, targetHours: 8) == .inProgress)
check("jövő mentes", Insights.targetState(day: d(2026, 10, 8), entries: [], today: today, targetHours: 8) == .exempt)
check("elvárt óraszám állítható", Insights.targetState(day: mon, entries: [entry(.meeting, secs: 6 * 3600)], today: today, targetHours: 6) == .reached)

section("Hosszú kihagyás")
func dates(_ list: [Date]) -> Set<String> { Set(list.map(ymd)) }
check("nincs bejegyzés: 0", Insights.consecutiveMissingDays(entryDates: [], today: today) == 0)
check("tegnap volt: 0", Insights.consecutiveMissingDays(entryDates: dates([d(2026, 10, 6)]), today: today) == 0)
check("9 napja volt: 8", Insights.consecutiveMissingDays(entryDates: dates([d(2026, 9, 28)]), today: today) == 8)
check("mai nap nem számít", Insights.consecutiveMissingDays(entryDates: dates([d(2026, 10, 7)]), today: today) == 366)
check("évhatáron át", Insights.consecutiveMissingDays(entryDates: dates([d(2026, 12, 20)]), today: d(2027, 1, 3)) == 13)
check("maxDays korlát", Insights.consecutiveMissingDays(entryDates: dates([d(2020, 1, 1)]), today: today, maxDays: 50) == 50)

section("Kitöltetlen és hiányos napok")
check("hónap első napján nincs kitöltetlen", Insights.missingDays(entryDates: [], lookback: "thisMonth", today: d(2026, 11, 1)).isEmpty)
check("vasárnap is hiányzik", Insights.missingDays(entryDates: [], lookback: "thisMonth", today: d(2026, 10, 5)).map(ymd) == ["2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04"])
check("kitöltött nap kimarad", Insights.missingDays(entryDates: dates([d(2026, 10, 2)]), lookback: "thisMonth", today: d(2026, 10, 4)).map(ymd) == ["2026-10-01", "2026-10-03"])
let byDate = ["2026-10-05": [entry(.meeting, secs: 3600)], "2026-10-06": day8]
check("hiányos napok", Insights.shortDays(entriesByDate: byDate, lookback: "thisMonth", today: d(2026, 10, 8), targetHours: 8).map(ymd) == ["2026-10-05"])

// MARK: CSV

section("CSV")
var travel = entry(.travel, secs: 3600, place: "Tata, Mór", act: "Kiszállás")
travel.departure = "Győr"; travel.arrival = "Győr"
let plain = entry(.meeting, secs: 1800, place: "Győr")
let enc = CSV.encode([travel, plain])
let dec = (try? CSV.decode(enc)) ?? CSV.DecodeResult(entries: [], warnings: ["hiba"])
check("utazás oda-vissza", dec.entries.count == 2 && dec.warnings.isEmpty)
let t2 = dec.entries.first { $0.type == "TRAVEL" }
check("indulás/érkezés/munkahelyek megmaradnak", t2?.departure == "Győr" && t2?.arrival == "Győr" && t2?.workplace == "Tata, Mór")
check("más típusnál nincs indulás/érkezés", dec.entries.first { $0.type == "MEETING" }?.departure == nil)
let old = "Dátum;Kezdés;Vége;Munkahely;Típus kód;Tevékenység\n2026-10-01;;;Győr;TRAVEL;régi utazás\n"
let oldDec = try? CSV.decode(Data(old.utf8))
check("régi (indulás nélküli) fájl olvasható", oldDec?.entries.count == 1 && oldDec?.entries.first?.departure == nil)
let bad = "Dátum;Típus kód;Időtartam (mp)\n2026-10-01;MEETING;inf\n2026-10-01;MEETING;1e99\n"
check("hibás számok nem omlasztanak", (try? CSV.decode(Data(bad.utf8)))?.entries.count == 2)
check("fejléc tartalmazza az új oszlopokat", String(data: enc, encoding: .utf8)?.contains("Indulás;Munkahely;Érkezés") == true)

section("Létszámjelentő CSV")
var r1 = AttendanceReport(date: "2026-10-10", congregation: "Győr")
r1.sabbathSchool = AttendanceCounts(children: 3, adults: 12, guests: 6)
r1.worship = AttendanceCounts(children: 4, adults: 24, guests: 12)
var r2 = AttendanceReport(date: "2026-10-10", congregation: "Tata, \"Nagy\"")
r2.worship.adults = 17
let aenc = AttendanceCSV.encode([r2, r1])
let adec = try? AttendanceCSV.decode(aenc)
check("létszám oda-vissza", adec?.reports.count == 2 && adec?.reports.first { $0.congregation == "Győr" } == r1 && adec?.reports.first { $0.congregation.hasPrefix("Tata") } == r2)
let aText = "\u{FEFF}Dátum,Gyülekezet,Szombatiskola gyermek,Istentisztelet felnőtt adventista\r\n2026. 10. 10.,Győr,3,x\r\n2026-10-10,Győr,5,99999999\r\nrossz,Tata,1,2\r\n"
let adec2 = try? AttendanceCSV.decode(Data(aText.utf8))
check("létszám: lazább formátum, ismétlődés felülírva, hibás sor figyelmeztetéssel",
      adec2?.reports.count == 1 && adec2?.reports.first?.sabbathSchool.children == 5 && adec2?.warnings.count == 1, "\(String(describing: adec2))")
check("létszám: extrém szám korlátozva", (adec2?.reports.first?.worship.adults ?? 0) <= 99_999)
let pend = Insights.pendingAttendance(reports: [r1], congregations: ["Győr"], lookback: "thisMonth", today: d(2026, 10, 12))
check("kész jelentés nem hiányzik", pend.isEmpty)
let pend2 = Insights.pendingAttendance(reports: [r1], congregations: ["Győr", "Tata"], lookback: "thisMonth", today: d(2026, 10, 12))
check("hiányzó gyülekezet esetén hiányzik", pend2.map(ymd) == ["2026-10-10"])
check("a mai esedékes nap is szerepel", Insights.pendingAttendance(reports: [], congregations: ["Győr"], lookback: "thisMonth", today: d(2026, 10, 10)).map(ymd) == ["2026-10-10"])
check("nincs gyülekezet: nincs teendő", Insights.pendingAttendance(reports: [], congregations: [], lookback: "thisMonth", today: d(2026, 10, 12)).isEmpty)

// MARK: Színsémák

section("Színsémák")
check("négy színséma, ismeretlen id kékre vált", Palette.all.count == 4 && Palette.byID("nincs").id == "blue" && Set(Palette.all.map { $0.id }).count == 4)

// MARK: Modell

section("Modell")
let support = ProcessInfo.processInfo.environment["OTS_SUPPORT_DIR"] ?? tmp
try? FileManager.default.removeItem(atPath: tmp + "/data")
UserDefaults.standard.set("Székesfehérvár", forKey: "home")
let m = AppModel()
m.selectedType = .travel
check("utazás: a kiindulás alapja a székhely, a cél üres", m.departure == "Székesfehérvár" && m.destination.isEmpty && m.roundTrip && !m.workplaceIsDeparture)
check("utazás: cél és tevékenység kell", !m.fieldsComplete && (m.missingFieldsHint ?? "").contains("Cél"))
m.destination = " Tata ,Mór, ,"; m.activity = "Kiszállás"
check("utazás: teljes", m.fieldsComplete && m.travelPlan?.stops.map { $0.settlement } == ["Tata", "Mór"])
let start = Date().addingTimeInterval(-3600)
m.add(m.makeEntry(start: start, end: start.addingTimeInterval(1800), source: "manual"))
let saved = m.entries.last
check("utazás bejegyzés mezői", saved?.departure == "Székesfehérvár" && saved?.arrival == "Székesfehérvár" && saved?.workplace == "Tata, Mór")
check("minden utazási hely bekerült a listába", ["Tata", "Mór", "Székesfehérvár"].allSatisfy { p in m.places.contains(p) })
m.clearDraft()
check("clearDraft: kiindulás és cél is üres, az oda-vissza újra bejelölt", m.departure.isEmpty && m.destination.isEmpty && m.roundTrip && !m.workplaceIsDeparture && m.selectedType == nil)
m.selectedType = .meeting
check("nem utazásnál nem kell indulás", m.departure.isEmpty)
m.clearDraft()

UserDefaults.standard.set(true, forKey: "attendance.enabled")
m.addAttendanceCongregation("Győr"); m.addAttendanceCongregation("győr"); m.addAttendanceCongregation("Tata")
check("gyülekezet regisztrálás (duplikátum nélkül)", m.attendanceCongregations == ["Győr", "Tata"])
m.moveAttendanceCongregation("Tata", by: -1)
check("sorrend módosítás", m.attendanceCongregations == ["Tata", "Győr"])
check("létszámjelentő be van kapcsolva", m.attendanceEnabled)
// múltbeli esedékes nap (a jövőbeli napot a program helyesen elutasítja)
let pastSat = AttendanceSchedule.dueDates(year: 2025, quarter: 4).first ?? d(2025, 10, 11)
r1.date = ymd(pastSat)
m.saveReports(day: pastSat, reports: [r1])
check("jelentés mentése fájlba", FileManager.default.fileExists(atPath: m.attendanceFileURL.path))
let m2 = AppModel()
check("jelentés újraindítás után megvan", m2.attendance.contains { $0.congregation == "Győr" && $0.date == ymd(pastSat) })
check("jövőbeli napra nem menthető", { let n = m2.attendance.count; m2.saveReports(day: DateUtil.addDays(Date(), 7), reports: [r1]); return m2.attendance.count == n }())
check("reset: létszámjelentés is törlődik, másolat marad", m.resetAllData() && m.attendance.isEmpty && FileManager.default.fileExists(atPath: m.attendanceFileURL.deletingLastPathComponent().appendingPathComponent("letszamjelentesek.torles-elotti.csv").path))

// MARK: Hibás beállítások nem okozhatnak összeomlást

section("Hibás beállítások")
UserDefaults.standard.set(["Győr", "győr", " ", "Tata", "TATA ", ""], forKey: "attendance.congregations")
UserDefaults.standard.set(true, forKey: "attendance.enabled")
let dupModel = AppModel()
check("duplikált és üres gyülekezetek kiszűrve betöltéskor", dupModel.attendanceCongregations == ["Győr", "Tata"], "\(dupModel.attendanceCongregations)")
UserDefaults.standard.set(99, forKey: "cal.startHour"); UserDefaults.standard.set(-5, forKey: "cal.endHour")
UserDefaults.standard.set(0, forKey: "reminder.days"); UserDefaults.standard.set(0, forKey: "target.hours")
UserDefaults.standard.set("nincs-ilyen", forKey: "missing.lookback")
check("érvénytelen értékek mellett is számol (nincs összeomlás)", dupModel.targetHours >= 1 && dupModel.missingDays(lookback: "nincs-ilyen").count >= 0 && (dupModel.reminderActive || !dupModel.reminderActive))
for k in ["cal.startHour", "cal.endHour", "reminder.days", "target.hours", "missing.lookback", "attendance.congregations", "attendance.enabled"] { UserDefaults.standard.removeObject(forKey: k) }

// MARK: Skill-telepítő

section("Skill-telepítő")
if ProcessInfo.processInfo.environment["OTS_SKILL_SOURCE"] != nil, ProcessInfo.processInfo.environment["OTS_HOME"] != nil {
    let fm = FileManager.default
    let homeRoot = ProcessInfo.processInfo.environment["OTS_HOME"] ?? ""
    try? fm.removeItem(atPath: homeRoot)
    try? fm.createDirectory(atPath: homeRoot, withIntermediateDirectories: true)
    func text(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
    func exists(_ target: SkillTarget, _ rel: String) -> Bool { fm.fileExists(atPath: SkillInstaller.skillDir(for: target).appendingPathComponent(rel).path) }
    func noLeftovers(_ target: SkillTarget) -> Bool {
        guard let en = fm.enumerator(at: SkillInstaller.skillDir(for: target), includingPropertiesForKeys: nil) else { return false }
        for case let u as URL in en where !u.hasDirectoryPath && !u.lastPathComponent.hasPrefix(".") {
            let t = text(u)
            if t.contains("{{") || t.contains("[[TASK") || t.contains("[[SHARED") || t.contains("[[/") { return false }
        }
        return true
    }

    let inst = SkillInstaller(model: m)
    check("tasks.json: öt feladat", inst.tasks.count == 5 && Set(inst.tasks.map { $0.id }) == ["havi", "koltseg", "nevsor", "hittan", "latogatottsag"])
    check("a csomag azonosítója stabil", inst.bundledFingerprint() == inst.bundledFingerprint() && inst.bundledFingerprint() != nil)

    // érvényesítés
    inst.selectedTasks = Set(inst.tasks.map { $0.id })
    inst.userName = ""; inst.home = ""; inst.congregations = ""
    check("név nélkül nem telepíthető", inst.detailsError != nil && !inst.install())
    inst.userName = "Kovács János & Társa $1"
    check("székhely nélkül nem (költségelszámolás)", inst.detailsError != nil)
    inst.home = "Székesfehérvár"
    check("gyülekezetek nélkül nem (névsor)", inst.detailsError != nil)
    inst.congregations = "Székesfehérvár, Mór, székesfehérvár , Bicske,"
    check("duplikátum és üres elem kiszűrve", inst.parsedCongregations == ["Székesfehérvár", "Mór", "Bicske"])
    check("nincs hiba", inst.detailsError == nil)
    inst.selectedTargets = []
    check("cél nélkül nem telepíthető", inst.targetsError != nil && !inst.install())
    inst.selectedTasks = []
    check("feladat nélkül nem telepíthető", inst.tasksError != nil)

    // 1) minden feladat, Claude
    inst.selectedTasks = Set(inst.tasks.map { $0.id })
    inst.selectedTargets = [.claude]
    check("minden feladat telepítése (Claude)", inst.install(), inst.errorText ?? "")
    check("minden fájl megvan", ["SKILL.md", "references/havi-munkajelento.md", "references/koltsegelszamolas.md", "references/gyulekezeti-nevsor.md",
                                  "references/hitoktatas.md", "references/latogatottsag.md", "references/tracker-adatforras.md"].allSatisfy { exists(.claude, $0) })
    check("tasks.json nem kerül a telepítésbe", !exists(.claude, "tasks.json"))
    check("nincs helyőrző/jelölő", noLeftovers(.claude))
    let skill1 = text(SkillInstaller.skillDir(for: .claude).appendingPathComponent("SKILL.md"))
    check("név, gyülekezetek, székhely a SKILL.md-ben", skill1.contains("Kovács János & Társa $1") && skill1.contains("Székesfehérvár, Mór, Bicske") && skill1.contains("Székhely (a költségelszámolás útvonalainak kiindulópontja): Székesfehérvár"))
    check("Claude: beépített böngésző szövege", skill1.contains("mcp__Claude_Browser__"))
    check("mind az öt feladat sora megvan", ["Havi munkajelentő", "Költségelszámolás", "Gyülekezeti névsor", "Hitoktatás", "Gyülekezeti látogatottság"].allSatisfy { skill1.contains($0) })
    check("közös adatforrás-szakasz megvan", skill1.contains("tracker-adatforras.md"))
    let lat = text(SkillInstaller.skillDir(for: .claude).appendingPathComponent("references/latogatottsag.md"))
    check("létszámjelentő: tracker + soha nem talál ki számot", lat.contains("letszamjelentesek.csv") && lat.contains("Soha ne írj be kitalált") && !lat.contains("±3"))
    let kolt = text(SkillInstaller.skillDir(for: .claude).appendingPathComponent("references/koltsegelszamolas.md"))
    check("költségelszámolás: Indulás - Munkahely(ek) - Érkezés és Google Maps többpontos útvonal", kolt.contains("Indulás - Munkahely1") && kolt.contains("maps/dir/<Indulás>/<Munkahely1>"))
    check("költségelszámolás: székhely a helyőrző helyén", kolt.contains("Székesfehérvár") && !kolt.contains("Győr"))
    check("jelölő a telepítésen: feladatok és célok", {
        let d = (try? Data(contentsOf: SkillInstaller.skillDir(for: .claude).appendingPathComponent(SkillInstaller.markerName))) ?? Data()
        let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
        return (o?["tasks"] as? [String])?.count == 5 && (o?["targets"] as? [String]) == ["claude"]
    }())
    check("állapot: naprakész", inst.status[.claude] == .upToDate)

    // 2) csak a névsor, Codex: csak az szerepel
    inst.selectedTasks = ["nevsor"]
    inst.selectedTargets = [.codex]
    inst.home = ""      // a névsor nem kér székhelyet
    check("csak névsor: nincs székhely-igény", !inst.needsHome && inst.needsCongregations && inst.detailsError == nil)
    check("névsor telepítése (Codex)", inst.install(), inst.errorText ?? "")
    check("csak a névsor fájlja és a SKILL.md van meg", exists(.codex, "SKILL.md") && exists(.codex, "references/gyulekezeti-nevsor.md")
          && !exists(.codex, "references/havi-munkajelento.md") && !exists(.codex, "references/koltsegelszamolas.md")
          && !exists(.codex, "references/latogatottsag.md") && !exists(.codex, "references/hitoktatas.md") && !exists(.codex, "references/tracker-adatforras.md"))
    check("nincs helyőrző/jelölő (Codex)", noLeftovers(.codex))
    let skill2 = text(SkillInstaller.skillDir(for: .codex).appendingPathComponent("SKILL.md"))
    let otherRefs = ["havi-munkajelento.md", "koltsegelszamolas.md", "hitoktatas.md", "latogatottsag.md", "tracker-adatforras.md"]
    let otherRows = ["- Havi munkajelentő: TASK", "- Költségelszámolás: TASK", "- Hitoktatás (Hittan): TASK", "- Gyülekezeti látogatottság: TASK"]
    check("csak a névsor feladat-hivatkozása a SKILL.md-ben",
          skill2.contains("gyulekezeti-nevsor.md") && skill2.contains("- Gyülekezeti névsor: TASK")
          && otherRefs.allSatisfy { !skill2.contains($0) } && otherRows.allSatisfy { !skill2.contains($0) })
    check("nincs közös adatforrás-szakasz", !skill2.contains("tracker-adatforras.md"))
    check("székhely sor nélkül, gyülekezetek sorral", skill2.contains("Gyülekezetek: Székesfehérvár, Mór, Bicske") && !skill2.contains("Székhely (a költségelszámolás"))
    check("nem Claude: általános böngészőszöveg", !skill2.contains("mcp__Claude_Browser__") && skill2.contains("böngésző- vagy számítógép-vezérlő eszközt"))
    check("Codex mappa: ~/.agents/skills", SkillInstaller.skillDir(for: .codex).path.hasSuffix(".agents/skills/ots-adminisztracio"))

    // 3) Codex + Antigravity CLI: egyetlen közös mappa (~/.agents/skills)
    inst.selectedTargets = [.codex, .antigravity]
    let folders = inst.effectiveFolders()
    check("Codex + Antigravity: egy közös mappa", folders.count == 1 && folders[0].url.path.hasSuffix(".agents/skills") && folders[0].targets.count == 2)
    inst.selectedTargets = [.antigravity]
    check("csak Antigravity: ~/.agents/skills (ott tölti be az agy)", inst.effectiveFolders().first?.url.path.hasSuffix(".agents/skills") == true && SkillTarget.antigravity.relativePath == ".agents/skills")
    inst.selectedTargets = [.claude, .antigravity]
    check("Claude + Antigravity: két mappa", inst.effectiveFolders().count == 2)

    // 4) költségelszámolás önmagában: közös adatforrás kell, székhely kell, gyülekezet nem
    inst.selectedTargets = [.antigravity]
    inst.selectedTasks = ["koltseg"]
    inst.congregations = ""
    inst.home = ""
    check("csak költségelszámolás: székhely kell, gyülekezet nem", inst.needsHome && !inst.needsCongregations && inst.detailsError != nil)
    inst.home = "Pécs"
    check("költségelszámolás telepítése (Antigravity)", inst.install(), inst.errorText ?? "")
    check("közös adatforrás-fájl is megvan", exists(.antigravity, "references/tracker-adatforras.md") && exists(.antigravity, "references/koltsegelszamolas.md") && !exists(.antigravity, "references/havi-munkajelento.md"))
    let skill3 = text(SkillInstaller.skillDir(for: .antigravity).appendingPathComponent("SKILL.md"))
    check("székhely sor, gyülekezet nélkül", skill3.contains("Székhely (a költségelszámolás útvonalainak kiindulópontja): Pécs") && !skill3.contains("Gyülekezetek:"))
    check("nincs helyőrző/jelölő (Antigravity)", noLeftovers(.antigravity))

    // 5) újratelepítés: másolat készül, a skillek mappájában nem marad maradék
    inst.selectedTasks = ["koltseg", "havi"]
    inst.userName = "Nagy Éva"
    check("újratelepítés", inst.install())
    check("biztonsági másolat készült", inst.results.first?.backup != nil && fm.fileExists(atPath: (inst.results.first?.backup ?? "") + "/ots-adminisztracio/SKILL.md"))
    let entries = (try? fm.contentsOfDirectory(atPath: SkillInstaller.skillsRoot(for: .antigravity).path)) ?? []
    check("a skillek mappájában csak a skill van", entries == ["ots-adminisztracio"], "\(entries)")

    // 6) kézzel telepített skill felismerése
    try? fm.removeItem(at: SkillInstaller.skillDir(for: .antigravity).appendingPathComponent(SkillInstaller.markerName))
    inst.refresh()
    check("jelölés nélküli skill = kézzel telepített", inst.status[.antigravity] == .foreign)

    // 7) OTS-oldal: DETKapu / TETKapu
    let claudeSkill = SkillInstaller.skillDir(for: .claude).appendingPathComponent("SKILL.md")
    inst.selectedTargets = [.claude]; inst.selectedTasks = ["havi"]; inst.userName = "Teszt Elek"
    check("alapértelmezett OTS-oldal: DETKapu", inst.site == .det && OTSSite.det.url == "https://ots.detkapu.hu/" && OTSSite.tet.url == "https://ots.tetkapu.hu/")
    check("DETKapu telepítése", inst.install(), inst.errorText ?? "")
    let detText = text(claudeSkill)
    check("DETKapu: cím, név és cím a skillben", detText.contains("name: ots-adminisztracio") && detText.contains("# OTS Adminisztráció") && detText.contains("https://ots.detkapu.hu/") && detText.contains("DETKapu") && !detText.contains("tetkapu"))
    check("nincs helyőrző/jelölő (OTS-oldal)", noLeftovers(.claude))
    inst.site = .tet
    check("TETKapu telepítése", inst.install(), inst.errorText ?? "")
    let tetText = text(claudeSkill)
    check("TETKapu: a megfelelő cím mindenütt", tetText.contains("https://ots.tetkapu.hu/") && tetText.contains("TETKapu") && !tetText.contains("detkapu"))
    check("az OTS-oldal megjegyződik a telepítés után", UserDefaults.standard.string(forKey: "skill.site") == "tet")
    check("a fájlokban nincs régi cím", ["references/havi-munkajelento.md", "references/tracker-adatforras.md"].allSatisfy { !text(SkillInstaller.skillDir(for: .claude).appendingPathComponent($0)).contains("detkapu") })
    check("telepített állapot: naprakész az új néven", { inst.refresh(); return inst.status[.claude] == .upToDate }())
    inst.site = .det

    // 8) a korábbi „detkapu-adminisztracio” skill kezelése
    let legacyApp = SkillInstaller.skillsRoot(for: .claude).appendingPathComponent(SkillInstaller.legacySkillName)
    try? fm.createDirectory(at: legacyApp, withIntermediateDirectories: true)
    try? "---\nname: detkapu-adminisztracio\n---\nrégi".write(to: legacyApp.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try? "{}".write(to: legacyApp.appendingPathComponent(SkillInstaller.markerName), atomically: true, encoding: .utf8)
    check("régi, az app által telepített skill lecserélése", inst.install() && !fm.fileExists(atPath: legacyApp.path)
          && (inst.results.first?.notes.joined().contains("lecseréltük") ?? false), "\(inst.results.first?.notes ?? [])")
    let noteText = inst.results.first?.notes.first ?? ""
    check("a régi skillről másolat készült", {
        guard let range = noteText.range(of: "másolat: "), let end = noteText.range(of: ").", range: range.upperBound..<noteText.endIndex) else { return false }
        let path = String(noteText[range.upperBound..<end.lowerBound])
        return fm.fileExists(atPath: path + "/" + SkillInstaller.legacySkillName + "/SKILL.md")
    }())
    try? fm.createDirectory(at: legacyApp, withIntermediateDirectories: true)
    try? "---\nname: detkapu-adminisztracio\n---\nsaját, kézzel telepített".write(to: legacyApp.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    check("kézzel telepített régi skillhez nem nyúl, de jelzi", inst.install() && fm.fileExists(atPath: legacyApp.appendingPathComponent("SKILL.md").path)
          && text(legacyApp.appendingPathComponent("SKILL.md")).contains("saját, kézzel telepített") && (inst.results.first?.notes.joined().contains("nem módosítottuk") ?? false))
    try? fm.removeItem(at: legacyApp)

    // 9) Antigravity CLI: ingyenes jelzés, a régi Gemini-másolat kezelése, az agy felismerése
    check("a Codex és az Antigravity CLI ingyenes, a Claude nem", SkillTarget.antigravity.isFree && SkillTarget.codex.isFree && !SkillTarget.claude.isFree)
    check("nincs többé Gemini CLI cél", SkillTarget.allCases.map { $0.rawValue } == ["claude", "codex", "antigravity"])
    UserDefaults.standard.set(["gemini"], forKey: "skill.targets")
    check("a régi „gemini” választás Antigravity-re vált", SkillInstaller(model: AppModel()).selectedTargets == [.antigravity])
    UserDefaults.standard.removeObject(forKey: "skill.targets")
    let oldGemini = SkillInstaller.homeDir.appendingPathComponent(".gemini/skills/\(SkillInstaller.skillName)")
    try? fm.createDirectory(at: oldGemini, withIntermediateDirectories: true)
    try? "---\nname: ots-adminisztracio\n---\nrégi gemini".write(to: oldGemini.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try? "{}".write(to: oldGemini.appendingPathComponent(SkillInstaller.markerName), atomically: true, encoding: .utf8)
    inst.selectedTargets = [.antigravity]; inst.selectedTasks = ["havi"]; inst.site = .det
    let agyFile = SkillInstaller.agyURL
    try? fm.removeItem(at: agyFile)
    check("agy nélkül: nem telepítettnek látszik", !SkillInstaller.agyInstalled)
    check("Antigravity telepítése", inst.install(), inst.errorText ?? "")
    let agyNotes = inst.results.first?.notes.joined(separator: "\n") ?? ""
    check("jelzi, ha az agy még nincs telepítve, és megadja a parancsot", agyNotes.contains("még nincs telepítve") && agyNotes.contains(SkillInstaller.agyInstallCommand), agyNotes)
    check("a régi, az app által telepített Gemini-másolat eltűnik (másolat marad)", !fm.fileExists(atPath: oldGemini.path) && agyNotes.contains("Gemini CLI magánszemélyeknek megszűnt"))
    try? fm.createDirectory(at: agyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    fm.createFile(atPath: agyFile.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
    check("az agy felismerése a ~/.local/bin/agy alapján", SkillInstaller.agyInstalled)
    check("agy mellett nincs telepítési figyelmeztetés", inst.install() && !(inst.results.first?.notes.joined().contains("még nincs telepítve") ?? true))
    try? fm.createDirectory(at: oldGemini, withIntermediateDirectories: true)
    try? "---\nname: x\n---\nsaját".write(to: oldGemini.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    check("jelölés nélküli Gemini-másolathoz nem nyúl", inst.install() && text(oldGemini.appendingPathComponent("SKILL.md")).contains("saját"))
    try? fm.removeItem(at: oldGemini)
    try? fm.removeItem(at: agyFile)
} else {
    print("(kihagyva: az OTS_SKILL_SOURCE és az OTS_HOME nincs beállítva)")
}

// MARK: 1.5.4: javaslatok gépelés közben, beállítás-fülek, újranyitás

section("Javaslatok gépelés közben")
do {
    let types = ["Istentisztelet", "Ügyintézés", "Értekezlet", "Adminisztráció", "Felkészülés", "Továbbképzés – résztvevő", "Utazás"]
    check("javaslat: ügy → Ügyintézés", Suggest.matches(query: "ügy", candidates: types) == ["Ügyintézés"])
    check("javaslat: ékezet nélkül is (ugy)", Suggest.matches(query: "ugy", candidates: types) == ["Ügyintézés"])
    check("javaslat: nagybetűvel is", Suggest.matches(query: "ÜGYIN", candidates: types) == ["Ügyintézés"])
    check("javaslat: üres szövegre nincs", Suggest.matches(query: "", candidates: types).isEmpty && Suggest.matches(query: "   ", candidates: types).isEmpty)
    check("javaslat: nincs találat", Suggest.matches(query: "xyz", candidates: types).isEmpty)
    check("javaslat: a pontosan egyező nem kerül a listára", Suggest.matches(query: "Utazás", candidates: types).isEmpty && Suggest.matches(query: "utazas", candidates: types).isEmpty)
    check("javaslat: a szó eleje is találat (résztvevő)", Suggest.matches(query: "rész", candidates: types) == ["Továbbképzés – résztvevő"])
    check("javaslat: bárhol benne (inté)", Suggest.matches(query: "min", candidates: types) == ["Adminisztráció"])
    check("javaslat: a szóeleji találat a belsőt megelőzi", Suggest.matches(query: "a", candidates: ["Pálya", "Alma", "Ma a nap"]) == ["Alma", "Ma a nap", "Pálya"], "\(Suggest.matches(query: "a", candidates: ["Pálya", "Alma", "Ma a nap"]))")
    check("javaslat: ismétlődés nélkül, legfeljebb a megadott darab", Suggest.matches(query: "t", candidates: ["Tata", "tata", "Tatabánya", "Tát", "Tab", "Tag", "Tan"], limit: 3).count == 3 && Set(Suggest.matches(query: "ta", candidates: ["Tata", "tata", "TATA ", "Tatabánya"]).map { Suggest.norm($0) }).count == Suggest.matches(query: "ta", candidates: ["Tata", "tata", "TATA ", "Tatabánya"]).count)
    // listás mező
    check("lista: az utolsó elválasztó utáni rész", Suggest.split("Tata, Mó").segment == "Mó" && Suggest.split("Tata, Mó").prefix == "Tata," && Suggest.split("Tata").segment == "Tata" && Suggest.split("Tata").prefix == "")
    check("lista: ` - ` és `;` is elválaszt", Suggest.split("Tata - Mó").segment == "Mó" && Suggest.split("Tata; Mó").segment == "Mó")
    check("lista: beillesztés az éppen írt rész helyére", Suggest.apply("Mór", to: "Tata, Mó", list: true) == "Tata, Mór" && Suggest.apply("Tata", to: "Ta", list: true) == "Tata" && Suggest.apply("Mór", to: "Tata - Mó", list: true) == "Tata - Mór")
    check("lista: egyszerű mezőnél a teljes szöveg cserélődik", Suggest.apply("Ügyintézés", to: "ügy", list: false) == "Ügyintézés")
    let places = ["Tata", "Tatabánya", "Mór", "Győr"]
    check("lista: a Cél éppen írt részére javasol", Suggest.suggestions(text: "Tata, Mó", candidates: places, list: true) == ["Mór"])
    check("lista: a már megadott helyet nem javasolja újra", Suggest.suggestions(text: "Tata, Ta", candidates: places, list: true) == ["Tatabánya"])
    check("lista: cím (utca, házszám) írása közben nincs javaslat", Suggest.suggestions(text: "Tata, Fő út 1", candidates: places, list: true).isEmpty && Suggest.suggestions(text: "Tata, Kossuth u.", candidates: places, list: true).isEmpty)
    check("lista: vessző után még üres rész: nincs javaslat", Suggest.suggestions(text: "Tata, ", candidates: places, list: true).isEmpty)
    // korábbi tevékenységek
    let sdir = tmp + "/suggest"
    try? FileManager.default.removeItem(atPath: sdir)
    UserDefaults.standard.set(sdir + "/bejegyzesek.csv", forKey: "dataFile")
    let sm = AppModel()
    func ent(_ type: ActivityType, _ act: String, _ day: String) -> Entry {
        Entry(id: UUID(), date: day, start: nil, end: nil, durationSeconds: 3600, workplace: "Győr", type: type.code, typeLabel: type.label, unit: type.unit.rawValue, quantity: nil, activity: act, source: "manual")
    }
    sm.add(ent(.meeting, "Heti megbeszélés", "2026-10-01"))
    sm.add(ent(.preparing, "Prédikáció", "2026-10-02"))
    sm.add(ent(.meeting, "Munkatársi értekezlet", "2026-10-03"))
    sm.add(ent(.meeting, "heti megbeszélés", "2026-10-04"))
    sm.add(ent(.preparing, "", "2026-10-05"))
    sm.selectedType = .meeting
    check("tevékenység-javaslat: a legutóbbi elöl, az azonos típusúak előbb, ismétlődés és üres nélkül", sm.activitySuggestions() == ["heti megbeszélés", "Munkatársi értekezlet", "Prédikáció"], "\(sm.activitySuggestions())")
    sm.selectedType = .preparing
    check("tevékenység-javaslat: típusváltásra más a sorrend", sm.activitySuggestions().first == "Prédikáció", "\(sm.activitySuggestions())")
    sm.selectedType = nil
    check("tevékenység-javaslat: a Munkahely mezőé a mentett helyszínek", sm.workplaceSuggestions == sm.places)
    UserDefaults.standard.set(tmp + "/data/bejegyzesek.csv", forKey: "dataFile")
}

section("Beállítás-fülek és újranyitás")
do {
    check("öt kategória, mind más azonosítóval, ikonnal és névvel", SettingsTab.allCases.count == 5 && Set(SettingsTab.allCases.map { $0.rawValue }).count == 5 && SettingsTab.allCases.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty && !$0.help.isEmpty })
    let ud = UserDefaults.standard
    let um = AppModel()
    let host = NSHostingController(rootView: SettingsView().environmentObject(um).environment(\.palette, .blue).frame(width: 440))
    host.sizingOptions = []
    let win = NSWindow(contentViewController: host)
    win.setContentSize(NSSize(width: 470, height: 900))
    win.makeKeyAndOrderFront(nil)
    for tab in SettingsTab.allCases {
        ud.set(tab.rawValue, forKey: "settings.tab")
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    ud.set("ismeretlen", forKey: "settings.tab")
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    check("minden kategória és az ismeretlen érték is összeomlás nélkül kirajzolódik", true)
    ud.removeObject(forKey: "settings.tab")
    win.orderOut(nil)
    let all = NSHostingController(rootView: SettingsView(showAllTabs: true).environmentObject(um).environment(\.palette, .blue).frame(width: 440))
    all.sizingOptions = []
    let w2 = NSWindow(contentViewController: all)
    w2.setContentSize(NSSize(width: 470, height: 900)); w2.makeKeyAndOrderFront(nil)
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    check("az összes kategória egyben is kirajzolódik (útmutató-képekhez)", true)
    w2.orderOut(nil)

    // a menüsori ablak bezárásakor számlálót léptet (a nézet ebből tudja, hogy a rögzítő oldalt kell mutatnia)
    let pc = PanelController.shared
    let menuWin = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
    pc.menuWindow = menuWin
    let before = pc.menuHiddenCount
    menuWin.makeKeyAndOrderFront(nil)
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    check("megnyitáskor a számláló nem változik", pc.menuHiddenCount == before)
    menuWin.orderOut(nil)
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    check("bezáráskor a számláló növekszik", pc.menuHiddenCount == before + 1, "\(pc.menuHiddenCount) / \(before)")
    pc.menuWindow = nil
}

section("Javaslatlista: kattintás és kinézet")
do {
    final class Box: ObservableObject { @Published var text = "ügy"; @Published var picked: String? }
    struct Harness: View {
        @ObservedObject var box: Box
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                SuggestTextField(prompt: "Tevékenység", text: $box.text, candidates: { ["Ügyintézés", "Ügyfélszolgálat", "Értekezlet"] }, forceOpen: true)
                Text("Ez a mező alatti szöveg").font(.caption)
                Button("Egy alatta lévő gomb") {}
                Spacer()
            }
            .padding(20).frame(width: 320, height: 220, alignment: .topLeading)
            .environment(\.palette, .blue)
        }
    }
    UserDefaults.standard.removeObject(forKey: "suggest.enabled")
    let box = Box()
    let h = NSHostingController(rootView: Harness(box: box))
    h.sizingOptions = []
    let w = NSWindow(contentViewController: h)
    w.appearance = NSAppearance(named: .aqua); w.backgroundColor = .white
    w.setContentSize(NSSize(width: 320, height: 220))
    w.makeKeyAndOrderFront(nil)
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    if let dir = ProcessInfo.processInfo.environment["OTS_RENDER_DIR"], let cv = w.contentView, let rep = cv.bitmapImageRepForCachingDisplay(in: cv.bounds) {
        cv.cacheDisplay(in: cv.bounds, to: rep)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/javaslat.png"))
    }
    // kattintás az első javaslatra (a mező alatt, a mező területén kívül): ablak-koordinátában, bal alsó origóval
    func click(at topLeft: NSPoint) {
        let p = NSPoint(x: topLeft.x, y: 220 - topLeft.y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let ev = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                w.sendEvent(ev)
            }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }
    // a mező kb. y 20–42, az első javaslat sora kb. y 46–66
    click(at: NSPoint(x: 60, y: 57))
    check("a javaslatlistára (a mező területén kívül) lehet kattintani: elfogadja a javaslatot", box.text == "Ügyintézés", "\(box.text)")
    w.orderOut(nil)
}

do {
    // szemrevételezéshez (képpé renderelve, ha az OTS_RENDER_DIR meg van adva): fülsor, egy kategória, a típusmező
    if let dir = ProcessInfo.processInfo.environment["OTS_RENDER_DIR"] {
        let ud = UserDefaults.standard
        ud.set(tmp + "/vis/bejegyzesek.csv", forKey: "dataFile")
        let vm = AppModel()
        func shot(_ view: AnyView, _ size: NSSize, _ name: String) {
            let h = NSHostingController(rootView: view)
            h.sizingOptions = []
            let w = NSWindow(contentViewController: h)
            w.appearance = NSAppearance(named: .aqua); w.backgroundColor = .white
            w.setContentSize(size); w.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            if let cv = w.contentView, let rep = cv.bitmapImageRepForCachingDisplay(in: cv.bounds) {
                cv.cacheDisplay(in: cv.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/" + name + ".png"))
            }
            w.orderOut(nil)
        }
        ud.set("recording", forKey: "settings.tab")
        shot(AnyView(VStack(spacing: 8) { SettingsTabBar(); SettingsView() }.padding(14).frame(width: 440, alignment: .top).environmentObject(vm).environment(\.palette, .blue)), NSSize(width: 470, height: 900), "beallitasok-rogzites")
        ud.set("data", forKey: "settings.tab")
        shot(AnyView(VStack(spacing: 8) { SettingsTabBar(); SettingsView() }.padding(8).frame(width: 340, alignment: .top).environmentObject(vm).environment(\.palette, .green).environment(\.compact, true)), NSSize(width: 360, height: 500), "beallitasok-kompakt")
        ud.removeObject(forKey: "settings.tab")
        vm.selectedType = .meeting; vm.workplace = "Győr"
        shot(AnyView(FieldsView().environmentObject(vm).environment(\.palette, .blue).frame(width: 440).padding(14)), NSSize(width: 470, height: 200), "urlap-tipusmezo")
        ud.set(tmp + "/data/bejegyzesek.csv", forKey: "dataFile")
    }
}

section("Tevékenység típusa: javaslat elfogadása")
do {
    // Hiba (1.5.4): a javaslat elfogadása után (Enter, Tab vagy kattintás) a mező üresnek látszott, mert a fókusz a mezőben maradt,
    // és a kiválasztott típus neve csak fókusz nélkül volt kirajzolva.
    UserDefaults.standard.removeObject(forKey: "suggest.enabled")
    let tdir = tmp + "/typefield"
    try? FileManager.default.removeItem(atPath: tdir)
    UserDefaults.standard.set(tdir + "/bejegyzesek.csv", forKey: "dataFile")
    let tm = AppModel()
    tm.selectedType = nil
    struct TypeHarness: View {
        @ObservedObject var m: AppModel
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                TypeSuggestField(initialQuery: "ügy", forceOpen: true).environmentObject(m)
                Text("alatta").font(.caption)
                Spacer()
            }
            .padding(20).frame(width: 320, height: 220, alignment: .topLeading)
            .environment(\.palette, .blue)
        }
    }
    let h = NSHostingController(rootView: TypeHarness(m: tm))
    h.sizingOptions = []
    let w = NSWindow(contentViewController: h)
    w.appearance = NSAppearance(named: .aqua); w.backgroundColor = .white
    w.setContentSize(NSSize(width: 320, height: 220))
    w.makeKeyAndOrderFront(nil)
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    func textFields(_ v: NSView) -> [NSTextField] { (v as? NSTextField).map { [$0] } ?? [] + v.subviews.flatMap { textFields($0) } }
    func allTextFields(_ v: NSView) -> [NSTextField] { var out: [NSTextField] = []; if let t = v as? NSTextField { out.append(t) }; for s in v.subviews { out += allTextFields(s) }; return out }
    let field = allTextFields(w.contentView ?? NSView()).first { $0.isEditable }
    check("a típusmező szövegmezője megtalálható", field != nil)
    if let field = field {
        w.makeFirstResponder(field)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        check("a mező fókuszban van (a hiba itt jelentkezett)", field.currentEditor() != nil)
        func click(_ topLeft: NSPoint) {
            let p = NSPoint(x: topLeft.x, y: 220 - topLeft.y)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let ev = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { w.sendEvent(ev) }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        // az első javaslat (Ügyintézés) a mező alatt: kb. y 46–66
        click(NSPoint(x: 60, y: 57))
        check("a kattintásra a típus beállt", tm.selectedType == .officeWork, "\(String(describing: tm.selectedType))")
        check("elfogadás után a mező elengedi a fókuszt", field.currentEditor() == nil)
    }
    w.orderOut(nil)
    UserDefaults.standard.set(tmp + "/data/bejegyzesek.csv", forKey: "dataFile")
}

// MARK: Hétvégi napok, Szabadnap egy kattintással, havi korlát

section("Hétvége: jelzés és Szabadnap")
do {
    func e(_ type: ActivityType, _ day: String, secs: Int = 0, q: Int? = nil) -> Entry {
        Entry(id: UUID(), date: day, start: nil, end: nil, durationSeconds: secs, workplace: type.isWholeDay ? type.shortLabel.uppercased() : "Győr", type: type.code, typeLabel: type.label, unit: type.unit.rawValue, quantity: q, activity: "", source: "manual")
    }
    // 2024–2035, minden negyedév minden hétvégéje
    var weekendDays = 0
    for year in 2024...2035 {
        for q in 1...4 {
            for sat in DateUtil.saturdays(year: year, quarter: q) {
                let sun = DateUtil.addDays(sat, 1)
                let later = DateUtil.addDays(sat, 3)   // „ma”: a hétvége után
                let tag = "\(year)/Q\(q) \(ymd(sat))"
                let sKey = ymd(sat), uKey = ymd(sun)
                let ok = Insights.targetState(day: sat, entries: [], today: later, targetHours: 8) == .short
                    && Insights.targetState(day: sun, entries: [], today: later, targetHours: 8) == .short
                    && Insights.targetState(day: sat, entries: [e(.preaching, sKey, q: 1)], today: later, targetHours: 8) == .exempt
                    && Insights.targetState(day: sun, entries: [e(.meeting, uKey, secs: 900)], today: later, targetHours: 8) == .exempt
                    && Insights.targetState(day: sun, entries: [e(.dayOff, uKey)], today: later, targetHours: 8) == .exempt
                    && Insights.targetState(day: sat, entries: [], today: sat, targetHours: 8) == .inProgress
                    && Insights.targetState(day: sun, entries: [], today: sat, targetHours: 8) == .exempt
                if !ok { check("hétvége \(tag)", false) }
                weekendDays += 1
            }
        }
    }
    check("hétvégi jelzés 2024–2035 minden negyedév minden hétvégéjén (\(weekendDays) hétvége)", weekendDays > 600)
    // a hétköznapi szabály változatlan
    check("hétköznapon továbbra is a napi óraszám számít", Insights.targetState(day: d(2026, 10, 5), entries: [e(.meeting, "2026-10-05", secs: 3 * 3600)], today: d(2026, 10, 14), targetHours: 8) == .short && Insights.targetState(day: d(2026, 10, 5), entries: [e(.meeting, "2026-10-05", secs: 8 * 3600)], today: d(2026, 10, 14), targetHours: 8) == .reached)
    // a hónap heteinek száma (a havi korlát): 28 nap = 4, 29–31 nap = 5
    var weeksOK = true
    for year in 2024...2035 {
        for month in 1...12 {
            let days = [1, 3, 5, 7, 8, 10, 12].contains(month) ? 31 : ([4, 6, 9, 11].contains(month) ? 30 : (DateUtil.date(year: year, month: 2, day: 29) != nil ? 29 : 28))
            let expected = days == 28 ? 4 : 5
            if Insights.weeksInMonth(year: year, month: month) != expected { weeksOK = false; check("hetek száma \(year)-\(month)", false, "\(Insights.weeksInMonth(year: year, month: month)) / \(expected)") }
        }
    }
    check("a hónap heteinek száma 2024–2035 minden hónapra (szökőév is)", weeksOK)
    check("érvénytelen hónapra sem omlik össze", Insights.weeksInMonth(year: 2026, month: 13) >= 4 && Insights.weeksInMonth(year: 0, month: 0) >= 4)

    // Szabadnap egy kattintással
    let sdir = tmp + "/dayoff"
    try? FileManager.default.removeItem(atPath: sdir)
    UserDefaults.standard.set(sdir + "/bejegyzesek.csv", forKey: "dataFile")
    UserDefaults.standard.removeObject(forKey: "missing.lookback")
    let dm = AppModel()
    let sunday = d(2025, 10, 5)   // vasárnap, múltbeli
    check("a kiválasztott nap vasárnap", DateUtil.isSunday(sunday))
    check("üres napot Szabadnapnak lehet jelölni", dm.markDayOff(sunday))
    let off = dm.entries.first { $0.date == "2025-10-05" }
    check("a bejegyzés egész napos Szabadnap, a Munkahely SZABADNAP", off?.type == ActivityType.dayOff.code && off?.unit == Unit.wholeDay.rawValue && off?.workplace == "SZABADNAP" && off?.source == "manual" && off?.durationSeconds == 0)
    check("a jelölés után a nap kitöltöttnek számít", Insights.targetState(day: sunday, entries: dm.entries(on: sunday), today: d(2025, 10, 8), targetHours: 8) == .exempt && !dm.missingDays(lookback: "365").contains { ymd($0) == "2025-10-05" })
    dm.lastError = nil
    check("kétszer nem jelöli ugyanazt a napot", !dm.markDayOff(sunday) && dm.entries.filter { $0.date == "2025-10-05" }.count == 1)
    dm.lastError = nil
    dm.add(e(.meeting, "2025-10-06", secs: 3600))
    check("olyan napot, amelyen van bejegyzés, nem jelöl", !dm.markDayOff(d(2025, 10, 6)) && dm.entries.filter { $0.date == "2025-10-06" }.count == 1)
    dm.lastError = nil
    check("jövőbeli napot nem jelöl", !dm.markDayOff(DateUtil.addDays(Date(), 5)) && dm.lastError != nil)
    dm.lastError = nil
    check("a Szabadnap CSV-oda-vissza megmarad", (try? CSV.decode(CSV.encode(dm.entries)).entries.contains { $0.type == ActivityType.dayOff.code && $0.date == "2025-10-05" }) == true)

    // az összes üres vasárnap egyszerre
    let before = dm.entries.count
    let expectedSundays = dm.missingDays(lookback: "30").filter { DateUtil.isSunday($0) }
    let marked = dm.markEmptySundaysAsDayOff(lookback: "30")
    check("az üres vasárnapokat mind megjelöli (és csak azokat)", marked == expectedSundays.count && dm.entries.count == before + marked && expectedSundays.allSatisfy { dm.entries(on: $0).contains { $0.type == ActivityType.dayOff.code } }, "\(marked) / \(expectedSundays.count)")
    check("a tömeges jelölés után nincs üres vasárnap a tartományban", dm.missingDays(lookback: "30").filter { DateUtil.isSunday($0) }.isEmpty)
    check("a tömeges jelölés után tájékoztató üzenet van (ha jelölt valamit)", marked == 0 || (dm.notice ?? "").contains("szabadnapnak jelölve"), dm.notice ?? "-")
    check("egy nem vasárnapi üres nap érintetlen", dm.missingDays(lookback: "30").allSatisfy { !DateUtil.isSunday($0) })

    // a havi korlát: legfeljebb annyi SZABADNAP, ahány hét van a hónapban (2025. október: 31 nap = 5)
    let ldir = tmp + "/dayofflimit"
    try? FileManager.default.removeItem(atPath: ldir)
    UserDefaults.standard.set(ldir + "/bejegyzesek.csv", forKey: "dataFile")
    let lm = AppModel()
    for day in 1...5 { lm.markDayOff(d(2025, 10, day)) }
    check("5 szabadnap egy 31 napos hónapban még rendben (nincs figyelmeztetés)", lm.notice == nil, lm.notice ?? "-")
    lm.markDayOff(d(2025, 10, 6))
    check("a hatodik szabadnapnál figyelmeztet a havi korlátra", (lm.notice ?? "").hasPrefix("Figyelem") && (lm.notice ?? "").contains("szabadnap") && (lm.notice ?? "").contains("5"), lm.notice ?? "-")
    check("a figyelmeztetés nem akadályozza a rögzítést", lm.entries.filter { $0.type == ActivityType.dayOff.code }.count == 6)
    lm.showNotice(nil)
    // a munkaszüneti nap külön korlát
    for day in 7...11 { lm.add(AppModel.wholeDayEntry(day: d(2025, 10, day), type: .publicHoliday, activity: "")) }
    check("5 szabadnap után 5 munkaszüneti nap külön korlát: 5 még rendben", lm.notice == nil, lm.notice ?? "-")
    lm.add(AppModel.wholeDayEntry(day: d(2025, 10, 12), type: .publicHoliday, activity: ""))
    check("a hatodik munkaszüneti napnál is figyelmeztet", (lm.notice ?? "").contains("munkaszüneti nap"), lm.notice ?? "-")
    // 28 napos február: legfeljebb 4
    let fm28 = AppModel()
    lm.showNotice(nil)
    for day in 3...6 { lm.markDayOff(d(2025, 2, day)) }
    check("február (28 nap): 4 szabadnap rendben", lm.notice == nil && lm.entries.filter { $0.type == ActivityType.dayOff.code && $0.date.hasPrefix("2025-02-") }.count == 4, lm.notice ?? "-")
    lm.markDayOff(d(2025, 2, 7))
    check("február (28 nap): az 5. szabadnapnál figyelmeztet", (lm.notice ?? "").hasPrefix("Figyelem"), lm.notice ?? "-")
    _ = fm28
    // a figyelmeztetés eltűnik, ha törlik
    lm.showNotice(nil)
    check("a notice törölhető", lm.notice == nil)
    UserDefaults.standard.set(tmp + "/data/bejegyzesek.csv", forKey: "dataFile")
}

do {
    // szemrevételezéshez: a kitöltetlen napok sora az új Szabadnap-gombokkal (képpé renderelve, ha az OTS_RENDER_DIR meg van adva)
    if let dir = ProcessInfo.processInfo.environment["OTS_RENDER_DIR"] {
        let ud = UserDefaults.standard
        ud.set(tmp + "/vis2/bejegyzesek.csv", forKey: "dataFile")
        ud.set("30", forKey: "missing.lookback")
        let vm = AppModel()
        // néhány nap bejegyzéssel, a többi üres (köztük vasárnapok)
        for back in [3, 6, 10] {
            let day = DateUtil.addDays(Date(), -back)
            vm.add(Entry(id: UUID(), date: ymd(day), start: nil, end: nil, durationSeconds: 3600, workplace: "Győr", type: ActivityType.meeting.code, typeLabel: "Értekezlet", unit: "ora", quantity: nil, activity: "x", source: "manual"))
        }
        vm.notice = "3 vasárnap szabadnapnak jelölve."
        for (name, compactMode, width) in [("kitoltetlen-napok", false, 440), ("kitoltetlen-napok-kompakt", true, 340)] {
            let h = NSHostingController(rootView: VStack(alignment: .leading, spacing: 8) {
                MissingDaysView()
                if let n = vm.notice { Text(n).font(.caption).foregroundStyle(Theme.warn) }
            }.environmentObject(vm).environment(\.palette, .blue).environment(\.compact, compactMode).frame(width: CGFloat(width)).padding(12))
            h.sizingOptions = []
            let w = NSWindow(contentViewController: h)
            w.appearance = NSAppearance(named: .aqua); w.backgroundColor = .white
            w.setContentSize(NSSize(width: width + 24, height: 130)); w.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            if let cv = w.contentView, let rep = cv.bitmapImageRepForCachingDisplay(in: cv.bounds) {
                cv.cacheDisplay(in: cv.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/" + name + ".png"))
            }
            w.orderOut(nil)
        }
        ud.removeObject(forKey: "missing.lookback")
        ud.set(tmp + "/data/bejegyzesek.csv", forKey: "dataFile")
    }
}

// MARK: Menüsori számláló: állandó szélesség

section("Menüsori számláló")
do {
    let icons: [(String, IconChoice)] = [("jelkép", IconSets.main[5]), ("szimbólum", IconSets.main[0]), ("paradicsom (emoji)", IconSets.pomoWork[0]), ("kávé (emoji)", IconSets.pomoBreak[1]), ("csésze (szimbólum)", IconSets.pomoBreak[0]), ("figyelmeztetés", IconSets.reminder[0])]
    let samples = ["00:00", "01:11", "08:08", "11:11", "12:34", "25:00", "47:58", "58:59", "59:59", "99:99"]
    for (name, ic) in icons {
        let sizes = Set(samples.map { MenuBarClock.make(icon: ic, text: $0, textColor: .black).size })
        check("\(name): a kép mérete minden számjegyre azonos (óó:pp)", sizes.count == 1, "\(sizes)")
        let longSizes = Set(["1:00:00", "1:11:11", "2:08:08", "9:59:59"].map { MenuBarClock.make(icon: ic, text: $0, textColor: .black).size })
        check("\(name): a h:mm:ss alakok mérete azonos", longSizes.count == 1)
        check("\(name): a hosszabb alak szélesebb (egyszer vált, egy óra után)", MenuBarClock.make(icon: ic, text: "1:00:00", textColor: .black).size.width > MenuBarClock.make(icon: ic, text: "59:59", textColor: .black).size.width)
    }
    check("jelkép és szimbólumok: sablonkép (a rendszer a menüsor színére festi)", [0, 1, 4, 5].allSatisfy { MenuBarClock.make(icon: icons[$0].1, text: "12:34", textColor: .black).isTemplate })
    check("emoji ikon (Pomodoro): színes kép, nem sablon", [2, 3].allSatisfy { !MenuBarClock.make(icon: icons[$0].1, text: "12:34", textColor: .black).isTemplate })
    check("a kép magassága a menüsori ikoné", MenuBarClock.make(icon: icons[0].1, text: "12:34", textColor: .black).size.height == MenuBarClock.height)

    // képpont-ellenőrzés: a számláló jelei (az ikon után) minden számra ugyanazon a helyen állnak
    func inkClusters(_ img: NSImage) -> [ClosedRange<Int>] {
        let scale = 4
        let w = Int(img.size.width) * scale, h = Int(img.size.height) * scale
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return [] }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
        img.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        var inkCols: [Bool] = []
        for x in 0..<w {
            var ink = false
            for y in 0..<h where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.3 { ink = true; break }
            inkCols.append(ink)
        }
        var out: [ClosedRange<Int>] = []
        var start: Int?
        for (i, c) in inkCols.enumerated() {
            if c, start == nil { start = i }
            if !c, let s0 = start { out.append(s0...(i - 1)); start = nil }
        }
        if let s0 = start { out.append(s0...(inkCols.count - 1)) }
        return out
    }
    for (name, ic) in icons {
        let a = inkClusters(MenuBarClock.make(icon: ic, text: "11:11", textColor: .black))
        let b2 = inkClusters(MenuBarClock.make(icon: ic, text: "00:00", textColor: .black))
        let c = inkClusters(MenuBarClock.make(icon: ic, text: "47:58", textColor: .black))
        let tail = { (x: [ClosedRange<Int>]) in Array(x.suffix(5)) }
        check("\(name): a számláló öt jele (négy számjegy, kettőspont) látszik", tail(a).count == 5 && tail(b2).count == 5 && tail(c).count == 5)
        if tail(a).count == 5, tail(b2).count == 5, tail(c).count == 5 {
            func center(_ r: ClosedRange<Int>) -> Double { Double(r.lowerBound + r.upperBound) / 2 }
            check("\(name): a kettőspont helye minden számra azonos", abs(center(tail(a)[2]) - center(tail(b2)[2])) <= 1 && abs(center(tail(a)[2]) - center(tail(c)[2])) <= 1, "\(center(tail(a)[2])) \(center(tail(b2)[2])) \(center(tail(c)[2]))")
            check("\(name): az utolsó számjegy cellája minden számra azonos (nem ugrik)", abs(center(tail(a)[4]) - center(tail(b2)[4])) <= 6 && abs(center(tail(a)[4]) - center(tail(c)[4])) <= 6)
        }
    }
    check("az idő helyőrzője/értelmezése: a menüsori szöveg órája", AppModel().menuClockText == nil)
    if let dir = ProcessInfo.processInfo.environment["OTS_RENDER_DIR"] {
        // szemrevételezéshez: minden ikonfajta, többféle idő, 4x nagyításban, világos és sötét háttéren
        let rows = icons.flatMap { ic in ["00:00", "47:58", "1:08:47"].map { (ic.1, $0) } }
        let scale: CGFloat = 4
        let wmax = rows.map { MenuBarClock.make(icon: $0.0, text: $0.1, textColor: .black).size.width }.max() ?? 40
        for dark in [false, true] {
            let hh = MenuBarClock.height * CGFloat(rows.count)
            if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((wmax + 8) * scale), pixelsHigh: Int((hh + 8) * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
               let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
                (dark ? NSColor(white: 0.12, alpha: 1) : NSColor.white).setFill(); NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh).fill()
                for (i, r) in rows.enumerated() {
                    let img = MenuBarClock.make(icon: r.0, text: r.1, textColor: dark ? .white : .black)
                    let rect = NSRect(x: 4 * scale, y: (4 + MenuBarClock.height * CGFloat(rows.count - 1 - i)) * scale, width: img.size.width * scale, height: img.size.height * scale)
                    if img.isTemplate && dark {
                        // sablonkép sötét menüsoron: fehérre festve
                        let t = img.copy() as? NSImage ?? img
                        t.lockFocus(); NSColor.white.set(); NSRect(origin: .zero, size: t.size).fill(using: .sourceAtop); t.unlockFocus()
                        t.draw(in: rect)
                    } else { img.draw(in: rect) }
                }
                NSGraphicsContext.restoreGraphicsState()
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + (dark ? "/menusori-szamlalo-sotet.png" : "/menusori-szamlalo.png")))
            }
        }
    }
}

// MARK: Skill: elavult telepítés jelzése és egykattintásos frissítés

section("Skill: frissítés")
if ProcessInfo.processInfo.environment["OTS_SKILL_SOURCE"] != nil, ProcessInfo.processInfo.environment["OTS_HOME"] != nil {
    let fm = FileManager.default
    let homeRoot = ProcessInfo.processInfo.environment["OTS_HOME"] ?? ""
    try? fm.removeItem(atPath: homeRoot)
    try? fm.createDirectory(atPath: homeRoot, withIntermediateDirectories: true)
    let ud = UserDefaults.standard
    let um = AppModel()

    func marker(_ t: SkillTarget) -> URL { SkillInstaller.skillDir(for: t).appendingPathComponent(SkillInstaller.markerName) }
    func readMarker(_ t: SkillTarget) -> [String: Any]? {
        (try? Data(contentsOf: marker(t))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
    func writeMarker(_ t: SkillTarget, _ obj: [String: Any]) {
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: marker(t), options: .atomic) }
    }

    // nincs telepítés: nincs mit frissíteni
    um.refreshSkillUpdate()
    check("telepítés nélkül nincs frissítés-jelzés", !um.skillUpdateAvailable)
    check("telepítés nélkül a frissítés nem csinál semmit", SkillInstaller(model: um).updateOutdated() == SkillInstaller.UpdateOutcome())

    // telepítés a varázslóval: Claude + Codex, két feladat, TETKapu
    let inst = SkillInstaller(model: um)
    inst.selectedTasks = ["havi", "koltseg"]
    inst.selectedTargets = [.claude, .codex]
    inst.userName = "Teszt Elek"; inst.home = "Győr"; inst.congregations = ""; inst.site = .tet
    check("kiinduló telepítés", inst.install(), inst.errorText ?? "")
    inst.refresh()
    check("friss telepítés naprakész", inst.status[.claude] == .upToDate && inst.status[.codex] == .upToDate)
    um.refreshSkillUpdate()
    check("naprakész skillnél nincs jelzés", !um.skillUpdateAvailable)
    check("naprakész skillnél a frissítés nem nyúl semmihez", SkillInstaller(model: um).updateOutdated() == SkillInstaller.UpdateOutcome())

    // a felhasználó közben mást állított a varázslóban: a frissítés nem írhatja át
    ud.set(["claude"], forKey: "skill.targets")
    ud.set("Más Név", forKey: "skill.userName")

    // „a skillben frissítettem valamit”: a telepítés jelölésében régi lenyomat
    for t in [SkillTarget.claude, .codex] {
        if var obj = readMarker(t) { obj["fingerprint"] = "00000000"; writeMarker(t, obj) }
    }
    // a telepített fájl tartalma: jelöljük, hogy a frissítés lecseréli
    let claudeSkillMd = SkillInstaller.skillDir(for: .claude).appendingPathComponent("SKILL.md")
    try? "RÉGI TARTALOM".write(to: claudeSkillMd, atomically: true, encoding: .utf8)
    um.refreshSkillUpdate()
    check("elavult skillnél jelzés van", um.skillUpdateAvailable)

    let msg = um.updateSkill()
    check("a frissítés üzenete a célokat nevezi meg", msg.contains("Frissítve") && msg.contains("Claude") && msg.contains("Codex"), msg)
    check("frissítés után nincs jelzés, naprakész", !um.skillUpdateAvailable && um.skillUpdateMessage == msg)
    let after = (try? String(contentsOf: claudeSkillMd, encoding: .utf8)) ?? ""
    check("a SKILL.md újra a csomagolt tartalom, a korábbi beállításokkal", !after.contains("RÉGI TARTALOM") && after.contains("Teszt Elek") && after.contains("ots.tetkapu.hu"), String(after.prefix(80)))
    check("a korábban kiválasztott feladatok maradtak (a többi nem került be)", fm.fileExists(atPath: SkillInstaller.skillDir(for: .claude).appendingPathComponent("references/havi-munkajelento.md").path) && !fm.fileExists(atPath: SkillInstaller.skillDir(for: .claude).appendingPathComponent("references/hitoktatas.md").path))
    let inst2 = SkillInstaller(model: um)
    check("mindkét mappa naprakész", inst2.status[.claude] == .upToDate && inst2.status[.codex] == .upToDate && (readMarker(.claude)?["fingerprint"] as? String) == inst2.bundledFingerprint())
    check("a régi telepítésről másolat készült", (try? fm.contentsOfDirectory(atPath: SkillInstaller.backupRoot.path))?.isEmpty == false)
    check("a varázsló mentett beállításait a frissítés nem írta át", ud.stringArray(forKey: "skill.targets") == ["claude"] && ud.string(forKey: "skill.userName") == "Más Név")

    // csak az egyik mappa elavult
    if var obj = readMarker(.codex) { obj["fingerprint"] = "11111111"; writeMarker(.codex, obj) }
    let codexMd = SkillInstaller.skillDir(for: .codex).appendingPathComponent("SKILL.md")
    try? "RÉGI CODEX".write(to: codexMd, atomically: true, encoding: .utf8)
    let claudeBefore = (try? String(contentsOf: claudeSkillMd, encoding: .utf8)) ?? ""
    let o2 = SkillInstaller(model: um).updateOutdated()
    check("csak az elavult mappa frissül", o2.didUpdate && o2.updated.contains(.codex) && !o2.updated.contains(.claude) && o2.problems.isEmpty, "\(o2)")
    check("a naprakész mappához nem nyúlt", ((try? String(contentsOf: claudeSkillMd, encoding: .utf8)) ?? "") == claudeBefore)
    check("a Codex-mappa tartalma frissült", !((try? String(contentsOf: codexMd, encoding: .utf8)) ?? "").contains("RÉGI CODEX"))

    // hiányos jelölés: nem találgat, a varázslót ajánlja
    if var obj = readMarker(.claude) { obj["fingerprint"] = "22222222"; obj.removeValue(forKey: "values"); writeMarker(.claude, obj) }
    let o3 = SkillInstaller(model: um).updateOutdated()
    check("hiányos jelölésnél nincs frissítés, a varázsló ajánlott", !o3.didUpdate && o3.problems.count == 1 && o3.problems[0].contains("varázsl"), "\(o3)")
    // kézzel telepített (jelölés nélkül): nem bántja
    try? fm.removeItem(at: marker(.claude))
    try? "KÉZI".write(to: claudeSkillMd, atomically: true, encoding: .utf8)
    let o4 = SkillInstaller(model: um).updateOutdated()
    check("kézzel telepített skillhez nem nyúl", o4 == SkillInstaller.UpdateOutcome() && ((try? String(contentsOf: claudeSkillMd, encoding: .utf8)) ?? "") == "KÉZI")
    um.refreshSkillUpdate()
    check("a kézi skill nem ad frissítés-jelzést", !um.skillUpdateAvailable)
    for k in ["skill.targets", "skill.userName", "skill.notifiedFingerprint"] { ud.removeObject(forKey: k) }
    try? fm.removeItem(atPath: homeRoot)
    try? fm.createDirectory(atPath: homeRoot, withIntermediateDirectories: true)
} else {
    check("skill-frissítés tesztjei kihagyva (nincs OTS_HOME / OTS_SKILL_SOURCE)", true)
}

// MARK: Naptárintegráció: értelmező (1.4.0)

section("Naptár-értelmező")
func at(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    cal.date(bySettingHour: h, minute: min, second: 0, of: d(y, m, day)) ?? d(y, m, day)
}
let farNow = d(2037, 1, 1)
func ev(_ title: String, loc: String = "", notes: String = "", _ s: Date, _ e: Date, allDay: Bool = false, id: String = "E1") -> CalendarEventInput {
    CalendarEventInput(id: id, title: title, location: loc, notes: notes, start: s, end: e, isAllDay: allDay)
}
func parsed(_ e: CalendarEventInput, now: Date = farNow, home: String = "Győr") -> CalendarOutcome { CalendarParser.parse(e, now: now, home: home) }
func drafts(_ o: CalendarOutcome) -> [CalendarDraft] {
    switch o {
    case .imported(let d): return d
    case .incomplete(_, let d, _): return d
    default: return []
    }
}
func problems(_ o: CalendarOutcome) -> [CalendarProblem] { if case .incomplete(_, _, let p) = o { return p }; return [] }
func one(_ o: CalendarOutcome) -> CalendarDraft? { if case .imported(let d) = o, d.count == 1 { return d[0] }; return nil }

// típusnevek
let typeCases: [(String, ActivityType)] = [
    ("Istentisztelet", .preaching), ("Látogatás", .visiting), ("Missziós látogatás", .missionVisiting),
    ("Ügyintézés", .officeWork), ("Ügy", .officeWork), ("Értekezlet", .meeting), ("Ért", .meeting),
    ("Evangelizáció", .evangelisation), ("Evang", .evangelisation), ("Bibliaóra", .bibleHour), ("Bibl", .bibleHour),
    ("Továbbképzés", .training), ("Képzés", .training), ("Tartott képzés", .heldTraining), ("Tartott továbbképzés", .heldTraining),
    ("Adminisztráció", .administration), ("Admin", .administration), ("Felkészülés", .preparing), ("Felk", .preparing),
    ("Utazás", .travel), ("Utaz", .travel), ("Szabadság", .holiday), ("Szabadnap", .dayOff),
    ("Munkaszüneti nap", .publicHoliday), ("Munkaszüneti", .publicHoliday)
]
for (name, t) in typeCases {
    for variant in [name, name.uppercased(), name.lowercased(), "  " + name] {
        let m = CalendarParser.matchType(variant + ": x")
        check("típusnév „\(variant)”", m?.type == t, "\(String(describing: m?.type.code))")
    }
}
check("típusnév: szóhatár (Ügyes, Értékelés nem típus)", CalendarParser.matchType("Ügyes dolog") == nil && CalendarParser.matchType("Értékelés: x") == nil && CalendarParser.matchType("Adminisztrátor") == nil)
check("típusnév: ékezet nélkül", CalendarParser.matchType("Ertekezlet: x")?.type == .meeting && CalendarParser.matchType("felkeszules")?.type == .preparing)
check("típusnév: leghosszabb egyezés", CalendarParser.matchType("Missziós látogatás ×2")?.type == .missionVisiting && CalendarParser.matchType("Tartott képzés: x")?.type == .heldTraining && CalendarParser.matchType("Képzés: x")?.type == .training)
check("típusnév: nem törhető szóköz", CalendarParser.matchType("Munkaszüneti\u{00A0}nap")?.type == .publicHoliday)

// alap esetek a leírásból
do {
    let o = parsed(ev("Értekezlet: Heti munkatársi megbeszélés", loc: "Győr", at(2026, 10, 1, 9), at(2026, 10, 1, 10, 30)))
    let x = one(o)
    check("Értekezlet: 1:30, Győr, tevékenység", x?.type == .meeting && x?.durationSeconds == 5400 && x?.workplace == "Győr" && x?.activity == "Heti munkatársi megbeszélés" && x?.address == nil, "\(o)")
    check("azonosító a nap szuffixszel", x?.calendarID == "E1#2026-10-01" && x?.date == "2026-10-01")
    let en = x?.entry()
    check("bejegyzés: forrás naptár, azonosító, mennyiség nélkül", en?.source == "calendar" && en?.calendarID == "E1#2026-10-01" && en?.quantity == nil && en?.unit == "ora")
}
for sep in [": ", " - ", " – ", " — "] {
    let x = one(parsed(ev("Értekezlet" + sep + "Heti", loc: "Győr", at(2026, 10, 1, 9), at(2026, 10, 1, 10))))
    check("elválasztó „\(sep)”", x?.activity == "Heti" && x?.type == .meeting, "\(String(describing: x?.activity))")
}
do {
    let x = one(parsed(ev("Felkészülés @Mór: Prédikáció", at(2026, 10, 1, 11), at(2026, 10, 1, 13))))
    check("Felkészülés @Mór", x?.workplace == "Mór" && x?.durationSeconds == 7200 && x?.activity == "Prédikáció")
    let y = one(parsed(ev("Felk @Mór", at(2026, 10, 1, 11), at(2026, 10, 1, 12))))
    check("@Település tevékenység nélkül", y?.workplace == "Mór" && y?.activity == "")
    let z = one(parsed(ev("Értekezlet @Tata: x", loc: "Győr", at(2026, 10, 1, 9), at(2026, 10, 1, 10))))
    check("a @ erősebb a Helyszínnél", z?.workplace == "Tata")
    let w = one(parsed(ev("Értekezlet heti megbeszélés", loc: "Győr", at(2026, 10, 1, 9), at(2026, 10, 1, 10))))
    check("elválasztó nélküli szöveg a tevékenység", w?.activity == "heti megbeszélés")
}
// mennyiség
for (title, q, act) in [("Látogatás ×3: Idősek otthona", 3, "Idősek otthona"), ("Látogatás x3: Idősek otthona", 3, "Idősek otthona"), ("Látogatás 3 fő: Idősek otthona", 3, "Idősek otthona"),
                        ("Látogatás: Idősek otthona 3 fő", 3, "Idősek otthona"), ("Látogatás: Idősek otthona", 1, "Idősek otthona"), ("Látogatás @Mór ×5: x", 5, "x"),
                        ("Látogatás ×0: x", 1, "x"), ("Látogatás: ×2 család", 2, "család")] {
    let x = one(parsed(ev(title, loc: "Mór", at(2026, 10, 1, 14), at(2026, 10, 1, 15))))
    check("mennyiség „\(title)”", x?.quantity == q && x?.activity == act && x?.type == .visiting, "\(String(describing: x?.quantity)) \(String(describing: x?.activity))")
}
do {
    let x = one(parsed(ev("Istentisztelet", loc: "Tata", at(2026, 10, 3, 10), at(2026, 10, 3, 12))))
    check("Istentisztelet: 1 alkalom, 2 óra tájékoztatóul", x?.quantity == 1 && x?.durationSeconds == 7200 && x?.workplace == "Tata" && x?.entry().creditSeconds == 3600)
    let y = one(parsed(ev("Missziós látogatás ×2: x", loc: "Mór", at(2026, 10, 1, 14), at(2026, 10, 1, 15))))
    check("Missziós látogatás ×2", y?.type == .missionVisiting && y?.quantity == 2)
    let b = one(parsed(ev("Bibl: Fiatalok", loc: "Bicske", at(2026, 10, 1, 18), at(2026, 10, 1, 19, 30))))
    check("Bibl: Fiatalok", b?.type == .bibleHour && b?.workplace == "Bicske" && b?.quantity == 1 && b?.activity == "Fiatalok")
    let m = one(parsed(ev("Ért ×3: x", loc: "Győr", at(2026, 10, 1, 9), at(2026, 10, 1, 10))))
    check("óra típusnál a ×3 nem mennyiség", m?.quantity == nil)
}

// hiányos és nem felismert
do {
    let o = parsed(ev("Értekezlet: x", at(2026, 10, 1, 9), at(2026, 10, 1, 10)))
    check("hiányos: nincs munkahely", problems(o) == [.missingWorkplace] && drafts(o).count == 1, "\(o)")
    if case .incomplete(let t, _, _) = o { check("hiányos: típus megmarad", t == .meeting) }
    check("nem felismert", parsed(ev("Fogorvos", at(2026, 10, 1, 9), at(2026, 10, 1, 10))) == .unrecognized(title: "Fogorvos"))
    check("üres cím nem felismert", parsed(ev("   ", at(2026, 10, 1, 9), at(2026, 10, 1, 10))) == .unrecognized(title: ""))
    check("nulla időtartam hiányos", problems(parsed(ev("Értekezlet", loc: "Győr", at(2026, 10, 1, 9), at(2026, 10, 1, 9)))) == [.noDuration])
    check("negatív időtartam hiányos", problems(parsed(ev("Értekezlet", loc: "Győr", at(2026, 10, 1, 10), at(2026, 10, 1, 9)))) == [.noDuration])
    check("túl hosszú esemény hiányos", problems(parsed(ev("Értekezlet", loc: "Győr", at(2026, 5, 1, 9), at(2026, 8, 1, 9)))).contains(.tooLong))
}

// címek
func placeOf(_ s: String) -> CalendarParser.Place { CalendarParser.place(s) }
check("cím: település vessző után", placeOf("Fő utca 3., Győr") == CalendarParser.Place(settlement: "Győr", address: "Fő utca 3., Győr"))
check("cím: irányítószám és ország nélkül", placeOf("Fő utca 3., 9021 Győr, Magyarország").settlement == "Győr" && placeOf("Fő u. 3, 9021 Győr, Hungary").settlement == "Győr")
check("cím: település elöl", placeOf("Győr, Fő utca 3.").settlement == "Győr" && placeOf("9021 Győr, Fő utca 3.").settlement == "Győr")
check("cím: puszta település nem pontos cím", placeOf("Győr") == CalendarParser.Place(settlement: "Győr", address: nil))
check("cím: kötőjeles név", placeOf("Szent-Györgyi u. 3., Győr").settlement == "Győr" && placeOf("Győr-Moson").settlement == "Győr-Moson")
check("cím: település nélküli cím", placeOf("Fő utca 3").settlement == nil && placeOf("").settlement == nil && placeOf(" , ").settlement == nil)
check("cím: szétvágás ` - ` mentén", CalendarParser.splitLocations("Fő utca 3., Győr - Mór u. 5, Mór") == ["Fő utca 3., Győr", "Mór u. 5, Mór"])
check("cím: a címen belüli kötőjel nem választ el", CalendarParser.splitLocations("Szent-Györgyi u. 3., Győr-Moson") == ["Szent-Györgyi u. 3., Győr-Moson"] && CalendarParser.splitLocations("A–B u. 1., Győr").count == 1)
check("cím: gondolatjel is elválaszt", CalendarParser.splitLocations("Győr – Mór") == ["Győr", "Mór"] && CalendarParser.splitLocations("Győr — Mór") == ["Győr", "Mór"])
do {
    let x = one(parsed(ev("Értekezlet: x", loc: "Fő utca 3., Győr", at(2026, 10, 1, 9), at(2026, 10, 1, 10))))
    check("esemény: cím a CSV-oszlopba, település a munkahelyre", x?.workplace == "Győr" && x?.address == "Fő utca 3., Győr")
    let y = parsed(ev("Értekezlet: x", loc: "Fő utca 3., Győr - Mór u. 5, Mór", at(2026, 10, 1, 9), at(2026, 10, 1, 10)))
    check("esemény: több cím hiányos, az első a munkahely", problems(y) == [.multipleAddresses] && drafts(y).first?.workplace == "Győr" && drafts(y).first?.address == "Fő utca 3., Győr", "\(y)")
    let z = one(parsed(ev("Értekezlet @Tata: x", loc: "Fő utca 3., Győr", at(2026, 10, 1, 9), at(2026, 10, 1, 10))))
    check("esemény: @ mellett idegen cím nem kerül be", z?.workplace == "Tata" && z?.address == nil)
    let w = one(parsed(ev("Értekezlet @Győr: x", loc: "Fő utca 3., Győr", at(2026, 10, 1, 9), at(2026, 10, 1, 10))))
    check("esemény: @ mellett egyező cím bekerül", w?.workplace == "Győr" && w?.address == "Fő utca 3., Győr")
    let v = one(parsed(ev("Értekezlet: x", loc: "Győr", at(2026, 10, 1, 9), at(2026, 10, 1, 10))))
    check("esemény: puszta település nem cím", v?.address == nil)
}

// Utazás
do {
    let routes: [(String, String)] = [("Győr ⇄ Tata, Mór | Kiszállás", "⇄"), ("Győr <-> Tata, Mór | Kiszállás", "<->"), ("Győr oda-vissza Tata, Mór | Kiszállás", "oda-vissza"),
                                      ("Győr → Tata, Mór → Győr | Kiszállás", "→"), ("Győr -> Tata, Mór -> Győr | Kiszállás", "->")]
    for (r, tag) in routes {
        let x = one(parsed(ev("Utazás: " + r, at(2026, 10, 1, 7, 30), at(2026, 10, 1, 8, 15))))
        check("utazás útvonal „\(tag)”", x?.type == .travel && x?.departure == "Győr" && x?.arrival == "Győr" && x?.workplace == "Tata, Mór" && x?.activity == "Kiszállás" && x?.durationSeconds == 2700, "\(String(describing: x))")
    }
    let a = one(parsed(ev("Utaz: Győr → Tata → Mór → Bicske | cél", at(2026, 10, 1, 7), at(2026, 10, 1, 8))))
    check("utazás: különböző érkezés", a?.departure == "Győr" && a?.workplace == "Tata, Mór" && a?.arrival == "Bicske")
    let b = one(parsed(ev("Utazás: Kiszállás", loc: "Tata", at(2026, 10, 1, 7), at(2026, 10, 1, 8))))
    check("utazás: nincs útvonal, a székhely az alapérték", b?.departure == "Győr" && b?.arrival == "Győr" && b?.workplace == "Tata" && b?.activity == "Kiszállás")
    let c = one(parsed(ev("Utazás: Tata | Kiszállás", at(2026, 10, 1, 7), at(2026, 10, 1, 8))))
    check("utazás: csak munkahely a | előtt", c?.workplace == "Tata" && c?.departure == "Győr" && c?.arrival == "Győr")
    let d1 = one(parsed(ev("Utazás: Győr ⇄ Tata", notes: "Kiszállás\nmásodik sor", at(2026, 10, 1, 7), at(2026, 10, 1, 8))))
    check("utazás: cél a Leírás első sorából", d1?.activity == "Kiszállás")
    check("utazás: cél nélkül hiányos", problems(parsed(ev("Utazás: Győr ⇄ Tata", at(2026, 10, 1, 7), at(2026, 10, 1, 8)))) == [.missingActivity])
    check("utazás: székhely nélkül hiányos", problems(parsed(ev("Utazás: Kiszállás", loc: "Tata", at(2026, 10, 1, 7), at(2026, 10, 1, 8)), home: "")) == [.missingDeparture])
    let e1 = parsed(ev("Utazás: Győr → Tata | Kiszállás", at(2026, 10, 1, 7), at(2026, 10, 1, 8)))
    check("utazás: egy nyíl, a munkahely hiányos (nem tippel)", problems(e1) == [.missingWorkplace] && drafts(e1).first?.arrival == "Tata" && drafts(e1).first?.departure == "Győr", "\(e1)")
    let f = one(parsed(ev("Utazás: Kiszállás", loc: "Fő utca 3., Győr - Mór u. 5., Mór", at(2026, 10, 1, 7), at(2026, 10, 1, 8))))
    check("utazás: a címek a munkahelyek sorrendjét adják", f?.workplace == "Győr, Mór" && f?.address == "Fő utca 3., Győr - Mór u. 5., Mór", "\(String(describing: f))")
    let g = one(parsed(ev("Utazás: Győr ⇄ Tata, Mór | Kiszállás", loc: "Fő u. 3., Tata - Mór u. 5., Mór", at(2026, 10, 1, 7), at(2026, 10, 1, 8))))
    check("utazás: az útvonal települései és a címek együtt", g?.workplace == "Tata, Mór" && g?.address == "Fő u. 3., Tata - Mór u. 5., Mór")
    let h = one(parsed(ev("Utazás @Tata: Kiszállás", at(2026, 10, 1, 7), at(2026, 10, 1, 8))))
    check("utazás: @Település munkahelyként", h?.workplace == "Tata")
}

// kihagyás: lezajlott, visszautasított, törölt
do {
    let past = ev("Értekezlet", loc: "Győr", at(2026, 10, 1, 9), at(2026, 10, 1, 10))
    check("kihagyás: jövőbeli", parsed(past, now: at(2026, 9, 30, 12)) == .skipped(.notFinished))
    check("kihagyás: éppen tartó", parsed(past, now: at(2026, 10, 1, 9, 30)) == .skipped(.notFinished))
    check("átvétel: pont a vége után", one(parsed(past, now: at(2026, 10, 1, 10))) != nil)
    var dec = past; dec.isDeclined = true
    var can = past; can.isCancelled = true
    check("kihagyás: visszautasított és törölt", parsed(dec) == .skipped(.declined) && parsed(can) == .skipped(.cancelled))
    var decUnknown = ev("Fogorvos", at(2026, 10, 1, 9), at(2026, 10, 1, 10)); decUnknown.isDeclined = true
    check("kihagyás: a visszautasított nem kerül a nem felismertek közé", parsed(decUnknown) == .skipped(.declined))
    check("kihagyás: jövőbeli nem felismert sem jelenik meg", parsed(ev("Fogorvos", at(2027, 1, 1, 9), at(2027, 1, 1, 10)), now: at(2026, 10, 1)) == .skipped(.notFinished))
}

// egész napos
do {
    for endForm in [at(2026, 10, 3, 23, 59), d(2026, 10, 4)] {
        let o = parsed(ev("Szabadság", d(2026, 10, 1), endForm, allDay: true))
        check("egész napos: 3 nap, naponta egy bejegyzés", drafts(o).map { $0.date } == ["2026-10-01", "2026-10-02", "2026-10-03"], "\(drafts(o).map { $0.date })")
        check("egész napos: nulla idő, nincs munkahely-kötelezettség", drafts(o).allSatisfy { $0.durationSeconds == 0 && $0.start == nil && $0.type == .holiday } && { if case .imported = o { return true }; return false }())
    }
    let o = parsed(ev("Szabadság", d(2026, 10, 1), at(2026, 10, 3, 23, 59), allDay: true, id: "ABC"))
    check("egész napos: külön azonosító naponta", drafts(o).map { $0.calendarID } == ["ABC#2026-10-01", "ABC#2026-10-02", "ABC#2026-10-03"])
    let part = parsed(ev("Szabadság", d(2026, 10, 1), at(2026, 10, 3, 23, 59), allDay: true), now: at(2026, 10, 2, 12))
    check("egész napos: csak a mai napnál korábbi napok", drafts(part).map { $0.date } == ["2026-10-01"])
    check("egész napos: csak jövőbeli kihagyva", parsed(ev("Szabadnap", d(2026, 10, 5), d(2026, 10, 5), allDay: true), now: at(2026, 10, 5, 12)) == .skipped(.notFinished))
    check("egész napos: egynapos, a vége egyezik a kezdéssel", drafts(parsed(ev("Munkaszüneti nap", d(2026, 10, 23), d(2026, 10, 23), allDay: true))).count == 1)
    check("egész napos: más típus hiányos", problems(parsed(ev("Értekezlet", loc: "Győr", d(2026, 10, 1), d(2026, 10, 1), allDay: true))).contains(.wholeDayNotAllowed))
    let long = parsed(ev("Szabadság", d(2026, 7, 1), at(2026, 8, 20, 23, 59), allDay: true))
    check("egész napos: hosszú szabadság is átvehető", drafts(long).count == 51 && { if case .imported = long { return true }; return false }(), "\(drafts(long).count)")
    let timedHoliday = parsed(ev("Szabadság", at(2026, 10, 1, 9), at(2026, 10, 1, 17)))
    check("időzített szabadság egész napos bejegyzés", drafts(timedHoliday).count == 1 && drafts(timedHoliday)[0].start == nil)
    let wd = one(parsed(ev("Szabadság: Nyaralás", d(2026, 10, 1), d(2026, 10, 1), allDay: true)))
    check("egész napos megjegyzés", wd?.activity == "Nyaralás")
}

// éjfélen átnyúló esemény két részre bomlik
do {
    let o = parsed(ev("Értekezlet", loc: "Győr", at(2026, 10, 1, 22), at(2026, 10, 2, 2)))
    let ds = drafts(o)
    check("éjfél: két rész", ds.count == 2 && ds.map { $0.date } == ["2026-10-01", "2026-10-02"], "\(ds.map { $0.date })")
    check("éjfél: napi 2 óra", ds.map { $0.durationSeconds } == [7200, 7200])
    check("éjfél: az első 24:00-ig, a második 0:00-tól", ds.first?.end == d(2026, 10, 2) && ds.last?.start == d(2026, 10, 2))
    check("éjfél: saját azonosító naponta", ds.map { $0.calendarID } == ["E1#2026-10-01", "E1#2026-10-02"])
    // CSV-oda-vissza: a nap végi „24:00” hibátlanul megmarad
    let entries = ds.map { $0.entry() }
    if let back = try? CSV.decode(CSV.encode(entries)).entries {
        check("éjfél: CSV-oda-vissza", back.count == 2 && back.map { $0.durationSeconds } == [7200, 7200] && back.map { $0.date } == ["2026-10-01", "2026-10-02"], "\(back.map { $0.durationSeconds })")
    } else { check("éjfél: CSV-oda-vissza dekódolható", false) }
    let q = parsed(ev("Istentisztelet", loc: "Tata", at(2026, 10, 1, 23), at(2026, 10, 2, 1)))
    check("éjfél: alkalom/fő típusnál nem bomlik (a mennyiség nem duplázódik)", drafts(q).count == 1 && drafts(q)[0].quantity == 1)
    let three = drafts(parsed(ev("Értekezlet", loc: "Győr", at(2026, 10, 1, 20), at(2026, 10, 3, 4))))
    check("éjfél: három nap", three.count == 3 && three.map { $0.durationSeconds } == [4 * 3600, 86400, 4 * 3600], "\(three.map { $0.durationSeconds })")
}

// 2024–2035, minden negyedév: negyedév-/évhatár, szökőnap, nyári időszámítás
for year in 2024...2035 {
    for q in 1...4 {
        let tag = "\(year)/Q\(q)"
        guard let qs = DateUtil.quarterStart(year: year, quarter: q) else { check("\(tag) negyedévkezdet", false); continue }
        let lastDay = DateUtil.addDays(qs, -1)
        let s = cal.date(bySettingHour: 22, minute: 0, second: 0, of: lastDay) ?? lastDay
        let e = cal.date(bySettingHour: 1, minute: 30, second: 0, of: qs) ?? qs
        let ds = drafts(parsed(ev("Értekezlet", loc: "Győr", s, e)))
        check("\(tag): negyedékhatáron átnyúló esemény két nap", ds.count == 2 && ds.map { $0.date } == [ymd(lastDay), ymd(qs)], "\(ds.map { $0.date })")
        check("\(tag): a szeletek összege az esemény hossza", ds.reduce(0) { $0 + $1.durationSeconds } == Int(e.timeIntervalSince(s).rounded()))
        let h = ds.first?.end == qs && ds.last?.start == qs
        check("\(tag): a vágás pontosan éjfélkor", h)
        let sz = parsed(ev("Szabadság", DateUtil.addDays(qs, -2), DateUtil.addDays(qs, 2), allDay: true))
        check("\(tag): egész napos esemény a negyedévhatáron át 4 nap", drafts(sz).count == 4, "\(drafts(sz).count)")
    }
    // szökőnap
    let isLeap = DateUtil.date(year: year, month: 2, day: 29) != nil
    let sl = drafts(parsed(ev("Értekezlet", loc: "Győr", at(year, 2, 28, 22), at(year, 3, 1, 2))))
    check("\(year): február vége (\(isLeap ? "szökőév" : "nem szökőév"))", sl.count == (isLeap ? 3 : 2), "\(sl.map { $0.date })")
    if isLeap { check("\(year): a szökőnap 24 óra", sl.count == 3 && sl[1].date == "\(year)-02-29" && sl[1].durationSeconds == 86400) }
    // évhatár
    let ny = drafts(parsed(ev("Értekezlet", loc: "Győr", at(year, 12, 31, 23), at(year + 1, 1, 1, 1))))
    check("\(year): évhatár", ny.map { $0.date } == ["\(year)-12-31", "\(year + 1)-01-01"] && ny.map { $0.durationSeconds } == [3600, 3600], "\(ny.map { $0.date })")
    // nyári időszámítás váltása: az utolsó márciusi és októberi vasárnap körül minden szelet összege az esemény valódi hossza
    for month in [3, 10] {
        var day = d(year, month, 31)
        var guardN = 0
        while !DateUtil.isSunday(day) && guardN < 8 { day = DateUtil.addDays(day, -1); guardN += 1 }
        let s2 = cal.date(bySettingHour: 20, minute: 0, second: 0, of: DateUtil.addDays(day, -1)) ?? day
        let e2 = cal.date(bySettingHour: 8, minute: 0, second: 0, of: DateUtil.addDays(day, 1)) ?? day
        let dsd = drafts(parsed(ev("Értekezlet", loc: "Győr", s2, e2)))
        check("\(year)/\(month): nyári időszámítás váltáskor a szeletek összege", dsd.reduce(0) { $0 + $1.durationSeconds } == Int(e2.timeIntervalSince(s2).rounded()) && dsd.count == 3 && Set(dsd.map { $0.date }).count == 3, "\(dsd.map { $0.date }) \(dsd.map { $0.durationSeconds })")
    }
}

// bejegyzés és CSV: új oszlopok, régi fájlok
section("Naptár: CSV (Cím, Naptár azonosító)")
do {
    let en = Entry(id: UUID(), date: "2026-10-01", start: at(2026, 10, 1, 9), end: at(2026, 10, 1, 10), durationSeconds: 3600, workplace: "Győr", type: "MEETING", typeLabel: "Értekezlet", unit: "ora", quantity: nil, activity: "x; y", source: "calendar", departure: nil, arrival: nil, address: "Fő utca 3., Győr - Mór u. 5., Mór", calendarID: "ABC|2026#2026-10-01")
    let back = try? CSV.decode(CSV.encode([en])).entries
    check("CSV: cím és naptár-azonosító oda-vissza", back?.first?.address == en.address && back?.first?.calendarID == en.calendarID && back?.first?.workplace == "Győr", "\(String(describing: back?.first))")
    let plain = Entry(id: UUID(), date: "2026-10-01", start: nil, end: nil, durationSeconds: 3600, workplace: "Győr", type: "MEETING", typeLabel: "Értekezlet", unit: "ora", quantity: nil, activity: "", source: "manual")
    let b2 = try? CSV.decode(CSV.encode([plain])).entries
    check("CSV: cím nélküli bejegyzés változatlan", b2?.first?.address == nil && b2?.first?.calendarID == nil)
    check("CSV: a fejléc a végén kapja az új oszlopokat", CSV.columns.suffix(7) == ["Cím", "Naptár azonosító", "Indulás cím", "Érkezés cím", "Munkahely helye", "Induló km", "Érkező km"] && CSV.columns.count == 22)
    let old = "Azonosító;Dátum;Kezdés;Vége;Időtartam (mp);Időtartam (óó:pp);Indulás;Munkahely;Érkezés;Típus kód;Típus;Egység;Mennyiség;Tevékenység;Forrás\r\n\(UUID().uuidString);2026-10-01;09:00:00;10:00:00;3600;1:00;;Győr;;MEETING;Értekezlet;ora;;x;manual\r\n"
    let r = try? CSV.decode(Data(old.utf8))
    check("CSV: a régi (új oszlopok nélküli) fájl olvasható", r?.entries.count == 1 && r?.entries.first?.address == nil && r?.entries.first?.calendarID == nil && r?.warnings.isEmpty == true)
}

// MARK: Naptár-réteg (EventKit)

section("Naptár-réteg")
check("tartomány: üres és fordított", CalendarRange.chunks(from: d(2026, 5, 1), to: d(2026, 5, 1)).isEmpty && CalendarRange.chunks(from: d(2026, 5, 2), to: d(2026, 5, 1)).isEmpty)
for year in 2024...2035 {
    for q in 1...4 {
        guard let qs = DateUtil.quarterStart(year: year, quarter: q) else { continue }
        let end = DateUtil.addDays(qs, 700)
        let ch = CalendarRange.chunks(from: qs, to: end)
        let contiguous = zip(ch, ch.dropFirst()).allSatisfy { $0.0.1 == $0.1.0 }
        check("tartomány \(year)/Q\(q): 2 darab, összefüggő, teljes", ch.count == 2 && contiguous && ch.first?.0 == qs && ch.last?.1 == end, "\(ch.count)")
        check("tartomány \(year)/Q\(q): egy darab sem hosszabb egy évnél", ch.allSatisfy { cal.dateComponents([.day], from: $0.0, to: $0.1).day ?? 999 <= 366 })
    }
}
check("tartomány: rövid időszak egy darab", CalendarRange.chunks(from: d(2026, 10, 1), to: d(2026, 10, 31)).count == 1)
check("tartomány: a darabszám korlátos", CalendarRange.chunks(from: d(1990, 1, 1), to: d(2035, 1, 1), maxChunks: 5).count == 5)
check("azonosító: egyszeri esemény változatlan", CalendarRange.eventID(identifier: "ABC", occurrence: d(2026, 10, 1), isRecurringInstance: false) == "ABC")
let occ1 = CalendarRange.eventID(identifier: "ABC", occurrence: d(2026, 10, 1), isRecurringInstance: true)
let occ2 = CalendarRange.eventID(identifier: "ABC", occurrence: d(2026, 10, 8), isRecurringInstance: true)
check("azonosító: ismétlődő példányok külön azonosítót kapnak", occ1 != occ2 && occ1.hasPrefix("ABC|") && occ1 == CalendarRange.eventID(identifier: "ABC", occurrence: d(2026, 10, 1), isRecurringInstance: true))
check("azonosító: dátum nélkül változatlan", CalendarRange.eventID(identifier: "ABC", occurrence: nil, isRecurringInstance: true) == "ABC")
do {
    // memóriában létrehozott esemény (naptárhozzáférés és mentés nélkül)
    let store = EKEventStore()
    let e = EKEvent(eventStore: store)
    e.title = "Értekezlet: Heti"
    e.location = "Fő utca 3., Győr"
    e.notes = "jegyzet"
    e.startDate = at(2026, 10, 1, 9)
    e.endDate = at(2026, 10, 1, 10)
    let inp = EventKitCalendarSource.makeInput(e)
    check("EventKit-esemény átalakítása", inp.title == "Értekezlet: Heti" && inp.location == "Fő utca 3., Győr" && inp.notes == "jegyzet" && inp.start == at(2026, 10, 1, 9) && inp.end == at(2026, 10, 1, 10) && !inp.isAllDay && !inp.isDeclined && !inp.isCancelled && !inp.id.isEmpty)
    check("EventKit-esemény: az értelmező elfogadja", one(parsed(inp))?.workplace == "Győr")
    let blank = EKEvent(eventStore: store)
    let b = EventKitCalendarSource.makeInput(blank)
    check("EventKit-esemény: hiányos adat nem omlik össze", b.title == "" && b.end >= b.start)
    e.isAllDay = true
    check("EventKit-esemény: egész napos jelző", EventKitCalendarSource.makeInput(e).isAllDay)
}
check("hozzáférés-szövegek", [CalendarAccess.notDetermined, .granted, .denied, .restricted, .writeOnly].allSatisfy { !$0.text.isEmpty })

// MARK: Naptár-szinkron

section("Naptár-szinkron")
final class FakeCalendarSource: CalendarSource {
    var access: CalendarAccess = .granted
    var cals = [CalendarInfo(id: "A", title: "OTS Munkajelentő", account: "iCloud", colorHex: nil), CalendarInfo(id: "B", title: "Személyes", account: "iCloud", colorHex: nil)]
    var items: [(cal: String, event: CalendarEventInput)] = []
    func requestAccess() async -> Bool { access = .granted; return true }
    func calendars() -> [CalendarInfo] { cals }
    func events(calendarIDs: Set<String>?, from: Date, to: Date) -> [CalendarEventInput] {
        items.filter { (calendarIDs?.contains($0.cal) ?? true) && $0.event.start < to && $0.event.end > from }.map { $0.event }
    }
    func observeChanges(_ handler: @escaping () -> Void) -> NSObjectProtocol? { nil }
    func set(_ id: String, cal: String = "A", _ e: CalendarEventInput) { items.removeAll { $0.event.id == id }; items.append((cal, e)) }
    func remove(_ id: String) { items.removeAll { $0.event.id == id } }
}
check("baseID: napi utótag levágása", CalendarSync.baseID("ABC#2026-10-01") == "ABC" && CalendarSync.baseID("ABC|123#2026-10-01") == "ABC|123" && CalendarSync.baseID("ABC") == "ABC" && CalendarSync.baseID("A#B") == "A#B")

let syncDir = tmp + "/sync"
try? FileManager.default.removeItem(atPath: syncDir)
let prevDataFile = UserDefaults.standard.string(forKey: "dataFile")
UserDefaults.standard.set(syncDir + "/bejegyzesek.csv", forKey: "dataFile")
UserDefaults.standard.set("Győr", forKey: "home")
for k in ["ekcal.enabled", "ekcal.calendars", "ekcal.days", "ekcal.dismissed"] { UserDefaults.standard.removeObject(forKey: k) }
do {
    let sm = AppModel()
    let src = FakeCalendarSource()
    let syncer = CalendarSyncer(model: sm, source: src)
    let nowS = at(2026, 10, 10, 12)
    check("szinkron: kikapcsolva nem fut", syncer.sync(now: nowS) == nil)
    syncer.enabled = true
    check("szinkron: naptár kiválasztása nélkül nem fut", syncer.sync(now: nowS) == nil)
    syncer.selectedCalendarIDs = ["A"]
    src.access = .denied
    check("szinkron: engedély nélkül nem fut", syncer.sync(now: nowS) == nil)
    src.access = .granted

    // kézzel felvitt bejegyzés: a szinkron sosem érinti
    sm.add(Entry(id: UUID(), date: "2026-10-05", start: nil, end: nil, durationSeconds: 3600, workplace: "Tata", type: "MEETING", typeLabel: "Értekezlet", unit: "ora", quantity: nil, activity: "kézi", source: "manual"))
    let manualID = sm.entries.last?.id

    src.set("e1", ev("Értekezlet: Heti", loc: "Fő utca 3., Győr", at(2026, 10, 5, 9), at(2026, 10, 5, 10), id: "e1"))
    src.set("e2", ev("Szabadság", d(2026, 10, 6), at(2026, 10, 7, 23, 59), allDay: true, id: "e2"))
    src.set("e3", ev("Fogorvos", at(2026, 10, 6, 9), at(2026, 10, 6, 10), id: "e3"))
    src.set("e4", ev("Értekezlet: helyszín nélkül", at(2026, 10, 6, 11), at(2026, 10, 6, 12), id: "e4"))
    src.set("e5", cal: "B", ev("Értekezlet: másik naptár", loc: "Győr", at(2026, 10, 6, 13), at(2026, 10, 6, 14), id: "e5"))
    src.set("e6", ev("Értekezlet: jövő", loc: "Győr", at(2026, 10, 20, 9), at(2026, 10, 20, 10), id: "e6"))

    var r = syncer.sync(now: nowS)
    check("szinkron 1: átvett 3 (1 értekezlet, 2 nap szabadság)", r?.added == 3 && r?.updated == 0 && r?.deleted == 0, "\(String(describing: r))")
    check("szinkron 1: hiányos és nem felismert lista", syncer.incomplete.map { $0.id } == ["e4"] && syncer.unrecognized.map { $0.id } == ["e3"])
    check("szinkron 1: a másik naptár és a jövő kimarad", !sm.entries.contains { $0.calendarID?.hasPrefix("e5") == true || $0.calendarID?.hasPrefix("e6") == true })
    check("szinkron 1: forrás és cím", sm.entries.first { $0.calendarID == "e1#2026-10-05" }.map { $0.source == "calendar" && $0.address == "Fő utca 3., Győr" && $0.workplace == "Győr" } == true)
    check("szinkron 1: biztonsági másolat készült", FileManager.default.fileExists(atPath: syncDir + "/bejegyzesek.naptar-elotti.csv"))

    r = syncer.sync(now: nowS)
    check("szinkron 2: változatlan naptárnál nincs változás", r?.added == 0 && r?.updated == 0 && r?.deleted == 0 && r?.heldDeletions == 0, "\(String(describing: r))")
    sm.loadFromDisk()
    r = syncer.sync(now: nowS)
    check("szinkron 2b: a CSV újraolvasása után sincs változás (egyezik a mentett forma)", r?.added == 0 && r?.updated == 0 && r?.deleted == 0, "\(String(describing: r))")

    // módosítás
    let e1ID = sm.entries.first { $0.calendarID == "e1#2026-10-05" }?.id
    src.set("e1", ev("Értekezlet: Átírt cím", loc: "Fő utca 3., Győr", at(2026, 10, 5, 9), at(2026, 10, 5, 11), id: "e1"))
    r = syncer.sync(now: nowS)
    let e1After = sm.entries.first { $0.calendarID == "e1#2026-10-05" }
    check("szinkron 3: módosítás frissít, azonos azonosítóval", r?.updated == 1 && r?.added == 0 && e1After?.id == e1ID && e1After?.activity == "Átírt cím" && e1After?.durationSeconds == 7200, "\(String(describing: r))")
    check("szinkron 3: a másolat megvan", FileManager.default.fileExists(atPath: syncDir + "/bejegyzesek.naptar-elotti.csv"))

    // megrövidült többnapos esemény: a felesleges nap törlődik
    src.set("e2", ev("Szabadság", d(2026, 10, 6), at(2026, 10, 6, 23, 59), allDay: true, id: "e2"))
    r = syncer.sync(now: nowS)
    check("szinkron 4: megrövidült esemény napja törlődik", r?.deleted == 1 && sm.entries.filter { $0.calendarID?.hasPrefix("e2#") == true }.count == 1, "\(String(describing: r))")

    // törölt esemény
    src.remove("e1")
    r = syncer.sync(now: nowS)
    check("szinkron 5: törölt esemény bejegyzése törlődik", r?.deleted == 1 && !sm.entries.contains { $0.calendarID?.hasPrefix("e1#") == true }, "\(String(describing: r))")
    check("szinkron 5: a kézi bejegyzés érintetlen", sm.entries.contains { $0.id == manualID })

    // áthelyezés másik (nem kiválasztott) naptárba: a bejegyzés marad
    src.set("e2", cal: "B", ev("Szabadság", d(2026, 10, 6), at(2026, 10, 6, 23, 59), allDay: true, id: "e2"))
    r = syncer.sync(now: nowS)
    check("szinkron 6: a nem kiválasztott naptárba került esemény bejegyzése marad", r?.deleted == 0 && sm.entries.contains { $0.calendarID == "e2#2026-10-06" }, "\(String(describing: r))")

    // visszautasított / törölt állapot
    var cancelled = ev("Szabadság", d(2026, 10, 6), at(2026, 10, 6, 23, 59), allDay: true, id: "e2"); cancelled.isCancelled = true
    src.set("e2", cancelled)
    r = syncer.sync(now: nowS)
    check("szinkron 7: törölt (cancelled) esemény bejegyzése törlődik", r?.deleted == 1 && !sm.entries.contains { $0.calendarID?.hasPrefix("e2#") == true }, "\(String(describing: r))")

    // a hiányos esemény megoldása után nem kerül vissza a listára
    check("szinkron 8: a hiányos még listán", syncer.incomplete.map { $0.id } == ["e4"])
    sm.add(Entry(id: UUID(), date: "2026-10-06", start: at(2026, 10, 6, 11), end: at(2026, 10, 6, 12), durationSeconds: 3600, workplace: "Mór", type: "MEETING", typeLabel: "Értekezlet", unit: "ora", quantity: nil, activity: "javított", source: "calendar", calendarID: "e4#2026-10-06"))
    r = syncer.sync(now: nowS)
    check("szinkron 8: megoldott hiányos nem tér vissza és nem íródik felül", r?.incomplete == 0 && r?.updated == 0 && sm.entries.first { $0.calendarID == "e4#2026-10-06" }?.activity == "javított", "\(String(describing: r))")
    syncer.dismiss("e3")
    check("szinkron 9: kihagyott nem felismert eltűnik, és újraszinkron után sem tér vissza", syncer.unrecognized.isEmpty && { _ = syncer.sync(now: nowS); return syncer.unrecognized.isEmpty }())

    // ablakon kívüli (régi) bejegyzés érintetlen, akkor is, ha az esemény nincs a naptárban
    sm.add(Entry(id: UUID(), date: "2026-01-02", start: nil, end: nil, durationSeconds: 3600, workplace: "Győr", type: "MEETING", typeLabel: "Értekezlet", unit: "ora", quantity: nil, activity: "régi", source: "calendar", calendarID: "old#2026-01-02"))
    r = syncer.sync(now: nowS)
    check("szinkron 10: az ablakon kívüli régi bejegyzés érintetlen", r?.deleted == 0 && r?.heldDeletions == 0 && sm.entries.contains { $0.calendarID == "old#2026-01-02" })

    // védelem: sok törlés egyszerre nem fut le magától
    for i in 1...8 {
        src.set("m\(i)", ev("Értekezlet: tömeges \(i)", loc: "Győr", at(2026, 10, 8, 8 + (i % 4)), at(2026, 10, 8, 9 + (i % 4)), id: "m\(i)"))
    }
    r = syncer.sync(now: nowS)
    check("védelem: 8 új átvett", r?.added == 8, "\(String(describing: r))")
    let countBefore = sm.entries.count
    for i in 1...8 { src.remove("m\(i)") }
    r = syncer.sync(now: nowS)
    check("védelem: a sok törlés visszatartva, semmi sem törlődött", r?.deleted == 0 && r?.heldDeletions == 8 && sm.entries.count == countBefore && syncer.heldDeletions.count == 8, "\(String(describing: r))")
    check("védelem: megerősítés után törlődnek", syncer.confirmHeldDeletions() && sm.entries.count == countBefore - 8 && syncer.heldDeletions.isEmpty)
    check("védelem: a kézi bejegyzés most is megvan", sm.entries.contains { $0.id == manualID })

    // védelem: üresnek látszó naptár
    src.items.removeAll()
    r = syncer.sync(now: nowS)
    check("védelem: üres naptárnál a kevés törlés sem fut le magától", (r?.deleted ?? 1) == 0 && (r?.heldDeletions ?? 0) > 0, "\(String(describing: r))")
    syncer.discardHeldDeletions()
    check("védelem: elvetés után nincs visszatartott", syncer.heldDeletions.isEmpty)
}
if let p = prevDataFile { UserDefaults.standard.set(p, forKey: "dataFile") } else { UserDefaults.standard.set(tmp + "/data/bejegyzesek.csv", forKey: "dataFile") }
UserDefaults.standard.set("Székesfehérvár", forKey: "home")
for k in ["ekcal.enabled", "ekcal.calendars", "ekcal.days", "ekcal.dismissed"] { UserDefaults.standard.removeObject(forKey: k) }

// MARK: Naptár: javítás és felület

section("Naptár: javítás (Hiányos / Nem felismert)")
do {
    let nowF = at(2026, 10, 10, 12)
    let unk = CalendarPendingItem(event: ev("Fogorvos", loc: "Fő utca 3., Győr", at(2026, 10, 6, 9), at(2026, 10, 6, 10), id: "u1"), type: nil, drafts: [], problems: [])
    func ok(_ r: Result<[CalendarDraft], CalendarFixError>) -> [CalendarDraft]? { if case .success(let d) = r { return d }; return nil }
    func err(_ r: Result<[CalendarDraft], CalendarFixError>) -> String? { if case .failure(let e) = r { return e.text }; return nil }
    check("javítás: típus nélkül hiba", err(CalendarSync.fixedDrafts(item: unk, fix: CalendarFix(), now: nowF, home: "Győr")) == "Válassz tevékenység-típust.")
    check("javítás: munkahely nélkül hiba", (err(CalendarSync.fixedDrafts(item: unk, fix: CalendarFix(type: .meeting, workplace: " "), now: nowF, home: "Győr")) ?? "").contains("Munkahely"))
    let a = ok(CalendarSync.fixedDrafts(item: unk, fix: CalendarFix(type: .meeting, workplace: "Győr", activity: "Fogorvos"), now: nowF, home: "Győr"))
    check("javítás: nem felismert típust kap", a?.count == 1 && a?[0].type == .meeting && a?[0].workplace == "Győr" && a?[0].activity == "Fogorvos" && a?[0].calendarID == "u1#2026-10-06" && a?[0].address == "Fő utca 3., Győr", "\(String(describing: a))")
    let b = ok(CalendarSync.fixedDrafts(item: unk, fix: CalendarFix(type: .meeting, workplace: "Mór", activity: "x"), now: nowF, home: "Győr"))
    check("javítás: a más településre írt munkahelynél a cím elmarad", b?[0].workplace == "Mór" && b?[0].address == nil)
    let t = ok(CalendarSync.fixedDrafts(item: unk, fix: CalendarFix(type: .travel, workplace: "Tata, Mór", activity: "Kiszállás", departure: "Győr", arrival: "Győr"), now: nowF, home: "Győr"))
    check("javítás: utazás", t?[0].type == .travel && t?[0].departure == "Győr" && t?[0].arrival == "Győr" && t?[0].workplace == "Tata, Mór")
    check("javítás: utazás kötelező mezői", (err(CalendarSync.fixedDrafts(item: unk, fix: CalendarFix(type: .travel, workplace: "Tata"), now: nowF, home: "Győr")) ?? "").contains("Tevékenység"))
    let v = ok(CalendarSync.fixedDrafts(item: unk, fix: CalendarFix(type: .visiting, workplace: "Mór", activity: "x", quantity: 4), now: nowF, home: "Győr"))
    check("javítás: mennyiség", v?[0].quantity == 4 && v?[0].entry().creditSeconds == 4 * 3600)
    let hol = ok(CalendarSync.fixedDrafts(item: unk, fix: CalendarFix(type: .holiday), now: nowF, home: "Győr"))
    check("javítás: egész napos típusnál nem kell munkahely", hol?.count == 1 && hol?[0].type == .holiday && hol?[0].start == nil)

    // hiányos esemény: egész napos esemény más típussal -> egész napos típus
    let allDayEv = ev("Értekezlet", loc: "Győr", d(2026, 10, 6), d(2026, 10, 7), allDay: true, id: "w1")
    if case .incomplete(let ty, let ds, let pr) = parsed(allDayEv, now: nowF) {
        let it = CalendarPendingItem(event: allDayEv, type: ty, drafts: ds, problems: pr)
        let r = ok(CalendarSync.fixedDrafts(item: it, fix: CalendarFix(type: .dayOff), now: nowF, home: "Győr"))
        check("javítás: egész napos esemény típusának cseréje", r?.count == 1 && r?[0].type == .dayOff)
    } else { check("javítás: hiányos egész napos esemény", false) }
    // hiányos: több cím, a felhasználó választ
    let multiEv = ev("Értekezlet: x", loc: "Fő utca 3., Győr - Mór u. 5., Mór", at(2026, 10, 6, 9), at(2026, 10, 6, 10), id: "w2")
    if case .incomplete(let ty, let ds, let pr) = parsed(multiEv, now: nowF) {
        let it = CalendarPendingItem(event: multiEv, type: ty, drafts: ds, problems: pr)
        let r = ok(CalendarSync.fixedDrafts(item: it, fix: CalendarFix(workplace: "Mór", activity: "x"), now: nowF, home: "Győr"))
        check("javítás: több cím közül választott munkahely", r?[0].workplace == "Mór" && r?[0].address == nil)
        let keep = ok(CalendarSync.fixedDrafts(item: it, fix: CalendarFix(workplace: "Győr", activity: "x"), now: nowF, home: "Győr"))
        check("javítás: az egyező település címe megmarad", keep?[0].address == "Fő utca 3., Győr")
    } else { check("javítás: több címes esemény hiányos", false) }
    // nulla időtartam nem javítható
    let zeroEv = ev("Értekezlet", loc: "Győr", at(2026, 10, 6, 9), at(2026, 10, 6, 9), id: "w3")
    if case .incomplete(let ty, let ds, let pr) = parsed(zeroEv, now: nowF) {
        check("javítás: nulla időtartam nem javítható itt", err(CalendarSync.fixedDrafts(item: CalendarPendingItem(event: zeroEv, type: ty, drafts: ds, problems: pr), fix: CalendarFix(workplace: "Győr"), now: nowF, home: "Győr")) != nil)
    }
    check("kanonikus típusnév minden beépített típushoz", ActivityType.builtins.allSatisfy { CalendarParser.canonicalName(for: $0) != nil })
    check("kényszerített típus: minden típusnál a bejegyzés típusa egyezik", ActivityType.builtins.allSatisfy { t in
        let o = CalendarParser.parse(ev("Valami szöveg", loc: "Győr", at(2026, 10, 6, 9), at(2026, 10, 6, 10), id: "z"), forcedType: t, now: nowF, home: "Győr")
        return drafts(o).first?.type == t
    })

    // a szinkronizáló: javítás, ismételt átvétel, megtartás
    let rdir = tmp + "/sync2"
    try? FileManager.default.removeItem(atPath: rdir)
    UserDefaults.standard.set(rdir + "/bejegyzesek.csv", forKey: "dataFile")
    UserDefaults.standard.set("Győr", forKey: "home")
    for k in ["ekcal.enabled", "ekcal.calendars", "ekcal.days", "ekcal.dismissed"] { UserDefaults.standard.removeObject(forKey: k) }
    let rm = AppModel()
    let rsrc = FakeCalendarSource()
    let rs = CalendarSyncer(model: rm, source: rsrc)
    rs.enabled = true; rs.selectedCalendarIDs = ["A"]
    rsrc.set("u1", ev("Fogorvos", at(2026, 10, 6, 9), at(2026, 10, 6, 10), id: "u1"))
    rsrc.set("h1", ev("Értekezlet: x", at(2026, 10, 6, 11), at(2026, 10, 6, 12), id: "h1"))
    rs.sync(now: nowF)
    check("javítás: a két esemény a listán", rs.unrecognized.map { $0.id } == ["u1"] && rs.incomplete.map { $0.id } == ["h1"])
    if let item = rs.unrecognized.first {
        check("javítás: hiányos kitöltés hibát ad, nem ment", rs.resolve(item, fix: CalendarFix(type: .meeting), now: nowF) != nil && rm.entries.isEmpty)
        check("javítás: sikeres átvétel", rs.resolve(item, fix: CalendarFix(type: .meeting, workplace: "Győr", activity: "Fogorvos"), now: nowF) == nil && rm.entries.count == 1 && rs.unrecognized.isEmpty)
    }
    if let item = rs.incomplete.first {
        check("javítás: hiányos esemény átvétele", rs.resolve(item, fix: CalendarFix(workplace: "Tata", activity: "x"), now: nowF) == nil && rm.entries.count == 2 && rs.incomplete.isEmpty)
    }
    let r2 = rs.sync(now: nowF)
    check("javítás: újraszinkron nem duplázza és nem hozza vissza", r2?.added == 0 && r2?.updated == 0 && rm.entries.count == 2 && rs.incomplete.isEmpty && rs.unrecognized.isEmpty, "\(String(describing: r2))")
    // megtartás: törölt esemény, védelem miatt visszatartva, kézi bejegyzéssé válik
    rsrc.items.removeAll()
    let r3 = rs.sync(now: nowF)
    check("megtartás: üres naptárnál visszatartva", r3?.heldDeletions == 2 && rm.entries.count == 2, "\(String(describing: r3))")
    check("megtartás: kézi bejegyzéssé válnak", rs.keepHeldDeletionsAsManual() && rm.entries.allSatisfy { $0.calendarID == nil && $0.source == "manual" } && rs.heldDeletions.isEmpty)
    let r4 = rs.sync(now: nowF)
    check("megtartás: a szinkron többé nem nyúl hozzájuk", r4?.deleted == 0 && r4?.heldDeletions == 0 && rm.entries.count == 2)
    UserDefaults.standard.set(tmp + "/data/bejegyzesek.csv", forKey: "dataFile")
    UserDefaults.standard.set("Székesfehérvár", forKey: "home")
    for k in ["ekcal.enabled", "ekcal.calendars", "ekcal.days", "ekcal.dismissed"] { UserDefaults.standard.removeObject(forKey: k) }
}

section("Naptár: felület")
do {
    let udd = UserDefaults.standard
    let fdir = tmp + "/sync3"
    try? FileManager.default.removeItem(atPath: fdir)
    udd.set(fdir + "/bejegyzesek.csv", forKey: "dataFile")
    udd.set("Győr", forKey: "home")
    let fm2 = AppModel()
    let fsrc = FakeCalendarSource()
    let fs = CalendarSyncer(model: fm2, source: fsrc)
    fs.enabled = true; fs.selectedCalendarIDs = ["A"]
    let nowU = at(2026, 10, 10, 12)
    fsrc.set("u1", ev("Fogorvos", loc: "Fő utca 3., Győr", at(2026, 10, 6, 9), at(2026, 10, 6, 10), id: "u1"))
    fsrc.set("h1", ev("Értekezlet: x", at(2026, 10, 6, 11), at(2026, 10, 6, 12), id: "h1"))
    fsrc.set("h2", ev("Utazás: Győr → Tata | ", at(2026, 10, 7, 7), at(2026, 10, 7, 8), id: "h2"))
    fsrc.set("h3", ev("Értekezlet", loc: "Győr", d(2026, 10, 8), d(2026, 10, 9), allDay: true, id: "h3"))
    fs.refreshAccess()
    fs.sync(now: nowU)
    let renderDir = ProcessInfo.processInfo.environment["OTS_RENDER_DIR"]
    func render(_ view: AnyView, _ size: NSSize, name: String) {
        let h = NSHostingController(rootView: view)
        h.sizingOptions = []
        let w = NSWindow(contentViewController: h)
        w.appearance = NSAppearance(named: .aqua)
        w.backgroundColor = .white
        w.setContentSize(size)
        w.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        check("\(name): az ablak mérete nem változott", abs(w.contentRect(forFrameRect: w.frame).width - size.width) < 1 && abs(w.contentRect(forFrameRect: w.frame).height - size.height) < 1)
        if let dir = renderDir, let cv = w.contentView, let rep = cv.bitmapImageRepForCachingDisplay(in: cv.bounds) {
            cv.cacheDisplay(in: cv.bounds, to: rep)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/\(name).png"))
        }
        w.orderOut(nil)
    }
    render(AnyView(CalendarPendingView(sync: fs).environmentObject(fm2).environment(\.palette, .blue)), NSSize(width: 640, height: 640), name: "naptar-hianyos")
    render(AnyView(CalendarNotationView().environment(\.palette, .blue)), NSSize(width: 620, height: 700), name: "naptar-jelolesek")
    render(AnyView(ScrollView { CalendarSyncCard(sync: fs).environmentObject(fm2).environment(\.palette, .blue).padding(12) }), NSSize(width: 460, height: 640), name: "naptar-beallitasok")
    check("felület: a kártya kikapcsolt állapotban is kirajzolódik", { fs.enabled = false; render(AnyView(CalendarSyncCard(sync: fs).environmentObject(fm2).environment(\.palette, .blue).frame(width: 440)), NSSize(width: 460, height: 200), name: "naptar-kikapcsolva"); return true }())
    let empty = CalendarSyncer(model: fm2, source: FakeCalendarSource())
    render(AnyView(CalendarPendingView(sync: empty).environmentObject(fm2).environment(\.palette, .blue)), NSSize(width: 640, height: 400), name: "naptar-ures")
    fs.enabled = true
    CalendarNotationWindow.shared.show()
    CalendarNotationWindow.shared.windowWillClose(Notification(name: NSWindow.willCloseNotification))
    check("felület: a jelölések ablak megnyitható és bezárható", true)
    udd.set(tmp + "/data/bejegyzesek.csv", forKey: "dataFile")
    udd.set("Székesfehérvár", forKey: "home")
    for k in ["ekcal.enabled", "ekcal.calendars", "ekcal.days", "ekcal.dismissed"] { udd.removeObject(forKey: k) }
}

// MARK: Google Maps: pontos címek

section("Google Maps: pontos címek")
do {
    func tvl(_ wp: String, addr: String?, dep: String? = "Győr", arr: String? = "Győr") -> Entry {
        Entry(id: UUID(), date: "2026-10-12", start: nil, end: nil, durationSeconds: 3600, workplace: wp, type: "TRAVEL", typeLabel: "Utazás", unit: "ora", quantity: nil, activity: "Kiszállás", source: "calendar", departure: dep, arrival: arr, address: addr)
    }
    let e1 = tvl("Tata, Mór", addr: "Fő u. 3., Tata - Mór u. 5., Mór")
    let r1 = OTSManual.routeDetail(e1, home: "Győr")
    check("útvonal címekkel: indulás és érkezés település", r1 == [RoutePoint(name: "Győr", address: nil), RoutePoint(name: "Tata", address: "Fő u. 3., Tata"), RoutePoint(name: "Mór", address: "Mór u. 5., Mór"), RoutePoint(name: "Győr", address: nil)], "\(r1)")
    check("útvonal címekkel: az OTS-be települések mennek (változatlan)", OTSManual.routePoints(e1, home: "Győr") == ["Győr", "Tata", "Mór", "Győr"])
    let e2 = tvl("Tata, Mór", addr: nil)
    check("útvonal cím nélkül: azonos a régivel", OTSManual.routeDetail(e2, home: "Győr").map { $0.name } == OTSManual.routePoints(e2, home: "Győr") && OTSManual.routeDetail(e2, home: "Győr").allSatisfy { $0.address == nil })
    let e3 = tvl("Győr", addr: "Fő utca 3., Győr")
    let r3 = OTSManual.routeDetail(e3, home: "Győr")
    check("a székhelyen lévő címes munkahely nem olvad össze az indulással, a cím nélküli visszaút viszont beleolvad", r3.count == 2 && r3[1].address == "Fő utca 3., Győr" && r3[0].address == nil, "\(r3)")
    let e4 = tvl("Tata, Mór", addr: "Mór u. 5., Mór")
    let r4 = OTSManual.routeDetail(e4, home: "Győr")
    check("csak az egyik munkahelynek van címe", r4.map { $0.address } == [nil, nil, "Mór u. 5., Mór", nil])
    let e5 = tvl("Győr, Győr", addr: "A u. 1., Győr - B u. 2., Győr")
    check("azonos településű címek sorrendben", OTSManual.routeDetail(e5, home: "Győr").compactMap { $0.address } == ["A u. 1., Győr", "B u. 2., Győr"])
    let url = OTSManual.mapsURL(r1, useAddress: { _ in true })
    check("Maps: a pontos címek a hivatkozásban", url?.absoluteString.contains("M%C3%B3r%20u.%205.,%20M%C3%B3r") == true && url?.absoluteString.hasPrefix("https://www.google.com/maps/dir/Gy%C5%91r/") == true, "\(String(describing: url))")
    let url2 = OTSManual.mapsURL(r1, useAddress: { $0.hasPrefix("Mór") ? false : true })
    check("Maps: a nem található cím helyett település", url2?.absoluteString.contains("/M%C3%B3r/") == true && url2?.absoluteString.contains("%20u.%205") == false && url2?.absoluteString.contains("F%C5%91%20u.%203") == true, "\(String(describing: url2))")
    let url3 = OTSManual.mapsURL(r1, useAddress: { _ in false })
    check("Maps: ha egyik cím sem található, a települések", url3 == OTSManual.mapsURL(["Győr", "Tata", "Mór", "Győr"]))
    let rows = OTSManual.costRows(entries: [e1], year: 2026, month: 10, home: "Győr")
    check("költségelszámolás: az útvonal települések, a térkép címekkel", rows.first?.points == ["Győr", "Tata", "Mór", "Győr"] && rows.first?.mapPoints.compactMap { $0.address }.count == 2 && rows.first?.route == "Győr - Tata - Mór - Győr")
    // geokódoló: tiszta részek
    check("geokódoló: a találat településével egyezés", AddressChecker.matches(["Győr", "Győr-Moson-Sopron"], settlement: "Győr") && !AddressChecker.matches(["Mór"], settlement: "Győr"))
    check("geokódoló: ékezet- és kisbetű-független", AddressChecker.matches(["GYOR"], settlement: "Győr"))
    check("geokódoló: nincs találat = nem található", !AddressChecker.matches([], settlement: "Győr") && !AddressChecker.matches([], settlement: nil))
    check("geokódoló: az ország hozzáadása", AddressChecker.query("Fő u. 3., Győr") == "Fő u. 3., Győr, Magyarország" && AddressChecker.query("Fő u. 3., Győr, Magyarország") == "Fő u. 3., Győr, Magyarország" && AddressChecker.query("Main St 1, Hungary") == "Main St 1, Hungary")
}

// MARK: Utazás: Kiindulás és Cél (települések és pontos címek), oda-vissza, munkahely-jelölés

section("Utazás: Kiindulás, Cél, oda-vissza")
do {
    func pl(_ s: String) -> [CalendarParser.ParsedPlace]? { CalendarParser.parsePlaces(s) }
    func one(_ s: String) -> CalendarParser.ParsedPlace? { CalendarParser.parsePlace(s) }
    check("hely: egyszerű település", one("Tata") == CalendarParser.ParsedPlace(settlement: "Tata", address: nil))
    check("hely: település és cím (település elöl)", one("Tata, Fő út 1.") == CalendarParser.ParsedPlace(settlement: "Tata", address: "Fő út 1., Tata"))
    check("hely: több vesszős utcarész", one("Tata, Fő út 1., I. emelet") == CalendarParser.ParsedPlace(settlement: "Tata", address: "Fő út 1., I. emelet, Tata"))
    check("hely: fordított sorrend is érthető", one("Fő út 1., Tata") == CalendarParser.ParsedPlace(settlement: "Tata", address: "Fő út 1., Tata"))
    check("hely: irányítószám és ország", one("9021 Győr, Fő u. 3.")?.settlement == "Győr" && one("Fő u. 3., 9021 Győr, Magyarország")?.settlement == "Győr")
    check("hely: házszám nélküli utca", one("Tata, Fő út") == CalendarParser.ParsedPlace(settlement: "Tata", address: "Fő út, Tata"))
    check("hely: kötőjeles név", one("Győr-Moson")?.settlement == "Győr-Moson")
    check("hely: üres és hibás", pl("") == nil && pl("  ,  ") == nil && pl("12") == nil && pl("Fő utca 3") == nil && pl("Fő út 1.") == nil)
    // több hely a Célban
    check("helyek: vesszős település-lista (a régi szokás)", pl("Tata, Mór")?.map { $0.settlement } == ["Tata", "Mór"] && pl("Tata, Mór")?.allSatisfy { $0.address == nil } == true)
    check("helyek: egyik pontos, másik egyszerű", pl("Tata, Fő út 1., Mór") == [CalendarParser.ParsedPlace(settlement: "Tata", address: "Fő út 1., Tata"), CalendarParser.ParsedPlace(settlement: "Mór", address: nil)])
    check("helyek: mindkettő pontos", pl("Tata, Fő út 1., Mór, Kossuth u. 5.") == [CalendarParser.ParsedPlace(settlement: "Tata", address: "Fő út 1., Tata"), CalendarParser.ParsedPlace(settlement: "Mór", address: "Kossuth u. 5., Mór")])
    check("helyek: az első egyszerű, a második pontos", pl("Tata, Mór, Kossuth u. 5.") == [CalendarParser.ParsedPlace(settlement: "Tata", address: nil), CalendarParser.ParsedPlace(settlement: "Mór", address: "Kossuth u. 5., Mór")])
    check("helyek: elválasztó ` - ` és `;`", pl("Tata - Mór u. 5., Mór")?.map { $0.settlement } == ["Tata", "Mór"] && pl("Tata, Fő út 1.; Mór")?.map { $0.settlement } == ["Tata", "Mór"])
    check("helyek: utcával kezdődő második cím (fordított)", pl("Tata, Fő út 1., Kossuth u. 5., Mór") == [CalendarParser.ParsedPlace(settlement: "Tata", address: "Fő út 1., Tata"), CalendarParser.ParsedPlace(settlement: "Mór", address: "Kossuth u. 5., Mór")])
    check("helyek: egyetlen helyből nem lesz több", one("Tata, Mór") == nil)

    let ud2 = UserDefaults.standard
    let adir = tmp + "/addr"
    try? FileManager.default.removeItem(atPath: adir)
    ud2.set(adir + "/bejegyzesek.csv", forKey: "dataFile")
    ud2.set("Győr", forKey: "home")
    for k in ["draft.departure", "draft.destination"] { ud2.removeObject(forKey: k) }
    let am = AppModel()
    am.clearDraft()
    am.selectedType = .travel
    check("utazás: a kiindulás alapja a székhely; az oda-vissza alapból bekapcsolt; a munkahely alapból a Cél", am.departure == "Győr" && am.roundTrip && !am.workplaceIsDeparture)
    am.activity = "Kiszállás"
    let st = Date().addingTimeInterval(-3600)
    func entry() -> Entry { am.makeEntry(start: st, end: st.addingTimeInterval(1800), source: "manual") }
    // 1. Oda-vissza (alapból): Kiindulás -> Cél -> Kiindulás
    am.departure = "Győr"; am.destination = "Tata"
    var e = entry()
    check("oda-vissza: Győr - Tata - Győr", am.fieldsComplete && OTSManual.routePoints(e, home: "X") == ["Győr", "Tata", "Győr"] && e.departure == "Győr" && e.arrival == "Győr" && e.workplace == "Tata" && !e.workplaceIsDeparture, "\(OTSManual.routePoints(e, home: "X"))")
    // több hely a Célban
    am.destination = "Tata, Mór"
    e = entry()
    check("oda-vissza több céllal: Győr - Tata - Mór - Győr", OTSManual.routePoints(e, home: "X") == ["Győr", "Tata", "Mór", "Győr"] && e.workplace == "Tata, Mór")
    // 2. Egyirányú: a pipa kikapcsolva
    am.roundTrip = false
    e = entry()
    check("egyirányú: Győr - Tata - Mór (nincs visszaút)", OTSManual.routePoints(e, home: "X") == ["Győr", "Tata", "Mór"] && e.arrival == "Mór", "\(OTSManual.routePoints(e, home: "X"))")
    am.destination = "Tata"
    e = entry()
    check("egyirányú egy céllal: Győr - Tata", OTSManual.routePoints(e, home: "X") == ["Győr", "Tata"] && e.workplace == "Tata")
    // 3. Pontos címek: csak az egyik oldalon, vagy mindkettőn
    am.roundTrip = true
    am.departure = "Győr, Fő út 1."; am.destination = "Tata"
    e = entry()
    check("csak a Kiindulásnak van pontos címe", e.departure == "Győr" && e.departureAddress == "Fő út 1., Győr" && e.arrivalAddress == "Fő út 1., Győr" && e.address == nil)
    am.departure = "Győr"; am.destination = "Tata, Kossuth u. 5."
    e = entry()
    check("csak a Célnak van pontos címe", e.departureAddress == nil && e.address == "Kossuth u. 5., Tata" && e.workplace == "Tata")
    am.departure = "Győr, Fő út 1."; am.destination = "Tata, Kossuth u. 5., Mór"
    e = entry()
    let rd = OTSManual.routeDetail(e, home: "Győr")
    check("mindkettőn, és a Célban egyik pontos, másik egyszerű: az OTS útvonal települések, a térkép címekkel", OTSManual.routePoints(e, home: "Győr") == ["Győr", "Tata", "Mór", "Győr"] && rd.map { $0.address } == ["Fő út 1., Győr", "Kossuth u. 5., Tata", nil, "Fő út 1., Győr"], "\(rd)")
    am.roundTrip = false
    e = entry()
    let rd1 = OTSManual.routeDetail(e, home: "Győr")
    check("egyirányú útnál az utolsó cél nem duplázódik a térképen", rd1.map { $0.name } == ["Győr", "Tata", "Mór"] && rd1.map { $0.address } == ["Fő út 1., Győr", "Kossuth u. 5., Tata", nil], "\(rd1)")
    am.roundTrip = true
    // 4. Hibás forma
    am.destination = "5"
    check("hibás cím nem rögzíthető", !am.fieldsComplete && (am.missingFieldsHint ?? "").contains("Cél"))
    am.destination = "Tata"; am.departure = "Győr, Mór"
    check("a Kiindulás csak egy hely lehet", !am.fieldsComplete && (am.missingFieldsHint ?? "").contains("Kiindulás"))
    am.departure = ""
    check("kiindulás nélkül nem rögzíthető", !am.fieldsComplete && (am.missingFieldsHint ?? "").contains("Kiindulás"))
    am.departure = "Győr"; am.destination = ""
    check("cél nélkül nem rögzíthető", !am.fieldsComplete && (am.missingFieldsHint ?? "").contains("Cél"))
    am.activity = ""; am.destination = "Tata"
    check("a Tevékenység az Utazásnál kötelező", !am.fieldsComplete && (am.missingFieldsHint ?? "").contains("Tevékenység"))
    am.activity = "Kiszállás"
    // 5. Munkahely-jelölés
    am.departure = "Győr"; am.destination = "Tata, Mór"; am.workplaceIsDeparture = true
    e = entry()
    check("munkahely a Kiindulás: a bejegyzés jelöli, az útvonal változatlan", e.workplaceIsDeparture && OTSManual.routePoints(e, home: "X") == ["Győr", "Tata", "Mór", "Győr"] && OTSManual.workplaceList([e]) == ["Győr"], "\(OTSManual.workplaceList([e]))")
    am.workplaceIsDeparture = false
    e = entry()
    check("munkahely a Cél (alap): az OTS Munkahely a Cél helyei", !e.workplaceIsDeparture && OTSManual.workplaceList([e]) == ["Tata", "Mór"])
    // 6. Nem utazásnál nincs
    am.clearDraft(); am.selectedType = .meeting; am.workplace = "Győr"
    let plain = am.makeManualEntry(day: Date(), durationSeconds: 3600)
    check("nem utazásnál nincs cím, jelölés", plain.departure == nil && plain.departureAddress == nil && plain.arrivalAddress == nil && plain.address == nil && !plain.workplaceIsDeparture)
    // 7. Mentés és újraolvasás
    am.clearDraft()
    am.selectedType = .travel; am.activity = "Kiszállás"; am.departure = "Győr, Fő út 1."; am.destination = "Tata, Kossuth u. 5."; am.workplaceIsDeparture = true
    am.add(am.makeManualEntry(day: DateUtil.addDays(Date(), -1), durationSeconds: 1800))
    let am2 = AppModel()
    check("mentés és újraolvasás után minden megvan", am2.entries.contains { $0.departureAddress == "Fő út 1., Győr" && $0.address == "Kossuth u. 5., Tata" && $0.workplaceIsDeparture && $0.workplace == "Tata" && $0.departure == "Győr" })
    check("CSV: új oszlop a végén", CSV.columns.suffix(5) == ["Indulás cím", "Érkezés cím", "Munkahely helye", "Induló km", "Érkező km"] && CSV.columns.count == 22)
    let oldCsv = "Azonosító;Dátum;Kezdés;Vége;Időtartam (mp);Időtartam (óó:pp);Indulás;Munkahely;Érkezés;Típus kód;Típus;Egység;Mennyiség;Tevékenység;Forrás\r\n\(UUID().uuidString);2026-10-01;;;1800;0:30;Győr;Tata;Győr;TRAVEL;Utazás;ora;;x;manual\r\n"
    let oldDec = try? CSV.decode(Data(oldCsv.utf8))
    check("régi sor: a Munkahely helye üres = Cél", oldDec?.entries.first?.workplaceIsDeparture == false && oldDec?.entries.count == 1)
    am.clearDraft()
    for k in ["draft.departure", "draft.destination"] { ud2.removeObject(forKey: k) }
    ud2.set(tmp + "/data/bejegyzesek.csv", forKey: "dataFile")
    ud2.set("Székesfehérvár", forKey: "home")
}

section("Időzítő: korábbi kezdés")
do {
    let udT = UserDefaults.standard
    try? FileManager.default.removeItem(atPath: tmp + "/timer")
    udT.set(tmp + "/timer/bejegyzesek.csv", forKey: "dataFile")
    udT.removeObject(forKey: "timer.start")
    let tm = AppModel()
    tm.clearDraft(); tm.selectedType = .meeting; tm.workplace = "Győr"
    let nowT = Date()
    // fix pillanat a számoláshoz
    let dayStartT = DateUtil.startOfDay(nowT)
    check("kezdés: jövőbeli nem lehet", AppModel.clampedStart(nowT.addingTimeInterval(600), now: nowT) == nowT)
    check("kezdés: a mai nap elejénél korábbi nem lehet", AppModel.clampedStart(dayStartT.addingTimeInterval(-3600), now: nowT) == dayStartT)
    check("kezdés: a napon belüli korábbi időpont megmarad", AppModel.clampedStart(nowT.addingTimeInterval(-300), now: nowT) == nowT.addingTimeInterval(-300) || nowT.timeIntervalSince(dayStartT) < 300)
    tm.plannedStart = nowT.addingTimeInterval(-60)
    tm.startStopwatch()
    let started = tm.timerStart
    check("indítás előre megadott kezdéssel: onnantól számol", tm.stopwatchRunning && started != nil && abs((started ?? .distantFuture).timeIntervalSince(nowT) + 60) < 3 && tm.stopwatchElapsed >= 59 && tm.plannedStart == nil, "\(tm.stopwatchElapsed)")
    // futó időzítő kezdésének korrigálása
    tm.setTimerStart(nowT.addingTimeInterval(-120))
    check("futó időzítő kezdésének korrigálása", abs((tm.timerStart ?? .distantFuture).timeIntervalSince(nowT) + 120) < 3 && tm.stopwatchElapsed >= 119)
    tm.setTimerStart(nowT.addingTimeInterval(3600))
    check("a futó időzítő kezdése nem lehet jövőbeli", (tm.timerStart ?? .distantFuture) <= Date())
    tm.setTimerStart(dayStartT.addingTimeInterval(-86400 * 3))
    check("a futó időzítő kezdése legfeljebb a nap elejéig mehet vissza", (tm.timerStart ?? .distantPast) >= dayStartT)
    tm.setTimerStart(nowT.addingTimeInterval(-300))
    tm.stopStopwatch()
    let saved = tm.entries.last
    check("leállítás: a bejegyzés a korábbi kezdéstől számol (≥ 5 perc)", saved != nil && saved?.source == "timer" && (saved?.durationSeconds ?? 0) >= 299 || nowT.timeIntervalSince(dayStartT) < 300, "\(String(describing: saved?.durationSeconds)) \(String(describing: saved?.start)) \(nowT)")
    check("leállítás: a bejegyzés kezdése a megadott korábbi időpont", (saved?.start.map { abs($0.timeIntervalSince(nowT) + 300) < 5 } ?? false) || nowT.timeIntervalSince(dayStartT) < 300, "\(String(describing: saved?.start)) \(nowT)")
    check("leállítás után nincs tervezett kezdés és futó időzítő", tm.plannedStart == nil && !tm.stopwatchRunning)
    tm.clearDraft()
    udT.removeObject(forKey: "timer.start")
    udT.set(tmp + "/data/bejegyzesek.csv", forKey: "dataFile")
}

do {
    // az űrlap kinézete (képpé renderelve, ha az OTS_RENDER_DIR meg van adva)
    let ud3 = UserDefaults.standard
    ud3.set(tmp + "/addr2/bejegyzesek.csv", forKey: "dataFile")
    let fm3 = AppModel()
    fm3.selectedType = .travel; fm3.activity = "Kiszállás"
    fm3.departure = "Győr, Fő út 1."; fm3.destination = "Tata, Kossuth u. 5., Mór"
    if let dir = ProcessInfo.processInfo.environment["OTS_RENDER_DIR"] {
        func shot(_ view: AnyView, _ size: NSSize, _ name: String) {
            let h = NSHostingController(rootView: view)
            h.sizingOptions = []
            let w = NSWindow(contentViewController: h)
            w.appearance = NSAppearance(named: .aqua); w.backgroundColor = .white
            w.setContentSize(size)
            w.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            if let cv = w.contentView, let rep = cv.bitmapImageRepForCachingDisplay(in: cv.bounds) {
                cv.cacheDisplay(in: cv.bounds, to: rep)
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/" + name + ".png"))
            }
            w.orderOut(nil)
        }
        shot(AnyView(FieldsView().environmentObject(fm3).environment(\.palette, .blue).frame(width: 440).padding(14)), NSSize(width: 470, height: 250), "urlap-cim")
        shot(AnyView(FieldsView().environmentObject(fm3).environment(\.palette, .blue).environment(\.compact, true).frame(width: 340).padding(8)), NSSize(width: 360, height: 230), "urlap-cim-kompakt")
        fm3.selectedType = .meeting; fm3.workplace = "Győr"
        shot(AnyView(StopwatchView().environmentObject(fm3).environment(\.palette, .blue).frame(width: 440).padding(14)), NSSize(width: 470, height: 230), "idozito-kezdes")
        fm3.plannedStart = Date().addingTimeInterval(-600)
        shot(AnyView(StopwatchView().environmentObject(fm3).environment(\.palette, .blue).environment(\.compact, true).frame(width: 340).padding(8)), NSSize(width: 360, height: 210), "idozito-kezdes-kompakt")
        fm3.plannedStart = nil
    }
    ud3.removeObject(forKey: "draft.departure"); ud3.removeObject(forKey: "draft.destination")
    ud3.set(tmp + "/data/bejegyzesek.csv", forKey: "dataFile")
}

// MARK: Kézi felvitel az OTS-be (1.3.1)

section("Kézi felvitel: Munkajelentő")
do {
    let after = d(2026, 11, 2)
    func hhmm(_ day: String, _ h: Int, _ min: Int = 0) -> Date { Fmt.dayFormatter.date(from: day)!.addingTimeInterval(Double(h * 3600 + min * 60)) }
    func tEntry(_ type: ActivityType, secs: Int = 0, q: Int? = nil, date: String, place: String = "Győr", h: Int = 8, dep: String? = nil, arr: String? = nil, act: String = "x") -> Entry {
        var e = entry(type, secs: secs, q: q, date: date, place: place, act: act)
        e.start = hhmm(date, h); e.end = hhmm(date, h).addingTimeInterval(Double(secs)); e.departure = dep; e.arrival = arr
        return e
    }
    func row(_ day: Date, _ list: [Entry], rules: Bool = false) -> OTSWorkRow { OTSManual.workRow(day: day, entries: list, rules: rules, today: after) }

    // pomodoro: a pomók összege kerekítődik, nem külön-külön (4 × 25 perc = 100 perc → 2 óra)
    let pomos = (0..<4).map { tEntry(.preparing, secs: 1500, date: "2026-10-05", h: 8 + $0) }
    check("pomodoro: a napi összeg kerekítődik felfelé", row(d(2026, 10, 5), pomos).values[ActivityType.preparing.code] == 2)
    check("kerek óra nem nő", row(d(2026, 10, 5), [tEntry(.meeting, secs: 7200, date: "2026-10-05")]).values[ActivityType.meeting.code] == 2)
    let mixed = [tEntry(.meeting, secs: 5 * 3600, date: "2026-10-05"), tEntry(.missionVisiting, q: 2, date: "2026-10-05", h: 14), tEntry(.preaching, q: 1, date: "2026-10-05", h: 16), tEntry(.preaching, q: 2, date: "2026-10-05", h: 17)]
    let rm = row(d(2026, 10, 5), mixed, rules: true)
    check("alkalom és fő összeadódik", rm.values[ActivityType.preaching.code] == 3 && rm.values[ActivityType.missionVisiting.code] == 2 && rm.values[ActivityType.meeting.code] == 5)
    check("10 szám: nincs kiegészítés és nincs !!!", rm.values[ActivityType.officeWork.code] == nil && !rm.workplace.hasPrefix("!!!"))
    // a sorokat a skill nem egészíti ki 8 órára (sem szabályokkal, sem nélkülük)
    let short = [tEntry(.meeting, secs: 3 * 3600, date: "2026-10-05")]
    check("szabályok nélkül nincs kiegészítés", row(d(2026, 10, 5), short).values == [ActivityType.meeting.code: 3] && row(d(2026, 10, 5), short).workplace == "Győr")
    let rf = row(d(2026, 10, 5), short, rules: true)
    check("bekapcsolt jelölésnél sincs 8-ra kiegészítés és !!! előtag", rf.values == [ActivityType.meeting.code: 3] && rf.workplace == "Győr", "\(rf.values) \(rf.workplace)")
    let rsat = row(d(2026, 10, 10), [tEntry(.preaching, q: 1, date: "2026-10-10")], rules: true)
    check("szombaton egyetlen bejegyzés is elég, kiegészítés nélkül", rsat.values == [ActivityType.preaching.code: 1] && rsat.workplace == "Győr")
    let rcap = row(d(2026, 10, 5), [tEntry(.meeting, secs: 10 * 3600, date: "2026-10-05")])
    check("legfeljebb 8", rcap.values[ActivityType.meeting.code] == 8 && !rcap.notes.isEmpty)
    // üres napok
    check("üres nap szabályok nélkül üres", row(d(2026, 10, 6), []).isEmpty)
    check("üres hétköznap: !!!", row(d(2026, 10, 6), [], rules: true).workplace == "!!!")
    check("üres szombat: !!!", row(d(2026, 10, 10), [], rules: true).workplace == "!!!")
    check("üres vasárnap: !!! (nem magától szabadnap)", row(d(2026, 10, 11), [], rules: true).workplace == "!!!")
    check("vasárnap Szabadnap bejegyzéssel: SZABADNAP", row(d(2026, 10, 11), [tEntry(.dayOff, date: "2026-10-11")], rules: true).workplace == "SZABADNAP")
    check("jövőbeli nap üres szabályokkal is", OTSManual.workRow(day: d(2026, 11, 5), entries: [], rules: true, today: d(2026, 11, 2)).isEmpty)
    // egész napos
    check("szabadnap", row(d(2026, 10, 6), [entry(.dayOff, date: "2026-10-06")], rules: true).workplace == "SZABADNAP")
    check("munkaszüneti nap", row(d(2026, 10, 6), [entry(.publicHoliday, date: "2026-10-06")], rules: true).workplace == "MUNKASZÜNETI NAP")
    let rh = row(d(2026, 10, 6), [entry(.holiday, date: "2026-10-06")], rules: true)
    check("szabadság: pipa, semmi más", rh.holiday && rh.workplace.isEmpty && rh.values.isEmpty)
    // saját kategória
    let rc = row(d(2026, 10, 6), [tEntry(custom, secs: 3600, date: "2026-10-06")])
    check("saját kategória nem kerül az OTS-sorba", rc.values.isEmpty && !rc.hasData && rc.workplace.isEmpty && !rc.notes.isEmpty)
    // munkahely lista
    let places = OTSManual.workplaceList([
        tEntry(.meeting, secs: 3600, date: "2026-10-05", place: "Tata", h: 13),
        tEntry(.travel, secs: 3600, date: "2026-10-05", place: "Győr, tata, Tatabánya", h: 9, dep: "Győr", arr: "Győr"),
        tEntry(.preparing, secs: 3600, date: "2026-10-05", place: "Győr", h: 15)])
    check("munkahely: időrend, ismétlődés nélkül", places == ["Győr", "tata", "Tatabánya"], "\(places)")
    // jövő nélkül és hónapok
    for y in 2024...2035 {
        for mo in 1...12 {
            let days = OTSManual.monthDays(year: y, month: mo)
            let expected = [31, (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][mo - 1]
            if days.count != expected || !days.allSatisfy({ DateUtil.components($0).month == mo }) { check("hónap \(y)-\(mo) napjai", false, "\(days.count) != \(expected)") }
        }
    }
    check("érvénytelen hónap nem omlik össze", OTSManual.monthDays(year: 2026, month: 13).isEmpty && OTSManual.monthDays(year: 0, month: 0).isEmpty)
    check("hónap léptetése évhatáron", OTSManual.previousMonth(year: 2027, month: 1) == (2026, 12) && OTSManual.nextMonth(year: 2026, month: 12) == (2027, 1))
}

section("Kézi felvitel: Költségelszámolás")
do {
    func tv(_ date: String, place: String, dep: String?, arr: String?, h: Int, act: String = "Út") -> Entry {
        var e = entry(.travel, secs: 3600, date: date, place: place, act: act)
        e.departure = dep; e.arrival = arr
        e.start = Fmt.dayFormatter.date(from: date)!.addingTimeInterval(Double(h * 3600)); e.end = e.start?.addingTimeInterval(3600)
        return e
    }
    func at(_ date: String, _ h: Int, _ place: String, _ act: String) -> Entry {
        var e = entry(.meeting, secs: 3600, date: date, place: place, act: act)
        e.start = Fmt.dayFormatter.date(from: date)!.addingTimeInterval(Double(h * 3600)); e.end = e.start?.addingTimeInterval(3600)
        return e
    }
    let list = [
        tv("2026-10-05", place: "Tata, Tatabánya", dep: "Győr", arr: "Győr", h: 8),
        at("2026-10-05", 10, "Tata", "Értekezlet a csapattal"),
        at("2026-10-05", 12, "Mór", "Nem útvonalbeli"),
        tv("2026-10-07", place: "Győr", dep: "Győr", arr: "", h: 8, act: "Helyben"),
        tv("2026-10-08", place: "Tata", dep: "", arr: "", h: 8, act: "Reggel"),
        tv("2026-10-08", place: "Mór", dep: "Győr", arr: "Győr", h: 15, act: "Délután"),
        tv("2026-11-03", place: "Pápa", dep: "Győr", arr: "Győr", h: 8)
    ]
    let rows = OTSManual.costRows(entries: list, year: 2026, month: 10, home: "Győr")
    check("költség: csak a hónap utazásai, utanként egy sor (a napon belüli több út külön sor)", rows.map { $0.rowKey } == ["2026-10-05#0", "2026-10-07#0", "2026-10-08#0", "2026-10-08#1"], "\(rows.map { $0.rowKey })")
    check("útvonal: Indulás - Munkahelyek - Érkezés", rows.first?.route == "Győr - Tata - Tatabánya - Győr", rows.first?.route ?? "")
    check("tevékenység: kizárólag az Utazás bejegyzésé (más kategóriából nem veszünk át)", rows.first?.activity == "Út", rows.first?.activity ?? "")
    check("azonos szomszédos pontok összevonva", rows[1].points == ["Győr"], rows[1].route)
    check("üres indulás/érkezés: székhely", rows[2].points == ["Győr", "Tata", "Győr"], "\(rows[2].points)")
    check("több út egy napon: külön sor, saját útvonallal és tevékenységgel", rows[2].multiple && rows[3].multiple && rows[2].route == "Győr - Tata - Győr" && rows[3].route == "Győr - Mór - Győr" && rows[2].activity == "Reggel" && rows[3].activity == "Délután" && !rows[0].multiple, "\(rows.map { $0.route })")
    // km-állások a sorban
    var kmTrip = tv("2026-10-20", place: "Tata", dep: "Győr", arr: "Győr", h: 8, act: "Km")
    kmTrip.startKm = 1000; kmTrip.endKm = 1060
    var kmHalf = tv("2026-10-21", place: "Mór", dep: "Győr", arr: "Győr", h: 8, act: "Fél")
    kmHalf.startKm = 2000
    let kmRows = OTSManual.costRows(entries: [kmTrip, kmHalf, tv("2026-10-22", place: "Pápa", dep: "Győr", arr: "Győr", h: 8)], year: 2026, month: 10, home: "Győr")
    check("költség: a km-állások a sorban, az út hossza számolva", kmRows[0].startKm == 1000 && kmRows[0].endKm == 1060 && kmRows[0].kmDriven == 60)
    check("költség: részleges vagy hiányzó állásból nincs út-hossz", kmRows[1].startKm == 2000 && kmRows[1].endKm == nil && kmRows[1].kmDriven == nil && kmRows[2].startKm == nil && kmRows[2].kmDriven == nil)
    check("költség: a km megváltozása megváltoztatja az aláírást (a pipa érvénytelenné válik)", kmRows[0].signature != { () -> String in var c = kmRows[0]; c.endKm = 1070; return c.signature }())
    check("Google Maps hivatkozás sorrendben, kódolva", OTSManual.mapsURL(["Győr", "Tatabánya", "Győr"])?.absoluteString == "https://www.google.com/maps/dir/Gy%C5%91r/Tatab%C3%A1nya/Gy%C5%91r")
    check("Google Maps: egy pontból nincs útvonal", OTSManual.mapsURL(["Győr"]) == nil)
    check("üres hónap", OTSManual.costRows(entries: list, year: 2026, month: 9, home: "Győr").isEmpty)
    // oda-vissza út: Érkezés = Indulás
    let rt = tv("2026-10-09", place: "Tata", dep: "Győr", arr: "Győr", h: 8, act: "Oda-vissza")
    check("oda-vissza útvonal: A - B - A", OTSManual.routePoints(rt, home: "Győr") == ["Győr", "Tata", "Győr"])
    let rt2 = tv("2026-10-09", place: "Tata, Tatabánya", dep: "Mór", arr: "Mór", h: 8)
    check("oda-vissza több úticéllal", OTSManual.routePoints(rt2, home: "Győr") == ["Mór", "Tata", "Tatabánya", "Mór"])
    let onlyOther = [at("2026-10-12", 10, "Győr", "Csak értekezlet")]
    check("tevékenység nélküli utazás mellett sem kerül át más tevékenység", OTSManual.costRows(entries: [tv("2026-10-12", place: "Tata", dep: "Győr", arr: "Győr", h: 8, act: "")] + onlyOther, year: 2026, month: 10, home: "Győr").first?.activity == "")
}

section("Kézi felvitel: Létszámjelentő")
do {
    var r1 = AttendanceReport(date: "2026-10-10", congregation: "Győr"); r1.worship = AttendanceCounts(children: 1, adults: 30, guests: 4)
    var r2 = AttendanceReport(date: "2026-10-17", congregation: "Győr")
    let rows = OTSManual.attendanceRows(reports: [r1, r2], congregations: ["Győr", "Tata"], year: 2026, month: 10)
    check("esedékes nap × gyülekezet, hiányzó is látszik", rows.map { "\($0.key)|\($0.congregation)|\($0.report != nil)" } == ["2026-10-10|Győr|true", "2026-10-10|Tata|false", "2026-10-17|Győr|true", "2026-10-17|Tata|false"], "\(rows.map { $0.key + $0.congregation })")
    check("nem esedékes hónap üres", OTSManual.attendanceRows(reports: [], congregations: ["Győr"], year: 2026, month: 9).isEmpty)
    for y in 2024...2035 { for mo in 1...12 { _ = OTSManual.attendanceRows(reports: [], congregations: ["A"], year: y, month: mo) } }
    check("minden hónapra lefut", true)
}

section("Űrlap: kötelező mezők")
do {
    let fm = AppModel()
    fm.clearDraft()
    fm.selectedType = .meeting; fm.workplace = "Győr"; fm.activity = ""
    check("nem utazásnál a tevékenység opcionális", fm.missingFieldsHint == nil && fm.fieldsComplete)
    fm.workplace = ""
    check("a munkahely továbbra is kötelező", fm.missingFieldsHint != nil && !fm.fieldsComplete)
    fm.selectedType = .holiday
    check("egész napos típusnál csak a típus kell", fm.fieldsComplete)
    fm.selectedType = .travel; fm.destination = "Tata"; fm.departure = "Győr"; fm.activity = ""
    check("utazásnál a tevékenység kötelező", !fm.fieldsComplete && (fm.missingFieldsHint ?? "").contains("Tevékenység"))
    fm.activity = "Hittan"
    check("utazás teljes (Kiindulás, Cél, Tevékenység)", fm.fieldsComplete)
    fm.destination = ""
    check("utazásnál a Cél kötelező", !fm.fieldsComplete && (fm.missingFieldsHint ?? "").contains("Cél"))
    fm.clearDraft()
}

section("Kategóriák színei")
do {
    check("hex oda-vissza", CategoryColors.hex(of: CategoryColors.color(hex: "#3366CC") ?? .black) == "#3366CC")
    check("hibás hex nil", CategoryColors.color(hex: "zzz") == nil && CategoryColors.color(hex: "#12345") == nil && CategoryColors.color(hex: "") == nil)
    let cm = AppModel()
    check("alapérték nem módosított", !CategoryColors.isCustomized(ActivityType.meeting.code))
    cm.setCategoryColor(ActivityType.meeting.code, hex: "#FF0000")
    check("szín beállítva", CategoryColors.isCustomized(ActivityType.meeting.code) && CategoryColors.hex(of: CategoryColors.color(code: ActivityType.meeting.code)) == "#FF0000")
    check("szín mentve a beállításokba", (UserDefaults.standard.dictionary(forKey: "categoryColors") as? [String: String])?[ActivityType.meeting.code] == "#FF0000")
    cm.setCategoryColor(ActivityType.meeting.code, hex: "rossz")
    check("hibás szín az alapértéket állítja vissza", !CategoryColors.isCustomized(ActivityType.meeting.code))
    check("ismeretlen kód nem omlik össze", CategoryColors.hex(of: CategoryColors.color(code: "NINCS_ILYEN")) != nil)
    check("a színminták érvényes hex-értékek, ismétlődés nélkül", SettingsView.swatches.allSatisfy { CategoryColors.color(hex: $0) != nil } && Set(SettingsView.swatches).count == SettingsView.swatches.count)
    cm.setCategoryColor(ActivityType.meeting.code, hex: SettingsView.swatches[0])
    check("színminta kiválasztása elmentődik", CategoryColors.hex(of: CategoryColors.color(code: ActivityType.meeting.code)) == SettingsView.swatches[0])
    UserDefaults.standard.removeObject(forKey: "categoryColors")
    CategoryColors.overrides = [:]
}

section("Pipák")
do {
    let suite = UserDefaults(suiteName: "ots-selftest-checklist") ?? .standard
    suite.removePersistentDomain(forName: "ots-selftest-checklist")
    let c = OTSChecklist(defaults: suite)
    check("kezdetben nincs pipa", !c.isDone("w|2026-10-05", "a"))
    c.set("w|2026-10-05", "a", done: true)
    check("pipa megvan", c.isDone("w|2026-10-05", "a"))
    check("megváltozott tartalomnál a pipa érvényét veszti", !c.isDone("w|2026-10-05", "b"))
    check("megmarad újratöltés után", OTSChecklist(defaults: suite).isDone("w|2026-10-05", "a"))
    c.set("w|2026-10-05", "a", done: false)
    check("törölhető", !c.isDone("w|2026-10-05", "a"))
    suite.removePersistentDomain(forName: "ots-selftest-checklist")
}

section("Kézi felvitel ablak (felület)")
do {
    let om = AppModel()
    om.addAttendanceCongregation("Győr")
    for i in 0..<12 {
        om.workplace = "Győr"; om.activity = "Munka \(i)"; om.selectedType = [ActivityType.meeting, .preparing, .visiting, .travel][i % 4]
        if om.selectedType?.isTravel == true { om.departure = "Győr"; om.destination = "Tata, Tatabánya" }
        om.quantity = 2
        let st = DateUtil.addDays(Date(), -(i % 5 + 1)).addingTimeInterval(Double(8 * 3600))
        om.add(om.makeEntry(start: st, end: st.addingTimeInterval(3600), source: "manual")); om.clearDraft()
    }
    let ud = UserDefaults.standard
    let hosting = NSHostingController(rootView: OTSManualView().environmentObject(om))
    hosting.sizingOptions = []
    let win = NSWindow(contentViewController: hosting)
    win.setContentSize(NSSize(width: 900, height: 600))
    win.makeKeyAndOrderFront(nil)
    for ds in OTSDataset.allCases {
        for vm in OTSViewMode.allCases {
            for rules in [false, true] {
                for ws in [1, 2] {
                    ud.set(ds.rawValue, forKey: "ots.dataset"); ud.set(vm.rawValue, forKey: "ots.viewMode"); ud.set(rules, forKey: "ots.rules"); ud.set(ws, forKey: "cal.weekStart")
                    RunLoop.current.run(until: Date().addingTimeInterval(0.04))
                }
            }
        }
    }
    check("az összes nézet (3 adat × 3 mód × szabály × hétkezdet) összeomlás nélkül kirajzolódik", true)
    check("az ablak mérete nem változott a tartalomtól", abs(win.contentRect(forFrameRect: win.frame).height - 600) < 1)
    for k in ["ots.dataset", "ots.viewMode", "ots.rules", "cal.weekStart", "ots.done"] { ud.removeObject(forKey: k) }
    win.orderOut(nil)
}

// MARK: Felületi terhelés (összeomlás és ablakmagasság)

section("Felületi terhelés")
do {
    let ud = UserDefaults.standard
    ud.set(true, forKey: "attendance.enabled")
    ud.set("light", forKey: "appearance")
    let sm = AppModel()
    sm.addAttendanceCongregation("Győr"); sm.addAttendanceCongregation("Tata"); sm.addAttendanceCongregation("Tatabánya"); sm.addAttendanceCongregation("Mór")
    // sok bejegyzés ma, hogy a napi lista hosszú legyen; régebbi nap nincs, így az emlékeztető sáv is látszik, ha a ma üres
    for i in 0..<40 {
        sm.workplace = "Győr"; sm.activity = "Hosszú leírás a \(i). feladatról, ami több sorba is törhet, mert elég részletes szöveg"; sm.selectedType = .preparing
        let st = DateUtil.addDays(Date(), -9).addingTimeInterval(Double(6 * 3600 + i * 600))
        sm.add(sm.makeEntry(start: st, end: st.addingTimeInterval(300), source: "manual")); sm.clearDraft()
    }
    let maxH = ContentView.maxContentHeight
    let hosting = NSHostingController(rootView: ContentView().environmentObject(sm))
    hosting.sizingOptions = [.preferredContentSize]
    let win = NSPanel(contentViewController: hosting)
    win.styleMask = [.borderless, .nonactivatingPanel]
    win.makeKeyAndOrderFront(nil)
    func pump(_ t: Double) { RunLoop.current.run(until: Date().addingTimeInterval(t)) }
    func h() -> CGFloat { win.contentRect(forFrameRect: win.frame).height }
    pump(0.5)
    check("a menüablak a képernyőn belül marad indulásnál", h() > 100 && h() <= maxH + 1, "\(Int(h())) <= \(Int(maxH))")

    let pastDue = AttendanceSchedule.dueDates(from: DateUtil.addDays(Date(), -200), to: DateUtil.addDays(Date(), -1)).last ?? DateUtil.addDays(Date(), -7)
    var worst: CGFloat = 0
    for round in 0..<4 {
        ud.set(round % 2 == 0, forKey: "compact")
        ud.set(round % 2 == 0 ? "dark" : "light", forKey: "appearance")
        ud.set(Palette.all[round % Palette.all.count].id, forKey: "palette")
        ud.set([6, 7, 0, 3][round], forKey: "cal.startHour"); ud.set([19, 20, 24, 5][round], forKey: "cal.endHour")
        ud.set(round % 2 == 0 ? 1 : 2, forKey: "cal.weekStart")
        for day in [Date(), pastDue, DateUtil.addDays(Date(), -9)] {
            sm.selectedDay = day
            for mode in Mode.allCases {
                sm.mode = mode
                sm.pomoSettingsOpen = (mode == .pomodoro) && round % 2 == 1
                sm.pendingSlot = (mode == .calendar && round % 2 == 1) ? AppModel.PendingSlot(day: DateUtil.startOfDay(Date()), startMin: 8 * 60, endMin: 9 * 60) : nil
                pump(0.08)
                worst = max(worst, h())
                if h() > maxH + 1 { check("magasság a korláton belül (kör \(round), \(mode.rawValue))", false, "\(Int(h())) > \(Int(maxH))") }
            }
        }
    }
    sm.pendingSlot = nil; sm.pomoSettingsOpen = false
    // leválasztott ablak: szélesség és magasság változtatása közben sem omlik össze, és az ablak mérete a felhasználóé marad
    do {
        let dh = NSHostingController(rootView: ContentView(detached: true).environmentObject(sm))
        dh.sizingOptions = []
        let dw = NSWindow(contentViewController: dh)
        dw.makeKeyAndOrderFront(nil)
        var ok = true
        for size in [NSSize(width: 440, height: 700), NSSize(width: 900, height: 700), NSSize(width: 520, height: 400), NSSize(width: 760, height: 780), NSSize(width: 440, height: 300), NSSize(width: 340, height: 600)] {
            for mode in Mode.allCases {
                sm.mode = mode
                dw.setContentSize(size)
                pump(0.05)
                let now = dw.contentRect(forFrameRect: dw.frame).size
                if abs(now.width - size.width) > 1 || abs(now.height - size.height) > 1 { ok = false }
            }
        }
        check("a leválasztott ablak átméretezés közben stabil, mérete nem a tartalomtól függ", ok)
        dw.orderOut(nil)
    }
    check("a lapok, napok, módok és színsémák váltogatása után sincs összeomlás", true, "legmagasabb: \(Int(worst)) / \(Int(maxH))")
    check("a menüablak sosem magasabb a képernyőnél", worst <= maxH + 1)
    for k in ["compact", "appearance", "palette", "cal.startHour", "cal.endHour", "cal.weekStart", "attendance.enabled"] { ud.removeObject(forKey: k) }
    AppearanceManager.apply()
    win.orderOut(nil)
}

// MARK: Kilométeróra (1.6.0)

section("Kilométeróra: mezők, ellenőrzés, javítás, havi összeg")
do {
    // értelmezés
    check("km: üres rendben", AppModel.kmValue("") == (nil, true) && AppModel.kmValue("  ") == (nil, true))
    check("km: szám, szóközzel is", AppModel.kmValue("123456").value == 123456 && AppModel.kmValue("123 456").value == 123456)
    check("km: hibás értékek érvénytelenek, nem omlanak össze", ["abc", "-5", "1e99", "inf", "nan", "99999999"].allSatisfy { !AppModel.kmValue($0).valid })
    // ellenőrzés
    check("km: rendben ha érkező > induló", AppModel.kmProblem(start: 100, end: 150, previous: 100) == nil)
    check("km: érkező = induló hibás", AppModel.kmProblem(start: 100, end: 100, previous: nil) != nil)
    check("km: érkező < induló hibás", AppModel.kmProblem(start: 100, end: 90, previous: nil) != nil)
    check("km: induló kisebb az előző végénél hibás", AppModel.kmProblem(start: 90, end: nil, previous: 100) != nil)
    check("km: csak érkező, az előző végénél nem nagyobb: hibás", AppModel.kmProblem(start: nil, end: 100, previous: 100) != nil)
    check("km: egyik mező sem kötelező", AppModel.kmProblem(start: nil, end: nil, previous: 100) == nil && AppModel.kmProblem(start: 120, end: nil, previous: 100) == nil)

    let kdir = tmp + "/km"
    try? FileManager.default.removeItem(atPath: kdir)
    let ukm = UserDefaults.standard
    ukm.set(kdir + "/bejegyzesek.csv", forKey: "dataFile")
    ukm.set("Győr", forKey: "home")
    for k in ["draft.departure", "draft.destination"] { ukm.removeObject(forKey: k) }
    let km = AppModel()
    km.clearDraft()
    km.selectedType = .travel
    km.activity = "Kiszállás"
    km.departure = "Győr"; km.destination = "Tata"
    let t0 = Date().addingTimeInterval(-7200)
    func rec(_ s: String, _ e: String, at: Date) -> Entry {
        km.startKmText = s; km.endKmText = e
        let en = km.makeEntry(start: at, end: at.addingTimeInterval(1800), source: "manual")
        km.add(en)
        km.clearDraft()
        km.selectedType = .travel; km.activity = "Kiszállás"; km.departure = "Győr"; km.destination = "Tata"
        return en
    }
    check("km: üresen is rögzíthető", km.fieldsComplete && km.startKmText == "")
    let first = rec("", "", at: t0)
    check("km: üres mezőkkel nincs km a bejegyzésben", first.startKm == nil && first.endKm == nil && km.lastEndKm == nil)
    let a = rec("1000", "1060", at: t0.addingTimeInterval(-86400 * 2))
    check("km: a bejegyzés tárolja az állásokat és az út hosszát", a.startKm == 1000 && a.endKm == 1060 && a.kmDriven == 60)
    check("km: rögzítés után az induló az előző végállással előtöltve, az érkező üres", km.startKmText == "1060" && km.endKmText == "")
    km.selectedType = .travel; km.activity = "Kiszállás"; km.departure = "Győr"; km.destination = "Tata"
    km.startKmText = "1000"
    check("km: az előző végállásnál kisebb induló blokkolja a rögzítést", km.missingFieldsHint?.contains("kisebb") == true && !km.fieldsComplete)
    km.startKmText = "1060"; km.endKmText = "1050"
    check("km: az induló alatti érkező blokkolja a rögzítést", km.missingFieldsHint?.contains("nagyobb") == true)
    km.startKmText = "12a"
    check("km: nem szám blokkolja a rögzítést", km.missingFieldsHint?.contains("egész szám") == true)
    km.startKmText = "1060"; km.endKmText = "1100"
    check("km: helyes értékekkel rögzíthető", km.fieldsComplete)
    let b = rec("1060", "1100", at: t0.addingTimeInterval(-86400))
    // nem utazás nem viszi a km-et
    km.selectedType = .meeting; km.workplace = "Győr"; km.startKmText = "5"; km.endKmText = "9"
    let nonTravel = km.makeEntry(start: t0, end: t0.addingTimeInterval(600), source: "manual")
    check("km: nem Utazás bejegyzés nem kap km-et", nonTravel.startKm == nil && nonTravel.endKm == nil)
    km.clearDraft()

    // havi összeg: csak a két állással rögzített utak
    check("km: havi összeg és hiányzó állások", { () -> Bool in
        let r = km.monthKm(containing: Date())
        let sameMonth = [a, b, first].filter { $0.date.prefix(7) == ymd(Date()).prefix(7) }
        let want = sameMonth.compactMap { $0.kmDriven }.reduce(0, +)
        return r.km == want && r.incomplete == sameMonth.filter { $0.kmDriven == nil }.count
    }())

    // javítás
    check("km: javítás érvényes értékkel", km.updateKm(b.id, start: "1060", end: "1110") == nil && km.entries.first { $0.id == b.id }?.endKm == 1110)
    check("km: javítás hibás értékkel nem módosít", km.updateKm(b.id, start: "1060", end: "1000") != nil && km.entries.first { $0.id == b.id }?.endKm == 1110)
    check("km: javítás az előző végénél kisebb indulóval hibás", km.updateKm(b.id, start: "900", end: "1110") != nil)
    check("km: javítás üresre törli az állásokat", km.updateKm(first.id, start: "", end: "") == nil)
    check("km: javítás nem létező bejegyzésre hibát ad", km.updateKm(UUID(), start: "1", end: "2") != nil)
    // mentés és visszaolvasás, a régi (22 oszlop előtti) fájl is olvasható
    let reread = AppModel()
    check("km: az állások a CSV-ből visszaolvashatók", reread.entries.first { $0.id == b.id }?.startKm == 1060 && reread.entries.first { $0.id == b.id }?.endKm == 1110)
    let oldCSV = "Azonosító;Dátum;Típus kód;Típus;Egység;Munkahely;Tevékenység\r\n;2026-05-04;MEETING;Megbeszélés;ora;Győr;x\r\n"
    check("km: régi, km-oszlop nélküli fájl olvasható", ((try? CSV.decode(Data(oldCSV.utf8)))?.entries.first).map { $0.startKm == nil && $0.endKm == nil } == true)
    check("km: a CSV fejlécében a két új oszlop a végén áll", CSV.columns.suffix(2) == ["Induló km", "Érkező km"] && CSV.columns.count == 22)
    let badCSV = "Dátum;Típus kód;Induló km;Érkező km\r\n2026-05-04;TRAVEL;abc;-4\r\n"
    check("km: hibás km a CSV-ben üres lesz, a sor megmarad", ((try? CSV.decode(Data(badCSV.utf8)))?.entries.first).map { $0.startKm == nil && $0.endKm == nil } == true)
    ukm.removeObject(forKey: "home")
}

// MARK: Javaslat a Munkahely mezőben (valódi űrlap): a lista a lejjebb lévő mezők fölött van, és kattintásra elfogadja a javaslatot

section("Javaslat a Munkahely mezőben (valódi űrlap)")
do {
    let ud = UserDefaults.standard
    ud.removeObject(forKey: "suggest.enabled")
    let dir = tmp + "/munkahely-javaslat"
    try? FileManager.default.removeItem(atPath: dir)
    ud.set(dir + "/bejegyzesek.csv", forKey: "dataFile")
    let fm = AppModel()
    var seed = Entry(id: UUID(), date: "2026-05-04", start: nil, end: nil, durationSeconds: 3600, workplace: "Győr", type: ActivityType.meeting.code, typeLabel: ActivityType.meeting.label, unit: Unit.hours.rawValue, quantity: nil, activity: "", source: "manual")
    fm.add(seed)
    seed.id = UUID(); seed.workplace = "Győrszentiván"; fm.add(seed)
    fm.selectedType = .meeting
    fm.workplace = ""
    fm.activity = ""
    func textFields(_ v: NSView) -> [NSTextField] {
        var r: [NSTextField] = []
        if let t = v as? NSTextField, t.isEditable { r.append(t) }
        for s in v.subviews { r += textFields(s) }
        return r
    }
    let h = NSHostingController(rootView: FieldsView().padding(14).frame(width: 440).environmentObject(fm).environment(\.palette, .blue).environment(\.compact, false))
    h.sizingOptions = []
    let w = NSWindow(contentViewController: h)
    w.appearance = NSAppearance(named: .aqua); w.backgroundColor = .white
    w.setContentSize(NSSize(width: 440, height: 360))
    w.makeKeyAndOrderFront(nil)
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    let fields = textFields(w.contentView!).sorted { $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY }
    if let first = fields.first {
        w.makeFirstResponder(first)
        fm.workplace = "gy"
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        if let out = ProcessInfo.processInfo.environment["OTS_RENDER_DIR"], let cv = w.contentView, let rep = cv.bitmapImageRepForCachingDisplay(in: cv.bounds) {
            cv.cacheDisplay(in: cv.bounds, to: rep)
            try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out + "/munkahely-javaslat.png"))
        }
        // az első javaslat sora: a mező alsó széle alatt (ablak-koordináta, bal alsó origó)
        let f = first.convert(first.bounds, to: nil)
        let p = NSPoint(x: f.minX + 40, y: f.minY - 2 - 3 - 11)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let ev = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { w.sendEvent(ev) }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        check("Munkahely: a javaslatra kattintva a mező a javaslatot kapja (nem marad üres, nem a lejjebb lévő mező kapja a kattintást)", fm.workplace == "Győr" || fm.workplace == "Győrszentiván", "\(fm.workplace)")
        check("Munkahely: a lejjebb lévő Tevékenység mező érintetlen", fm.activity == "")
    } else {
        check("Munkahely: az űrlap szövegmezői megtalálhatók", false)
    }
    w.orderOut(nil)
}

print(failures == 0 ? "MINDEN TESZT RENDBEN (\(total) ellenőrzés)" : "HIBÁK: \(failures) / \(total)")
exit(failures == 0 ? 0 : 1)
