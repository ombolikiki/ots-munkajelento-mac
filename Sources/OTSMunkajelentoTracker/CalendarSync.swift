import Foundation
import SwiftUI

/// A naptár-szinkron terve és végrehajtása. A tervező (`CalendarSync.plan`) tiszta függvény, EventKit nélkül tesztelhető;
/// a `CalendarSyncer` köti össze a naptárral (`CalendarSource`) és az adatokkal (`AppModel`).
/// Szabály: a naptár a mérvadó (módosítás frissít, törlés töröl), de csak a naptárból átvett bejegyzésekre;
/// a kézzel felvitt bejegyzéshez a szinkron nem nyúl.

/// Egy nem automatikusan átvehető esemény („Hiányos” vagy „Nem felismert”).
struct CalendarPendingItem: Identifiable, Equatable {
    var event: CalendarEventInput
    /// Hiányosnál a felismert típus.
    var type: ActivityType?
    /// A részben kitöltött napi szeletek (az előtöltéshez).
    var drafts: [CalendarDraft]
    var problems: [CalendarProblem]
    var id: String { event.id }
}

struct CalendarUpdate: Equatable {
    var entryID: UUID
    var draft: CalendarDraft
}

struct CalendarSyncPlan: Equatable {
    var toAdd: [CalendarDraft] = []
    var toUpdate: [CalendarUpdate] = []
    var toDelete: [UUID] = []
    /// Törlések, amelyeket a védelem miatt nem hajtunk végre magától (megerősítés kell).
    var heldDeletions: [UUID] = []
    var incomplete: [CalendarPendingItem] = []
    var unrecognized: [CalendarPendingItem] = []

    var hasChanges: Bool { !toAdd.isEmpty || !toUpdate.isEmpty || !toDelete.isEmpty }
}

enum CalendarSync {
    /// A naptárazonosító alapja: az esemény azonosítója a napi `#YYYY-MM-DD` utótag nélkül.
    static func baseID(_ calendarID: String) -> String {
        guard let hash = calendarID.lastIndex(of: "#") else { return calendarID }
        let suffix = calendarID[calendarID.index(after: hash)...]
        guard suffix.count == 10, CSV.parseDate(String(suffix)) != nil else { return calendarID }
        return String(calendarID[..<hash])
    }

    /// Ugyanazt a tartalmat jelenti-e a bejegyzés és a naptárból kapott szelet.
    static func sameContent(_ e: Entry, _ d: CalendarDraft) -> Bool {
        let q: Int? = d.type.hasQuantity ? max(1, d.quantity ?? 1) : nil
        return e.date == d.date && e.start == d.start && e.end == d.end && e.durationSeconds == d.durationSeconds
            && e.workplace == d.workplace && e.type == d.type.rawValue && e.quantity == q && e.activity == d.activity
            && e.departure == d.departure && e.arrival == d.arrival && e.address == d.address
    }

    /// A törlés védelme: ennél több (és a naptáras bejegyzések felénél több) törlést nem hajt végre magától.
    static let minHeldDeletions = 5

    /// - events: a kiválasztott naptárak eseményei az ablakban
    /// - existenceIDs: minden naptár összes eseményének azonosítója (a törlés eldöntéséhez; a naptár kijelölésének megszüntetése nem töröl)
    /// - existing: a jelenlegi bejegyzések
    /// - windowStart: az ablak kezdete; ennél korábbi bejegyzésekhez a szinkron nem nyúl
    /// - dismissed: a felhasználó által végleg kihagyottnak jelölt események azonosítói
    /// - allowDeletion: hamis, ha a naptár nem volt megbízhatóan olvasható (nincs engedély, hiba)
    static func plan(events: [CalendarEventInput], existenceIDs: Set<String>, existing: [Entry], now: Date, home: String,
                     windowStart: Date, dismissed: Set<String> = [], allowDeletion: Bool = true) -> CalendarSyncPlan {
        var plan = CalendarSyncPlan()
        let startKey = Fmt.dayFormatter.string(from: DateUtil.startOfDay(windowStart))

        var byCalID: [String: Entry] = [:]
        var resolvedBases = Set<String>()
        for e in existing {
            guard let cid = e.calendarID, !cid.isEmpty else { continue }
            if byCalID[cid] == nil { byCalID[cid] = e }
            resolvedBases.insert(baseID(cid))
        }

        var importedDrafts: [String: Set<String>] = [:]   // esemény azonosító -> a szeletek azonosítói
        var cancelledBases = Set<String>()
        var seenIDs = Set<String>()

        for ev in events {
            seenIDs.insert(ev.id)
            switch CalendarParser.parse(ev, now: now, home: home) {
            case .imported(let drafts):
                importedDrafts[ev.id] = Set(drafts.map { $0.calendarID })
                for d in drafts {
                    if let ex = byCalID[d.calendarID] {
                        if !sameContent(ex, d) { plan.toUpdate.append(CalendarUpdate(entryID: ex.id, draft: d)) }
                    } else {
                        plan.toAdd.append(d)
                    }
                }
            case .incomplete(let type, let drafts, let problems):
                if !resolvedBases.contains(ev.id) && !dismissed.contains(ev.id) {
                    plan.incomplete.append(CalendarPendingItem(event: ev, type: type, drafts: drafts, problems: problems))
                }
            case .unrecognized:
                if !resolvedBases.contains(ev.id) && !dismissed.contains(ev.id) {
                    plan.unrecognized.append(CalendarPendingItem(event: ev, type: nil, drafts: [], problems: []))
                }
            case .skipped(let reason):
                if reason == .declined || reason == .cancelled { cancelledBases.insert(ev.id) }
            }
        }

        // Törlési jelöltek: csak az ablakba eső, naptárból átvett bejegyzések.
        let known = existenceIDs.union(seenIDs)
        var candidates: [UUID] = []
        var inWindow = 0
        for e in existing {
            guard let cid = e.calendarID, !cid.isEmpty, e.date >= startKey else { continue }
            inWindow += 1
            let base = baseID(cid)
            if cancelledBases.contains(base) {
                candidates.append(e.id)
            } else if !known.contains(base) {
                candidates.append(e.id)
            } else if let ids = importedDrafts[base], !ids.contains(cid) {
                candidates.append(e.id)   // az esemény megrövidült vagy áthelyeződött: a felesleges nap törlődik
            }
        }
        if allowDeletion && !candidates.isEmpty {
            let suspicious = (existenceIDs.isEmpty && seenIDs.isEmpty) || candidates.count > max(minHeldDeletions, inWindow / 2)
            if suspicious { plan.heldDeletions = candidates } else { plan.toDelete = candidates }
        }
        return plan
    }
}

/// A felhasználó javítása egy „Hiányos” vagy „Nem felismert” eseményen.
struct CalendarFix: Equatable {
    var type: ActivityType?
    var workplace = ""
    var activity = ""
    var departure = ""
    var arrival = ""
    var quantity: Int?
}

extension CalendarSync {
    /// A javított napi szeletek, vagy a hiba szövege. Tiszta függvény (tesztelhető).
    static func fixedDrafts(item: CalendarPendingItem, fix: CalendarFix, now: Date, home: String) -> Result<[CalendarDraft], CalendarFixError> {
        if item.problems.contains(.noDuration) || item.problems.contains(.tooLong) {
            return .failure(CalendarFixError("Ez az esemény nem javítható itt (az időtartama nulla, negatív vagy túl hosszú); javítsd a naptárban, vagy hagyd ki."))
        }
        var drafts: [CalendarDraft]
        if let known = item.type {
            drafts = item.drafts
            if let t = fix.type, t != known, t.isWholeDay, item.problems.contains(.wholeDayNotAllowed) {
                drafts = drafts.map { var x = $0; x.type = t; x.quantity = nil; return x }
            }
        } else {
            guard let t = fix.type else { return .failure(CalendarFixError("Válassz tevékenység-típust.")) }
            switch CalendarParser.parse(item.event, forcedType: t, now: now, home: home) {
            case .imported(let d): drafts = d
            case .incomplete(_, let d, _): drafts = d
            default: drafts = []
            }
        }
        guard let first = drafts.first else { return .failure(CalendarFixError("Az eseményből nem készíthető bejegyzés.")) }
        let type = first.type
        let wp = fix.workplace.trimmingCharacters(in: .whitespacesAndNewlines)
        let act = fix.activity.trimmingCharacters(in: .whitespacesAndNewlines)
        let dep = fix.departure.trimmingCharacters(in: .whitespacesAndNewlines)
        let arr = fix.arrival.trimmingCharacters(in: .whitespacesAndNewlines)
        var missing: [String] = []
        if !type.isWholeDay {
            if type.isTravel {
                if dep.isEmpty { missing.append("Indulás") }
                if wp.isEmpty { missing.append("Munkahely(ek)") }
                if arr.isEmpty { missing.append("Érkezés") }
                if act.isEmpty { missing.append("Tevékenység") }
            } else if wp.isEmpty {
                missing.append("Munkahely")
            }
        }
        if !missing.isEmpty { return .failure(CalendarFixError("Kötelező mező: " + missing.joined(separator: ", ") + ".")) }
        let result: [CalendarDraft] = drafts.map { d in
            var x = d
            x.activity = act
            if !type.isWholeDay || !wp.isEmpty { x.workplace = wp }
            if type.isTravel { x.departure = dep; x.arrival = arr }
            if type.hasQuantity { x.quantity = max(1, min(999, fix.quantity ?? d.quantity ?? 1)) }
            // A pontos cím csak akkor marad, ha még ugyanabban a településben van.
            if let addr = d.address, !wp.isEmpty {
                let towns = addr.components(separatedBy: " - ").compactMap { CalendarParser.place($0).settlement }.map { CalendarParser.fold($0) }
                let wanted = type.isTravel ? wp.split(separator: ",").map { CalendarParser.fold(String($0)) } : [CalendarParser.fold(wp)]
                if !towns.contains(where: { wanted.contains($0) }) { x.address = nil }
            }
            return x
        }
        return .success(result)
    }
}

struct CalendarFixError: Error, Equatable {
    let text: String
    init(_ text: String) { self.text = text }
}

/// A szinkron eredménye (a felületnek).
struct CalendarSyncResult: Equatable {
    var added = 0
    var updated = 0
    var deleted = 0
    var heldDeletions = 0
    var incomplete = 0
    var unrecognized = 0
    var date: Date
    var error: String?
}

/// A felület és a naptár-értesítések a főszálon hívják (mint az AppModelt).
final class CalendarSyncer: ObservableObject {
    private let source: CalendarSource
    private weak var model: AppModel?
    private let ud = UserDefaults.standard

    @Published private(set) var access: CalendarAccess
    @Published private(set) var calendars: [CalendarInfo] = []
    @Published private(set) var isSyncing = false
    @Published private(set) var lastResult: CalendarSyncResult?
    @Published private(set) var incomplete: [CalendarPendingItem] = []
    @Published private(set) var unrecognized: [CalendarPendingItem] = []
    @Published private(set) var heldDeletions: [UUID] = []

    private var observer: NSObjectProtocol?
    private var debounce: DispatchWorkItem?

    init(model: AppModel, source: CalendarSource) {
        self.model = model
        self.source = source
        self.access = source.access
        ud.register(defaults: ["ekcal.enabled": false, "ekcal.days": 60])
    }

    deinit { if let o = observer { NotificationCenter.default.removeObserver(o) } }

    // MARK: Beállítások (UserDefaults)
    var enabled: Bool {
        get { ud.bool(forKey: "ekcal.enabled") }
        set { ud.set(newValue, forKey: "ekcal.enabled"); objectWillChange.send() }
    }
    /// A kiválasztott naptárak azonosítói.
    var selectedCalendarIDs: Set<String> {
        get { Set(ud.stringArray(forKey: "ekcal.calendars") ?? []) }
        set { ud.set(Array(newValue).sorted(), forKey: "ekcal.calendars"); objectWillChange.send() }
    }
    /// Hány napra visszamenőleg követi a naptárat (a régebbi bejegyzésekhez nem nyúl).
    var windowDays: Int {
        get { min(730, max(1, ud.integer(forKey: "ekcal.days"))) }
        set { ud.set(min(730, max(1, newValue)), forKey: "ekcal.days"); objectWillChange.send() }
    }
    /// A „Kihagyom” jelölt események azonosítói.
    var dismissedIDs: Set<String> {
        get { Set(ud.stringArray(forKey: "ekcal.dismissed") ?? []) }
        set { ud.set(Array(newValue).sorted(), forKey: "ekcal.dismissed"); objectWillChange.send() }
    }

    // MARK: Engedély és naptárak
    func requestAccess() async {
        _ = await source.requestAccess()
        refreshAccess()
    }

    func refreshAccess() {
        access = source.access
        calendars = access == .granted ? source.calendars() : []
    }

    // MARK: Szinkron
    /// A naptár változására (EKEventStoreChanged) késleltetve és összevonva szinkronizál.
    func startObserving() {
        guard observer == nil else { return }
        observer = source.observeChanges { [weak self] in self?.scheduleSync() }   // a főszálon érkezik
    }

    private func scheduleSync() {
        debounce?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.sync() }
        debounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
    }

    /// Egy szinkron futtatása. Visszaadja az eredményt (nil, ha nincs mit futtatni).
    @discardableResult
    func sync(now: Date = Date()) -> CalendarSyncResult? {
        guard enabled, !isSyncing, let model = model else { return nil }
        refreshAccess()
        guard access == .granted else { return nil }
        let selected = selectedCalendarIDs
        guard !selected.isEmpty else { return nil }
        isSyncing = true
        defer { isSyncing = false }

        let windowStart = DateUtil.addDays(DateUtil.startOfDay(now), -windowDays)
        let selectedEvents = source.events(calendarIDs: selected, from: windowStart, to: now)
        let wideEnd = DateUtil.addDays(now, 365)
        let existence = Set(source.events(calendarIDs: nil, from: windowStart, to: wideEnd).map { $0.id })

        let plan = CalendarSync.plan(events: selectedEvents, existenceIDs: existence, existing: model.entries, now: now,
                                     home: model.homePlace, windowStart: windowStart, dismissed: dismissedIDs)
        var result = CalendarSyncResult(date: now)
        result.added = plan.toAdd.count
        result.updated = plan.toUpdate.count
        result.deleted = plan.toDelete.count
        result.heldDeletions = plan.heldDeletions.count
        result.incomplete = plan.incomplete.count
        result.unrecognized = plan.unrecognized.count

        if plan.hasChanges {
            let updates: [Entry] = plan.toUpdate.map { $0.draft.entry(id: $0.entryID) }
            let ok = model.applyCalendarChanges(add: plan.toAdd.map { $0.entry() }, update: updates, delete: Set(plan.toDelete))
            if !ok { result.error = model.lastError ?? "A naptár-szinkron mentése nem sikerült." }
        }
        incomplete = plan.incomplete
        unrecognized = plan.unrecognized
        heldDeletions = plan.heldDeletions
        lastResult = result
        return result
    }

    /// Egy „Hiányos” vagy „Nem felismert” esemény átvétele a felhasználó javításával. Hibánál a hiba szövegét adja vissza.
    @discardableResult
    func resolve(_ item: CalendarPendingItem, fix: CalendarFix, now: Date = Date()) -> String? {
        guard let model = model else { return "Nincs adatmodell." }
        switch CalendarSync.fixedDrafts(item: item, fix: fix, now: now, home: model.homePlace) {
        case .failure(let e): return e.text
        case .success(let drafts):
            // Biztonság: egy már átvett nap nem kerülhet kétszer a fájlba.
            let have = Set(model.entries.compactMap { $0.calendarID })
            let fresh = drafts.filter { !have.contains($0.calendarID) }
            guard model.applyCalendarChanges(add: fresh.map { $0.entry() }, update: [], delete: []) else {
                return model.lastError ?? "A mentés nem sikerült."
            }
            incomplete.removeAll { $0.id == item.id }
            unrecognized.removeAll { $0.id == item.id }
            return nil
        }
    }

    /// Szinkron, ha az utolsó futás óta eltelt `seconds` másodperc (az ablak előtérbe kerülésekor).
    func syncIfStale(seconds: TimeInterval = 120, now: Date = Date()) {
        guard enabled else { return }
        if let last = lastResult?.date, now.timeIntervalSince(last) < seconds { return }
        sync(now: now)
    }

    /// A védelem miatt visszatartott törlések végrehajtása (a felhasználó megerősítése után).
    @discardableResult
    func confirmHeldDeletions() -> Bool {
        guard let model = model, !heldDeletions.isEmpty else { return false }
        let ok = model.applyCalendarChanges(add: [], update: [], delete: Set(heldDeletions))
        if ok { heldDeletions = [] }
        return ok
    }

    func discardHeldDeletions() { heldDeletions = [] }

    /// A visszatartott törlések helyett a bejegyzések megtartása: kézi bejegyzéssé válnak, a szinkron többé nem követi őket.
    @discardableResult
    func keepHeldDeletionsAsManual() -> Bool {
        guard let model = model, !heldDeletions.isEmpty else { return false }
        let ids = Set(heldDeletions)
        let changed: [Entry] = model.entries.filter { ids.contains($0.id) }.map { var e = $0; e.calendarID = nil; e.source = "manual"; return e }
        let ok = model.applyCalendarChanges(add: [], update: changed, delete: [])
        if ok { heldDeletions = [] }
        return ok
    }

    /// Egy esemény végleges kihagyása (nem kerül többé a listákra).
    func dismiss(_ eventID: String) {
        dismissedIDs = dismissedIDs.union([eventID])
        incomplete.removeAll { $0.id == eventID }
        unrecognized.removeAll { $0.id == eventID }
    }
}
