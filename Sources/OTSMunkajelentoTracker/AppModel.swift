import SwiftUI
import Combine
import AppKit
import UserNotifications

enum PomoPhase {
    case idle, work, shortBreak, longBreak
}

final class AppModel: ObservableObject {
    static let appName = "OTS Munkajelentő Tracker"
    static let defaultWorkplaces: [String] = []

    // MARK: Közös űrlapmezők (mindhárom módhoz)
    @Published var workplace: String { didSet { ud.set(workplace, forKey: "draft.workplace") } }
    /// A kiválasztott típus; üres, amíg a felhasználó nem választ.
    @Published var selectedType: ActivityType? {
        didSet {
            ud.set(selectedType?.code ?? "", forKey: "draft.type")
            if type.hasQuantity == false { quantity = 1 }
            if selectedType?.isTravel == true {
                if departure.isEmpty { departure = homePlace }
            }
        }
    }
    /// A logika számára mindig van típus (üres választásnál az alapértelmezett).
    var type: ActivityType {
        get { selectedType ?? .meeting }
        set { selectedType = newValue }
    }

    // MARK: Helyszínek és kategóriák (szerkeszthető listák)
    @Published private(set) var places: [String] = []
    @Published private(set) var customCategories: [CustomCategory] = []
    @Published private(set) var categoryColors: [String: String] = [:]
    @Published private(set) var hiddenTypeCodes: Set<String> = []
    @Published var activity: String { didSet { ud.set(activity, forKey: "draft.activity") } }
    /// Utazásnál: honnan indult / hová érkezett (a `workplace` ilyenkor a Munkahely(ek) listája).
    @Published var departure: String { didSet { ud.set(departure, forKey: "draft.departure") } }
    /// Utazásnál a Cél: egy vagy több hely, vesszővel elválasztva, akár pontos címmel is (Tata, Fő út 1., Mór).
    @Published var destination: String { didSet { ud.set(destination, forKey: "draft.destination") } }
    @Published var quantity: Int { didSet { ud.set(quantity, forKey: "draft.quantity") } }
    /// Utazásnál: oda-vissza út (a munka után visszatértem a Kiindulásra). Alapból bejelölt; minden rögzítés után újra az.
    @Published var roundTrip = true
    /// Utazásnál: igaz, ha a Kiindulás volt a munkahely, hamis, ha a Cél (alapból a Cél).
    @Published var workplaceIsDeparture = false
    /// Utazásnál (opcionális): a kilométeróra állása az út elején és végén (szövegként, ahogy a mezőbe írták).
    @Published var startKmText = ""
    @Published var endKmText = ""

    // MARK: Gyülekezeti létszámjelentő
    @Published var attendance: [AttendanceReport] = []
    /// A regisztrált gyülekezetek (sorrendben).
    @Published var attendanceCongregations: [String] = []
    var attendanceLastModified: Date?
    var attendanceFileURL: URL { dataFileURL.deletingLastPathComponent().appendingPathComponent("letszamjelentesek.csv") }

    // MARK: Felület állapota
    @Published var mode: Mode = .timer
    /// Nyitva van-e a Pomodoro-beállítások panel (ilyenkor a napi lista és a hiányzó napok rejtve vannak, hogy az ablak ne nőjön túl magasra).
    @Published var pomoSettingsOpen = false
    /// A napi lista és a Kézi bevitel közös napja.
    @Published var selectedDay = Date()

    // MARK: Naptár
    struct PendingSlot: Equatable {
        var day: Date
        var startMin: Int
        var endMin: Int
    }
    /// A Naptárban kijelölt, még nem rögzített idősáv.
    @Published var pendingSlot: PendingSlot?

    // MARK: Adatok
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var dataFileURL: URL
    @Published var lastError: String?

    // MARK: Időzítő
    @Published var now = Date()
    /// Az Időzítő előre megadott kezdése (nil: most indul).
    @Published var plannedStart: Date?
    @Published private(set) var timerStart: Date? {
        didSet { ud.set(timerStart?.timeIntervalSince1970 ?? 0, forKey: "timer.start") }
    }

    // MARK: Pomodoro
    @Published private(set) var pomoPhase: PomoPhase = .idle
    @Published private(set) var pomoPhaseEnd = Date()
    @Published private(set) var pomoDone = 0
    private var pomoPhaseStart = Date()

    let ud = UserDefaults.standard
    /// Igaz, ha az alkalmazás által telepített skill régebbi, mint az alkalmazásba csomagolt (a fejlécben jelzés, egy kattintással frissíthető).
    @Published private(set) var skillUpdateAvailable = false
    /// A legutóbbi skill-frissítés eredménye (a Beállítások › Skill részben látszik).
    @Published var skillUpdateMessage: String?
    /// A naptár-szinkron (Mac Naptár, EventKit); csak használatkor jön létre.
    lazy var calendarSync = CalendarSyncer(model: self, source: EventKitCalendarSource())
    private var ticker: AnyCancellable?
    private var terminateObserver: NSObjectProtocol?
    private var keyObserver: NSObjectProtocol?
    private var appearanceObserver: NSObjectProtocol?
    private var lastModified: Date?
    /// Igaz, ha az utolsó beolvasáskor sorokat kellett kihagyni: mentés előtt biztonsági másolat készül a fájlról.
    private var needsBackupBeforeSave = false

    // MARK: Fájlhelyek
    static var supportDir: URL {
        // Tesztekhez: az OTS_SUPPORT_DIR környezeti változóval a valódi adatmappa érintetlen marad.
        if let o = ProcessInfo.processInfo.environment["OTS_SUPPORT_DIR"] { return URL(fileURLWithPath: o, isDirectory: true) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support", isDirectory: true)
        return base.appendingPathComponent(appName, isDirectory: true)
    }
    static var defaultDataFile: URL { supportDir.appendingPathComponent("bejegyzesek.csv") }
    static var pointerFile: URL { supportDir.appendingPathComponent("beallitasok.json") }

    init() {
        ud.register(defaults: [
            "pomo.work": 25, "pomo.short": 5, "pomo.long": 15, "pomo.every": 4,
            "pomo.autoBreak": true, "pomo.autoWork": false,
            "draft.quantity": 1,
            "missing.lookback": "thisMonth",
            "sound.pomoEnd": "Glass", "sound.breakEnd": "Ping",
            "menuIcon": "adventist", "menuIcon.reminder": "warning",
            "cal.startHour": 7, "cal.endHour": 20, "cal.weekStart": 2,
            "target.hours": 8,
            "reminder.enabled": true, "reminder.days": 7,
            "attendance.enabled": false,
            "suggest.enabled": true,
            "palette": "blue", "appearance": "system"
        ])
        workplace = ud.string(forKey: "draft.workplace") ?? ""
        selectedType = nil
        activity = ud.string(forKey: "draft.activity") ?? ""
        departure = ud.string(forKey: "draft.departure") ?? ""
        destination = ud.string(forKey: "draft.destination") ?? ""
        quantity = max(1, ud.integer(forKey: "draft.quantity"))
        if let path = ud.string(forKey: "dataFile"), !path.isEmpty {
            var url = URL(fileURLWithPath: path)
            if url.pathExtension.lowercased() == "json" {
                url = url.deletingPathExtension().appendingPathExtension("csv")
                ud.set(url.path, forKey: "dataFile")
            }
            dataFileURL = url
        } else {
            dataFileURL = Self.defaultDataFile
        }
        loadLists()
        loadAttendanceCongregations()
        if let t = ActivityType.lookup(code: ud.string(forKey: "draft.type") ?? ""),
           ActivityType.all.contains(t) { selectedType = t }
        let t = ud.double(forKey: "timer.start")
        timerStart = t > 0 ? Date(timeIntervalSince1970: t) : nil

        try? FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        loadFromDisk()
        loadAttendanceFromDisk()
        seedPlacesIfNeeded()
        AppearanceManager.apply()
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { _ in AppearanceManager.apply() }
        writePointer()
        requestNotificationPermission()

        ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.tick()
        }
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.reloadIfChanged(); self?.reloadAttendanceIfChanged(); self?.calendarSyncIfEnabled(); self?.refreshSkillUpdate() }
        StatusMenuController.shared.install(model: self)
        DispatchQueue.main.async { [weak self] in self?.refreshSkillUpdate() }
        if ud.bool(forKey: "ekcal.enabled") {
            DispatchQueue.main.async { [weak self] in
                self?.calendarSync.startObserving()
                self?.calendarSync.sync()
            }
        }
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.handleTerminate() }
    }

    /// Az ablak előtérbe kerülésekor (és induláskor) szinkronizál, ha a naptár-szinkron be van kapcsolva.
    /// Megnézi, hogy a gépre telepített skill elavult-e a csomagolthoz képest; ha új változat jött, egyszer értesítést is küld.
    func refreshSkillUpdate() {
        let installer = SkillInstaller(model: self)
        let outdated = installer.bundledAvailable && installer.status.values.contains(.outdated)
        skillUpdateAvailable = outdated
        if !outdated { skillUpdateMessage = skillUpdateMessage }   // az utolsó eredmény megmarad
        guard outdated, let fp = installer.bundledFingerprint(), ud.string(forKey: "skill.notifiedFingerprint") != fp else { return }
        ud.set(fp, forKey: "skill.notifiedFingerprint")
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }   // tesztben nincs értesítés
        notify(title: "Frissült az OTS Adminisztráció skill",
               body: "A gépeden régebbi változat van. Egy kattintással frissítheted: a fejlécben a frissítés gomb, vagy Beállítások › Skill.",
               soundKey: "sound.breakEnd")
    }

    /// Az elavult skill frissítése a korábbi telepítés beállításaival (másolat készül a régiről). Az eredmény szövegét adja vissza.
    @discardableResult
    func updateSkill() -> String {
        let installer = SkillInstaller(model: self)
        let outcome = installer.updateOutdated()
        skillUpdateMessage = outcome.message
        refreshSkillUpdate()
        return outcome.message
    }

    func calendarSyncIfEnabled() {
        guard ud.bool(forKey: "ekcal.enabled") else { return }
        calendarSync.startObserving()
        calendarSync.syncIfStale()
    }

    // MARK: Ellenőrzés
    var trimmedWorkplace: String { workplace.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedActivity: String { activity.trimmingCharacters(in: .whitespacesAndNewlines) }

    var trimmedDeparture: String { departure.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// A Munkahely(ek) mező elemei (vesszővel elválasztva), üres elemek nélkül.
    var workplaceList: [String] {
        workplace.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    /// A székhely (az Utazás Indulás/Érkezés alapértéke).
    var homePlace: String { (ud.string(forKey: "home") ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Típus és Munkahely kötelező (a nem munkaidős, egész napos típusoknál csak a típus). A Tevékenység csak az Utazásnál kötelező
    /// (a Költségelszámolás táblázatba kell), máshol opcionális. Utazásnál az Indulás, a Munkahely(ek) és az Érkezés is kötelező
    /// (oda-vissza útnál az Érkezés az Indulás).
    var fieldsComplete: Bool { missingFieldsHint == nil && selectedType != nil }

    /// Az Utazás összeállított útvonala a bejegyzéshez: a Kiindulás (egy hely) és a Cél (egy vagy több hely, akár pontos címmel).
    struct TravelPlan: Equatable {
        var origin: CalendarParser.ParsedPlace
        var stops: [CalendarParser.ParsedPlace]
    }

    var travelPlan: TravelPlan? {
        guard let o = CalendarParser.parsePlace(departure), let stops = CalendarParser.parsePlaces(destination) else { return nil }
        return TravelPlan(origin: o, stops: stops)
    }

    var trimmedDestination: String { destination.trimmingCharacters(in: .whitespacesAndNewlines) }

    var missingFieldsHint: String? {
        if selectedType == nil { return "Válassz tevékenység-típust." }
        if type.isWholeDay { return nil }
        if type.isTravel {
            var missing: [String] = []
            if trimmedDeparture.isEmpty { missing.append("Kiindulás") }
            if trimmedDestination.isEmpty { missing.append("Cél") }
            if trimmedActivity.isEmpty { missing.append("Tevékenység") }
            if !missing.isEmpty { return "Kötelező mező: " + missing.joined(separator: ", ") + "." }
            if CalendarParser.parsePlace(departure) == nil { return "Kiindulás: egy hely, település vagy település és cím (például Győr, Fő út 1.)." }
            if CalendarParser.parsePlaces(destination) == nil { return "Cél: települések vesszővel, címmel is (például Tata, Fő út 1., Mór)." }
            return kmHint
        }
        if trimmedWorkplace.isEmpty { return "A Munkahely mező kötelező." }
        return nil
    }

    /// Az űrlap kiürítése (egy bejegyzés rögzítése után).
    func clearDraft() {
        workplace = ""
        activity = ""
        departure = ""
        destination = ""
        roundTrip = true
        workplaceIsDeparture = false
        quantity = 1
        selectedType = nil
        endKmText = ""
        startKmText = lastEndKm.map(String.init) ?? ""
    }

    // MARK: Jövőbeli napok tiltása
    func isFuture(_ day: Date) -> Bool {
        let cal = Calendar.current
        return cal.startOfDay(for: day) > cal.startOfDay(for: Date())
    }

    var workplaceSuggestions: [String] { places }

    /// A Tevékenység mező javaslatai: a korábban rögzített tevékenységek (legutóbbiak elöl, az éppen kiválasztott típusúak előbb).
    func activitySuggestions() -> [String] {
        var seen = Set<String>(), same: [String] = [], other: [String] = []
        for e in entries.reversed() {
            let a = e.activity.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !a.isEmpty, seen.insert(CalendarParser.fold(a)).inserted else { continue }
            if let t = selectedType, e.type == t.rawValue { same.append(a) } else { other.append(a) }
            if seen.count >= 300 { break }
        }
        return same + other
    }

    // MARK: Helyszínek
    private static let wholeDayNames: Set<String> = ["SZABADNAP", "SZABADSÁG", "MUNKASZÜNETI NAP"]

    private func loadLists() {
        if let saved = ud.array(forKey: "places") as? [String] { places = saved }
        if let data = ud.data(forKey: "customCategories"),
           let list = try? JSONDecoder().decode([CustomCategory].self, from: data) { customCategories = list }
        hiddenTypeCodes = Set(ud.stringArray(forKey: "hiddenTypes") ?? [])
        categoryColors = (ud.dictionary(forKey: "categoryColors") as? [String: String]) ?? [:]
        syncRegistry()
    }

    private func syncRegistry() {
        ActivityType.custom = customCategories.map { $0.activityType }
        ActivityType.hidden = hiddenTypeCodes
        CategoryColors.overrides = categoryColors
    }

    /// Egy kategória színe (nil = az alapértelmezett szín visszaállítása).
    func setCategoryColor(_ code: String, hex: String?) {
        if let hex = hex, CategoryColors.color(hex: hex) != nil { categoryColors[code] = hex } else { categoryColors[code] = nil }
        ud.set(categoryColors, forKey: "categoryColors")
        syncRegistry()
        objectWillChange.send()
    }

    /// Első induláskor (vagy a lista hiányában) az alapértelmezett és a már használt helyszínekkel tölti fel.
    private func seedPlacesIfNeeded() {
        guard ud.object(forKey: "places") == nil else { return }
        var list = Self.defaultWorkplaces
        for e in entries.sorted(by: { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }) {
            let w = e.workplace.trimmingCharacters(in: .whitespaces)
            if !w.isEmpty, !Self.wholeDayNames.contains(w.uppercased()),
               !list.contains(where: { $0.caseInsensitiveCompare(w) == .orderedSame }) { list.append(w) }
        }
        setPlaces(list)
    }

    private func setPlaces(_ list: [String]) {
        places = list
        ud.set(list, forKey: "places")
    }

    func addPlace(_ name: String) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !places.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else { return }
        setPlaces(places + [t])
    }

    func removePlace(_ name: String) {
        setPlaces(places.filter { $0 != name })
    }

    // MARK: Kategóriák
    func addCustomCategory(name: String, unit: Unit) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, unit != .wholeDay else { return }
        let slug = t.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "hu_HU"))
            .uppercased().map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        var code = ActivityType.customPrefix + slug
        var n = 2
        while ActivityType.lookup(code: code) != nil || customCategories.contains(where: { $0.code == code }) {
            code = ActivityType.customPrefix + slug + "_\(n)"; n += 1
        }
        let raw = unit == .people ? "people" : (unit == .occasions ? "occasions" : "hours")
        saveCategories(customCategories + [CustomCategory(code: code, label: t, unit: raw)])
    }

    func renameCustomCategory(code: String, to name: String) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = customCategories.firstIndex(where: { $0.code == code }) else { return }
        var list = customCategories
        list[i].label = t
        saveCategories(list)
    }

    func removeCustomCategory(code: String) {
        saveCategories(customCategories.filter { $0.code != code })
        if selectedType?.code == code { selectedType = nil }
    }

    private func saveCategories(_ list: [CustomCategory]) {
        customCategories = list
        if let data = try? JSONEncoder().encode(list) { ud.set(data, forKey: "customCategories") }
        syncRegistry()
        objectWillChange.send()
    }

    func setBuiltinHidden(_ code: String, hidden: Bool) {
        if hidden { hiddenTypeCodes.insert(code) } else { hiddenTypeCodes.remove(code) }
        ud.set(Array(hiddenTypeCodes), forKey: "hiddenTypes")
        syncRegistry()
        if hidden, selectedType?.code == code { selectedType = nil }
        objectWillChange.send()
    }

    // MARK: Időzítő
    var stopwatchRunning: Bool { timerStart != nil }
    var pomodoroActive: Bool { pomoPhase != .idle }
    var stopwatchElapsed: Int { Int(now.timeIntervalSince(timerStart ?? now)) }
    var pomoRemaining: Int { max(0, Int(pomoPhaseEnd.timeIntervalSince(now).rounded(.up))) }

    /// Az Időzítő kezdése: ha előre megadtál korábbi kezdést (`plannedStart`), onnantól számol; különben most indul.
    func startStopwatch() {
        guard !pomodoroActive, timerStart == nil, fieldsComplete, !type.isWholeDay else { return }
        now = Date()
        timerStart = Self.clampedStart(plannedStart ?? now, now: now)
        plannedStart = nil
    }

    /// A kezdés a mai nap 0:00 és a mostani pillanat közé szorítva (jövőbeli kezdés nem lehet; a korábbi napra csak a futó időzítő nyúlhat át).
    static func clampedStart(_ d: Date, now: Date, notBefore: Date? = nil) -> Date {
        let lower = notBefore ?? DateUtil.startOfDay(now)
        return max(lower, min(d, now))
    }

    /// A futó időzítő kezdésének korrigálása (például már öt perce dolgozol, de csak most indítottad): onnantól számol.
    /// Legfeljebb az eredeti kezdés napjának elejéig, és legkésőbb most.
    func setTimerStart(_ d: Date) {
        guard let current = timerStart else { return }
        now = Date()
        timerStart = Self.clampedStart(d, now: now, notBefore: DateUtil.startOfDay(current))
    }

    func stopStopwatch() {
        guard let start = timerStart else { return }
        let end = Date()
        guard fieldsComplete else { return }
        add(makeEntry(start: start, end: end, source: "timer"))
        timerStart = nil
        plannedStart = nil
        clearDraft()
    }

    func discardStopwatch() {
        timerStart = nil
        clearDraft()
    }

    // MARK: Pomodoro
    private func pomoMinutes(_ key: String) -> Int { max(1, ud.integer(forKey: key)) }

    func startPomodoro() {
        guard timerStart == nil, fieldsComplete, !type.isWholeDay else { return }
        beginPhase(.work)
    }

    /// Leállítás: a félbehagyott pomo eltelt ideje is bekerül a naplóba (30 másodperc alatt nem, azt véletlen kattintásnak vesszük).
    func stopPomodoro() {
        if pomoPhase == .work {
            let end = Date()
            if end.timeIntervalSince(pomoPhaseStart) >= 30, fieldsComplete {
                add(makeEntry(start: pomoPhaseStart, end: end, source: "pomodoro"))
            }
        }
        clearDraft()
        pomoPhase = .idle
        now = Date()
    }

    func discardPomodoro() {
        pomoPhase = .idle
        now = Date()
        clearDraft()
    }

    func skipPomodoroBreak() {
        guard pomoPhase == .shortBreak || pomoPhase == .longBreak else { return }
        pomoPhase = .idle
        if ud.bool(forKey: "pomo.autoWork") { beginPhase(.work) }
    }

    func resetPomodoroCounter() { pomoDone = 0 }

    private func beginPhase(_ phase: PomoPhase) {
        let minutes: Int
        switch phase {
        case .work: minutes = pomoMinutes("pomo.work")
        case .shortBreak: minutes = pomoMinutes("pomo.short")
        case .longBreak: minutes = pomoMinutes("pomo.long")
        case .idle: return
        }
        let start = Date()
        now = start
        pomoPhaseStart = start
        pomoPhaseEnd = start.addingTimeInterval(TimeInterval(minutes * 60))
        pomoPhase = phase
    }

    private func pomoPhaseFinished() {
        let finished = pomoPhase
        if finished == .work {
            if fieldsComplete {
                add(makeEntry(start: pomoPhaseStart, end: pomoPhaseEnd, source: "pomodoro"))
            }
            pomoDone += 1
            let every = pomoMinutes("pomo.every")
            let nextBreak: PomoPhase = (pomoDone % every == 0) ? .longBreak : .shortBreak
            notify(title: "Pomo vége", body: nextBreak == .longBreak ? "Hosszú szünet jön." : "Rövid szünet jön.", soundKey: "sound.pomoEnd")
            if ud.bool(forKey: "pomo.autoBreak") {
                beginPhase(nextBreak)
            } else {
                pomoPhase = .idle
            }
        } else {
            notify(title: "A szünet véget ért", body: "Mehet a következő pomo.", soundKey: "sound.breakEnd")
            if ud.bool(forKey: "pomo.autoWork") {
                beginPhase(.work)
            } else {
                pomoPhase = .idle
            }
        }
    }

    private var lastDayKey = ""

    private func tick() {
        // Napváltáskor frissülnek a napi jelzések (kitöltetlen napok, emlékeztető ikon).
        let key = Fmt.dayFormatter.string(from: Date())
        if key != lastDayKey {
            if !lastDayKey.isEmpty { objectWillChange.send() }
            lastDayKey = key
        }
        guard timerStart != nil || pomoPhase != .idle else { return }
        now = Date()
        if pomoPhase != .idle, now >= pomoPhaseEnd {
            pomoPhaseFinished()
        }
    }

    /// A menüsorban látszó idő: futó időzítőnél az eltelt idő, Pomodoro közben (ha be van kapcsolva) a hátralévő idő; egyébként nil.
    var menuClockText: String? {
        if stopwatchRunning { return Fmt.clock(stopwatchElapsed) }
        let showPomo = (ud.object(forKey: "menu.showPomoTime") as? Bool) ?? true
        if pomodoroActive && showPomo { return Fmt.clock(pomoRemaining) }
        return nil
    }

    private func handleTerminate() {
        // A futó Pomodoro-pomo ne vesszen el kilépéskor. Az időzítő állapota
        // magától megmarad (timer.start), és induláskor folytatódik.
        if pomoPhase == .work { stopPomodoro() }
    }

    // MARK: Bejegyzések
    func makeEntry(start: Date, end: Date, source: String) -> Entry {
        let duration = max(0, Int(end.timeIntervalSince(start).rounded()))
        return Entry(
            id: UUID(),
            date: Fmt.dayFormatter.string(from: start),
            start: start,
            end: end,
            durationSeconds: duration,
            workplace: entryWorkplace,
            type: type.rawValue,
            typeLabel: type.label,
            unit: type.unit.rawValue,
            quantity: type.hasQuantity ? quantity : nil,
            activity: trimmedActivity,
            source: source,
            departure: travelFields?.departure,
            arrival: travelFields?.arrival,
            address: travelFields?.stopAddresses,
            departureAddress: travelFields?.departureAddress,
            arrivalAddress: travelFields?.arrivalAddress,
            workplaceIsDeparture: type.isTravel && workplaceIsDeparture,
            startKm: type.isTravel ? Self.kmValue(startKmText).value : nil,
            endKm: type.isTravel ? Self.kmValue(endKmText).value : nil
        )
    }

    /// Az Utazás mezői a bejegyzéshez; nil, ha nem Utazás.
    /// Az útvonal: Kiindulás - Cél(ok) [- Kiindulás, ha oda-vissza]. A CSV-ben: `Indulás` = Kiindulás, `Munkahely` = a Cél helyei (ez az útvonal
    /// köztes pontjai), `Érkezés` = oda-vissza útnál a Kiindulás, egyirányú útnál a Cél utolsó helye (az összevonás miatt egyetlen pont marad),
    /// így a skill és a webapp változtatás nélkül a helyes útvonalat kapja. Ha a Kiindulás volt a munkahely, a `Munkahely helye` oszlop jelzi.
    private var travelFields: (departure: String, arrival: String, workplace: String, departureAddress: String?, arrivalAddress: String?, stopAddresses: String?)? {
        guard type.isTravel else { return nil }
        guard let p = travelPlan, let last = p.stops.last else { return (trimmedDeparture, trimmedDeparture, trimmedDestination, nil, nil, nil) }
        let addresses = p.stops.compactMap { $0.address }
        return (p.origin.settlement,
                roundTrip ? p.origin.settlement : last.settlement,
                p.stops.map { $0.settlement }.joined(separator: ", "),
                p.origin.address,
                roundTrip ? p.origin.address : nil,
                addresses.isEmpty ? nil : addresses.joined(separator: " - "))
    }

    /// A bejegyzésbe kerülő Munkahely: utazásnál a Cél helyei (települések, vesszővel).
    private var entryWorkplace: String {
        type.isTravel ? (travelFields?.workplace ?? "") : trimmedWorkplace
    }

    /// Kézi bevitel időpont nélkül: óraszámmal (óra típusoknál), vagy csak mennyiséggel (alkalom, fő).
    func makeManualEntry(day: Date, durationSeconds: Int) -> Entry {
        Entry(
            id: UUID(),
            date: Fmt.dayFormatter.string(from: day),
            start: nil, end: nil,
            durationSeconds: type.unit == .hours ? durationSeconds : 0,
            workplace: entryWorkplace,
            type: type.rawValue,
            typeLabel: type.label,
            unit: type.unit.rawValue,
            quantity: type.hasQuantity ? quantity : nil,
            activity: trimmedActivity,
            source: "manual",
            departure: travelFields?.departure,
            arrival: travelFields?.arrival,
            address: travelFields?.stopAddresses,
            departureAddress: travelFields?.departureAddress,
            arrivalAddress: travelFields?.arrivalAddress,
            workplaceIsDeparture: type.isTravel && workplaceIsDeparture,
            startKm: type.isTravel ? Self.kmValue(startKmText).value : nil,
            endKm: type.isTravel ? Self.kmValue(endKmText).value : nil
        )
    }

    func makeWholeDayEntry(day: Date) -> Entry { Self.wholeDayEntry(day: day, type: type, activity: trimmedActivity) }

    /// Egész napos bejegyzés (Szabadság, Szabadnap, Munkaszüneti nap) a megadott típussal.
    static func wholeDayEntry(day: Date, type: ActivityType, activity: String) -> Entry {
        Entry(
            id: UUID(),
            date: Fmt.dayFormatter.string(from: day),
            start: nil, end: nil, durationSeconds: 0,
            workplace: type.shortLabel.uppercased(),
            type: type.rawValue,
            typeLabel: type.label,
            unit: Unit.wholeDay.rawValue,
            quantity: nil,
            activity: activity,
            source: "manual"
        )
    }

    // MARK: Szabadnap egy kattintással és a havi korlát

    /// Rövid tájékoztató vagy figyelmeztetés a felületnek (például „3 vasárnap szabadnapnak jelölve”, vagy a havi korlát átlépése).
    @Published var notice: String?
    private var noticeToken = 0

    func showNotice(_ text: String?) {
        notice = text
        noticeToken += 1
        let token = noticeToken
        guard text != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            if let self = self, self.noticeToken == token { self.notice = nil }
        }
    }

    /// Egy üres nap Szabadnapnak jelölése. Nem jelöl jövőbeli napot, olyan napot, amelyen már van bejegyzés, és kétszer sem ugyanazt a napot.
    /// Hibánál (és a havi korlát átlépésekor) a `notice`-ban és a `lastError`-ban jelez; igazat ad vissza, ha megtörtént a jelölés.
    @discardableResult
    func markDayOff(_ day: Date) -> Bool {
        guard !isFuture(day) else { lastError = "Jövőbeli napot nem lehet szabadnapnak jelölni."; return false }
        guard entries(on: day).isEmpty else { lastError = "Ezen a napon már van bejegyzés, ezért nem jelölöm szabadnapnak."; return false }
        add(Self.wholeDayEntry(day: day, type: .dayOff, activity: ""))
        return true
    }

    /// A kitöltetlen vasárnapok (a megadott visszatekintésben) Szabadnapnak jelölése. Visszaadja, hányat jelölt meg.
    @discardableResult
    func markEmptySundaysAsDayOff(lookback: String) -> Int {
        let sundays = missingDays(lookback: lookback).filter { DateUtil.isSunday($0) }
        var count = 0
        for d in sundays where markDayOff(d) { count += 1 }
        if count > 0 {
            let limit = notice.map { $0.hasPrefix("Figyelem") ? " " + $0 : "" } ?? ""
            showNotice("\(count) vasárnap szabadnapnak jelölve." + limit)
        }
        return count
    }

    /// A havi korlát ellenőrzése egy új egész napos bejegyzés után: legfeljebb annyi SZABADNAP és annyi MUNKASZÜNETI NAP lehet egy hónapban,
    /// ahány hétből áll a hónap (az OTS lezárás előtt ezt ellenőrzi). Figyelmeztetés a `notice`-ban; nem akadályozza a rögzítést.
    private func checkMonthlyLimit(after entry: Entry) {
        guard entry.type == ActivityType.dayOff.code || entry.type == ActivityType.publicHoliday.code,
              let d = Fmt.dayFormatter.date(from: entry.date) else { return }
        let c = DateUtil.components(d)
        let prefix = String(format: "%04d-%02d-", c.year, c.month)
        let count = entries.filter { $0.type == entry.type && $0.date.hasPrefix(prefix) }.count
        let limit = Insights.weeksInMonth(year: c.year, month: c.month)
        guard count > limit else { return }
        let name = entry.type == ActivityType.dayOff.code ? "szabadnap" : "munkaszüneti nap"
        showNotice("Figyelem: ebben a hónapban \(count) \(name) van, az OTS legfeljebb \(limit)-t enged (a hónap heteinek száma). A hónap lezárása előtt javítani kell.")
    }

    func commitPending() {
        guard let slot = pendingSlot, fieldsComplete else { return }
        guard !isFuture(slot.day) else {
            lastError = "Jövőbeli napra nem lehet bejegyzést felvenni."
            return
        }
        let cal = Calendar.current
        if type.isWholeDay {
            if entries(on: slot.day).contains(where: { $0.type == type.rawValue }) {
                lastError = "Erre a napra már van ilyen bejegyzés."
                return
            }
            add(makeWholeDayEntry(day: slot.day))
        } else if let s = cal.date(byAdding: .minute, value: slot.startMin, to: slot.day),
                  let e = cal.date(byAdding: .minute, value: slot.endMin, to: slot.day) {
            guard e <= Date() else {
                lastError = "Jövőbeli időpontra nem lehet bejegyzést felvenni."
                return
            }
            add(makeEntry(start: s, end: e, source: "calendar"))
        }
        pendingSlot = nil
        clearDraft()
        if lastError == "Erre a napra már van ilyen bejegyzés." { lastError = nil }
    }

    func add(_ entry: Entry) {
        if entry.activityType?.isWholeDay != true {
            for p in entry.workplace.split(separator: ",") { addPlace(String(p)) }
            if let d = entry.departure { addPlace(d) }
            if let a = entry.arrival { addPlace(a) }
        }
        entries.append(entry)
        entries.sort { sortKey($0) < sortKey($1) }
        save()
        checkMonthlyLimit(after: entry)
    }

    /// A `i`. bejegyzés km-állásának beállítása és mentése (az ellenőrzés az `updateKm`-ben történik).
    func setKm(at i: Int, start: Int?, end: Int?) {
        guard entries.indices.contains(i) else { return }
        entries[i].startKm = start
        entries[i].endKm = end
        save()
    }

    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    /// Naptár-szinkron: hozzáadás, frissítés (azonos azonosítóval) és törlés egyetlen mentéssel.
    /// A változtatás előtt másolat készül az adatfájlról (`bejegyzesek.naptar-elotti.csv`, a következő szinkron felülírja);
    /// ha a másolat nem készül el, a módosítás elmarad.
    @discardableResult
    func applyCalendarChanges(add: [Entry], update: [Entry], delete: Set<UUID>) -> Bool {
        guard !add.isEmpty || !update.isEmpty || !delete.isEmpty else { return true }
        let fm = FileManager.default
        if fm.fileExists(atPath: dataFileURL.path) {
            let backup = dataFileURL.deletingLastPathComponent().appendingPathComponent("bejegyzesek.naptar-elotti.csv")
            do {
                try? fm.removeItem(at: backup)
                try fm.copyItem(at: dataFileURL, to: backup)
            } catch {
                lastError = "A naptár-szinkron előtti másolat nem készült el, ezért nem módosítottam az adatokat: \(error.localizedDescription)"
                return false
            }
        }
        let updates = Dictionary(update.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        var result = entries.filter { !delete.contains($0.id) }.map { updates[$0.id] ?? $0 }
        result.append(contentsOf: add)
        for e in update + add where e.activityType?.isWholeDay != true {
            for p in e.workplace.split(separator: ",") { addPlace(String(p)) }
            if let d = e.departure { addPlace(d) }
            if let a = e.arrival { addPlace(a) }
        }
        entries = result.sorted { sortKey($0) < sortKey($1) }
        save()
        return lastError?.hasPrefix("Mentési hiba") != true
    }

    private func sortKey(_ e: Entry) -> String {
        let t = e.start.map { Fmt.isoWithOffset.string(from: $0) } ?? "\(e.date)T00:00:00"
        return t
    }

    func entries(on day: Date) -> [Entry] {
        let key = Fmt.dayFormatter.string(from: day)
        return entries.filter { $0.date == key }
    }

    // MARK: Mentés / betöltés (CSV)

    func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    func save() {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dataFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if needsBackupBeforeSave, fm.fileExists(atPath: dataFileURL.path) {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "yyyyMMdd-HHmmss"
                let backup = dataFileURL.deletingPathExtension()
                    .appendingPathExtension("hibas-\(f.string(from: Date())).csv")
                try? fm.copyItem(at: dataFileURL, to: backup)
                needsBackupBeforeSave = false
            }
            try CSV.encode(entries).write(to: dataFileURL, options: .atomic)
            lastModified = modificationDate(of: dataFileURL)
            if lastError?.hasPrefix("Mentési hiba") == true { lastError = nil }
        } catch {
            lastError = "Mentési hiba: \(error.localizedDescription)"
        }
    }

    /// Beolvassa az adatfájlt; ha csak a régi JSON van meg, azt átalakítja CSV-vé.
    func loadFromDisk() {
        let fm = FileManager.default
        if fm.fileExists(atPath: dataFileURL.path) {
            loadCSV()
            return
        }
        let legacy = dataFileURL.deletingPathExtension().appendingPathExtension("json")
        if fm.fileExists(atPath: legacy.path) {
            importLegacyJSON(legacy)
        }
    }

    private func loadCSV() {
        do {
            let data = try Data(contentsOf: dataFileURL)
            let result = try CSV.decode(data)
            entries = result.entries.sorted { sortKey($0) < sortKey($1) }
            lastModified = modificationDate(of: dataFileURL)
            if startKmText.isEmpty { startKmText = lastEndKm.map(String.init) ?? "" }
            if result.warnings.isEmpty {
                lastError = nil
                needsBackupBeforeSave = false
            } else {
                needsBackupBeforeSave = true
                let shown = result.warnings.prefix(3).joined(separator: "; ")
                lastError = "\(result.warnings.count) sor kimaradt az adatfájlból: \(shown)"
            }
        } catch {
            needsBackupBeforeSave = true
            lastError = "Az adatfájl nem olvasható: \(error.localizedDescription)"
        }
    }

    /// Ha a fájlt közben szerkesztették (pl. táblázatkezelőben), újra beolvassa.
    func reloadIfChanged() {
        guard FileManager.default.fileExists(atPath: dataFileURL.path),
              let mod = modificationDate(of: dataFileURL), mod != lastModified else { return }
        loadCSV()
    }

    private func importLegacyJSON(_ url: URL) {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            guard let date = Fmt.isoWithOffset.date(from: s) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Hibás dátum: \(s)")
            }
            return date
        }
        do {
            let file = try d.decode(EntryFile.self, from: Data(contentsOf: url))
            entries = file.entries.sorted { sortKey($0) < sortKey($1) }
            save()
        } catch {
            lastError = "A régi (JSON) adatfájl nem olvasható: \(error.localizedDescription)"
        }
    }

    /// Új adatmappa kiválasztása. Ha ott már van adatfájl, azt tölti be, egyébként oda menti a meglévőket.
    func changeDataFolder(to folder: URL) {
        let newFile = folder.appendingPathComponent("bejegyzesek.csv")
        dataFileURL = newFile
        ud.set(newFile.path, forKey: "dataFile")
        applyNewLocation()
    }

    func resetDataFolder() {
        dataFileURL = Self.defaultDataFile
        ud.removeObject(forKey: "dataFile")
        applyNewLocation()
    }

    private func applyNewLocation() {
        let fm = FileManager.default
        let legacy = dataFileURL.deletingPathExtension().appendingPathExtension("json")
        if fm.fileExists(atPath: dataFileURL.path) || fm.fileExists(atPath: legacy.path) {
            entries = []
            loadFromDisk()
        } else {
            save()
        }
        if fm.fileExists(atPath: attendanceFileURL.path) {
            attendance = []
            loadAttendanceFromDisk()
        } else if !attendance.isEmpty {
            saveAttendance()
        }
        writePointer()
    }

    /// A skill ebből a fix helyen lévő fájlból tudja meg, hol van az adatfájl.
    private func writePointer() {
        let obj: [String: Any] = [
            "formatVersion": 2,
            "app": Self.appName,
            "format": "csv",
            "delimiter": ";",
            "dataFile": dataFileURL.path,
            "attendanceFile": attendanceFileURL.path
        ]
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes]) {
            try? data.write(to: Self.pointerFile, options: .atomic)
        }
    }

    // MARK: Visszaállítás alapállapotba

    /// Az összes bevitt adat törlése: bejegyzések, helyszínlista, saját kategóriák, elrejtett kategóriák,
    /// az űrlap és a futó időzítők. A beállítások (ikonok, hangok, nézet, adatmappa) megmaradnak.
    /// Biztonsági okból a törlés előtti adatfájl egy másolata megmarad (`bejegyzesek.torles-elotti.csv`),
    /// minden törlésnél felülírva.
    @discardableResult
    func resetAllData() -> Bool {
        let fm = FileManager.default
        timerStart = nil
        pomoPhase = .idle
        pomoDone = 0
        pendingSlot = nil
        if fm.fileExists(atPath: dataFileURL.path) {
            let backup = dataFileURL.deletingLastPathComponent().appendingPathComponent("bejegyzesek.torles-elotti.csv")
            try? fm.removeItem(at: backup)
            do {
                try fm.copyItem(at: dataFileURL, to: backup)
            } catch {
                lastError = "A törlés előtti másolat nem készült el, ezért nem töröltem: \(error.localizedDescription)"
                return false
            }
        }
        if fm.fileExists(atPath: attendanceFileURL.path) {
            let backup = attendanceFileURL.deletingLastPathComponent().appendingPathComponent("letszamjelentesek.torles-elotti.csv")
            try? fm.removeItem(at: backup)
            try? fm.copyItem(at: attendanceFileURL, to: backup)
        }
        entries = []
        attendance = []
        saveAttendance()
        needsBackupBeforeSave = false
        save()
        setPlaces(Self.defaultWorkplaces)
        saveCategories([])
        hiddenTypeCodes = []
        ud.set([String](), forKey: "hiddenTypes")
        syncRegistry()
        clearDraft()
        selectedDay = Date()
        if lastError?.hasPrefix("Mentési hiba") != true { lastError = nil }
        return true
    }

    // MARK: Értesítés
    private func requestNotificationPermission() {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func playSound(_ name: String) {
        guard name != Sounds.none else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    private func notify(title: String, body: String, soundKey: String) {
        playSound(ud.string(forKey: soundKey) ?? "Glass")
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
