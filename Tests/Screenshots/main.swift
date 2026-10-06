import SwiftUI
import AppKit

// Képernyőképek a használati útmutatóhoz (kitalált példaadatokkal). A scripts/screenshots.sh futtatja.

let out = ProcessInfo.processInfo.environment["OTS_SHOTS_OUT"] ?? NSTemporaryDirectory() + "ots-shots"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let support = ProcessInfo.processInfo.environment["OTS_SUPPORT_DIR"] ?? NSTemporaryDirectory() + "ots-support"
let ud = UserDefaults.standard
for k in ud.dictionaryRepresentation().keys { ud.removeObject(forKey: k) }
ud.set(support + "/data/bejegyzesek.csv", forKey: "dataFile")
ud.set("Székesfehérvár", forKey: "home")
ud.set(true, forKey: "attendance.enabled")
ud.set(6, forKey: "cal.startHour")
ud.set(19, forKey: "cal.endHour")
_ = NSApplication.shared
NSApplication.shared.setActivationPolicy(.accessory)

let cal = DateUtil.gregorian
func at(_ daysAgo: Int, _ h: Int, _ min: Int) -> Date {
    let base = DateUtil.addDays(Date(), -daysAgo)
    return cal.date(bySettingHour: h, minute: min, second: 0, of: base) ?? base
}

let m = AppModel()
m.addAttendanceCongregation("Székesfehérvár")
m.addAttendanceCongregation("Mór")
m.addAttendanceCongregation("Bicske")

func add(_ place: String, _ act: String, _ t: ActivityType, _ day: Int, _ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int, q: Int = 1, dep: String? = nil, arr: String? = nil) {
    m.workplace = place; m.activity = act; m.selectedType = t; m.quantity = q
    // Utazásnál az 1.5.0 óta Kiindulás és Cél van (a Munkahely a Cél); az `arr` egyirányú útnál a Cél utolsó helye lenne, itt oda-vissza út
    if t.isTravel { m.departure = dep ?? m.departure; m.destination = place; m.roundTrip = true; _ = arr }
    m.add(m.makeEntry(start: at(day, h1, m1), end: at(day, h2, m2), source: "manual")); m.clearDraft()
}

// 1) A hosszú kihagyás jelzéséhez: csak régi (9+ napos) bejegyzések
add("Székesfehérvár", "Heti megbeszélés", .meeting, 12, 9, 0, 11, 0)
add("Mór", "Prédikáció írása", .preparing, 11, 9, 0, 12, 0)
add("Székesfehérvár", "Számlák rendezése", .officeWork, 10, 8, 30, 10, 30)

func shot(_ name: String, _ view: AnyView, size: NSSize? = nil, dark: Bool = false) {
    ud.set(dark ? "dark" : "light", forKey: "appearance")
    AppearanceManager.apply()
    let framed = view
        .environmentObject(m)
        .environment(\.palette, Palette.byID(ud.string(forKey: "palette") ?? "blue"))
        .background(Color(nsColor: .windowBackgroundColor))
    let host = NSHostingView(rootView: framed)
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let s = size ?? host.fittingSize
    host.frame = NSRect(origin: .zero, size: s)
    let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    win.appearance = host.appearance
    win.contentView = host; win.orderFrontRegardless(); host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: rep)
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
        print("kép:", name, s)
    }
}

// Emlékeztető + hiányos/kitöltetlen napok
m.mode = .timer
ud.set("30", forKey: "missing.lookback")
shot("10-emlekezteto", AnyView(ContentView()))

// 2) Friss bejegyzések
add("Székesfehérvár", "Heti munkatársi megbeszélés", .meeting, 0, 9, 0, 10, 30)
add("Mór", "Prédikáció írása", .preparing, 0, 11, 0, 13, 0)
add("Mór", "Látogatás: idősek otthona", .missionVisiting, 0, 14, 0, 15, 0, q: 3)
add("Székesfehérvár", "Számlák rendezése", .officeWork, 1, 8, 30, 11, 30)
add("Bicske", "Bibliakör", .evangelisation, 1, 18, 0, 19, 30)
add("Tata, Mór", "Kiszállás", .travel, 2, 7, 30, 8, 15, dep: "Székesfehérvár", arr: "Székesfehérvár")
add("Mór", "Istentisztelet", .preaching, 2, 10, 0, 12, 0)
add("Székesfehérvár", "Konferencia-előkészítés", .preparing, 3, 6, 30, 12, 0)
add("Székesfehérvár", "Havi jelentés", .administration, 3, 13, 0, 15, 0)
add("Székesfehérvár", "Esti ima", .meeting, 3, 20, 0, 21, 0)
m.selectedDay = Date()

ud.set("30", forKey: "missing.lookback")
m.mode = .timer
m.workplace = "Székesfehérvár"; m.selectedType = .preparing; m.activity = "Prédikáció előkészítése"
shot("01-idozito", AnyView(ContentView()))
m.mode = .manual
shot("02-kezi-bevitel", AnyView(ContentView()))
m.mode = .pomodoro
m.startPomodoro()
shot("03-pomodoro", AnyView(ContentView()))
m.pomoSettingsOpen = true
shot("04-pomodoro-beallitasok", AnyView(ContentView()))
m.pomoSettingsOpen = false
m.discardPomodoro()

// Utazás három mezővel
m.mode = .timer
m.selectedType = .travel
m.workplace = "Tata, Mór"; m.activity = "Kiszállás a környékre"
shot("08-utazas", AnyView(ContentView()))
m.clearDraft()

// Naptár: a 6–19 sáv, a sávon kívüli (20:00) bejegyzés jelzésével
m.mode = .calendar
shot("05-naptar", AnyView(ContentView()))
m.pendingSlot = AppModel.PendingSlot(day: DateUtil.startOfDay(Date()), startMin: 15 * 60, endMin: 16 * 60 + 30)
shot("06-naptar-uj", AnyView(ContentView()))
m.pendingSlot = nil

// Létszámjelentő egy múltbeli esedékes szombaton
let past = AttendanceSchedule.dueDates(from: DateUtil.addDays(Date(), -200), to: DateUtil.addDays(Date(), -1)).last ?? DateUtil.addDays(Date(), -7)
m.selectedDay = past
m.mode = .timer
shot("09-letszamjelentes", AnyView(ContentView()))
m.selectedDay = Date()

// Kompakt nézet és sötét mód
ud.set(true, forKey: "compact")
shot("07-kompakt", AnyView(ContentView()))
for id in ["blue", "green", "purple", "amber"] {
    ud.set(id, forKey: "palette")
    shot("15-szinseme-\(id)", AnyView(ContentView()))
}
ud.set("blue", forKey: "palette")
ud.set(false, forKey: "compact")
m.mode = .timer
m.workplace = "Székesfehérvár"; m.selectedType = .preparing; m.activity = "Prédikáció előkészítése"
shot("13-sotet-mod", AnyView(ContentView()), dark: true)
m.mode = .calendar
shot("14-sotet-naptar", AnyView(ContentView()), dark: true)
ud.set("light", forKey: "appearance")

// Beállítások és ikonok
struct IconRow: View {
    let title: String; let choices: [IconChoice]; let time: String?
    var body: some View {
        HStack(spacing: 14) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            ForEach(choices) { c in
                HStack(spacing: 3) { IconView(choice: c); if let t = time { Text(t).monospacedDigit() } }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
            }
            Spacer()
        }
    }
}
struct IconsOverview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            IconRow(title: "Alap ikon", choices: IconSets.main, time: nil)
            IconRow(title: "Időzítő fut", choices: [IconSets.main[5]], time: "00:42:10")
            IconRow(title: "Pomo közben", choices: IconSets.pomoWork, time: "18:05")
            IconRow(title: "Szünet közben", choices: IconSets.pomoBreak, time: "04:12")
            IconRow(title: "Emlékeztető", choices: IconSets.reminder, time: nil)
        }.padding(14).frame(width: 640)
    }
}
shot("11-menusor-ikonok", AnyView(IconsOverview()))
ud.set(true, forKey: "reminder.enabled")
shot("12-beallitasok", AnyView(ScrollView { SettingsView(showAllTabs: true).padding(14).frame(width: 440) }.frame(width: 440, height: 2800)), size: NSSize(width: 440, height: 2800))

// Skill-telepítő lépései
let inst = SkillInstaller(model: m)
inst.userName = "Kovács János"; inst.home = "Székesfehérvár"; inst.congregations = "Székesfehérvár, Mór, Bicske"
inst.selectedTargets = [.claude, .antigravity]; inst.site = .tet
for (n, s) in [("16-skill-1-attekintes", SkillInstaller.Step.intro), ("17-skill-2-cel", .target), ("18-skill-3-feladatok", .tasks),
               ("19-skill-4-adatok", .details), ("20-skill-5-telepites", .review)] {
    inst.step = s
    shot(n, AnyView(SkillInstallerView(installer: inst)), size: NSSize(width: 580, height: 640))
}
// Kézi felvitel az OTS-be
m.setCategoryColor(ActivityType.preparing.code, hex: "#B5483A")
m.addCustomCategory(name: "Magánügy", unit: .hours)
add("Székesfehérvár", "Saját ügy", ActivityType.lookup(label: "Magánügy") ?? .meeting, 4, 16, 0, 17, 0)
let pastReport = AttendanceReport(date: Fmt.dayFormatter.string(from: past), congregation: "Székesfehérvár",
                                  sabbathSchool: AttendanceCounts(children: 3, adults: 21, guests: 2), worship: AttendanceCounts(children: 4, adults: 32, guests: 6))
m.saveReports(day: past, reports: [pastReport])
let pc = DateUtil.components(past)
let thisMonth = DateUtil.components(Date())
func otsShot(_ name: String, _ dataset: OTSDataset, _ mode: OTSViewMode, rules: Bool = false, attendance: Bool = false, dark: Bool = false) {
    ud.set(dataset.rawValue, forKey: "ots.dataset"); ud.set(mode.rawValue, forKey: "ots.viewMode"); ud.set(rules, forKey: "ots.rules")
    let start = attendance ? (pc.year, pc.month) : (thisMonth.year, thisMonth.month)
    shot(name, AnyView(OTSManualView(initialMonth: start)), size: NSSize(width: 1020, height: 640), dark: dark)
}
otsShot("21-kezi-munkajelento-tabla", .work, .table, rules: true)
otsShot("22-kezi-munkajelento-lista", .work, .list)
otsShot("23-kezi-munkajelento-naptar", .work, .calendar)
otsShot("24-kezi-koltseg", .cost, .table)
otsShot("25-kezi-letszam", .attendance, .table, attendance: true)
otsShot("26-kezi-sotet", .work, .calendar, dark: true)
shot("27-szinek-beallitas", AnyView(SettingsView(showAllTabs: true).padding(14).frame(width: 440)), size: NSSize(width: 440, height: 760))
print("kész")
