import SwiftUI
import AppKit

/// A naptár-szinkron felülete: Beállítások-kártya, a „Hiányos / Nem felismert” ablak és a jelölések leírása.
/// Az ablakok rögzített méretűek és görgethetők (lásd CLAUDE.md: az ablak nem nőhet a képernyőnél nagyobbra).

// MARK: Beállítások-kártya

struct CalendarSyncCard: View {
    @ObservedObject var sync: CalendarSyncer
    @EnvironmentObject var m: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Naptár-szinkron (Mac Naptár)").font(.subheadline.weight(.semibold))
            Text("A Mac Naptár-alkalmazásának lezajlott eseményeit veszi át bejegyzésként, egy irányban: a naptárba az alkalmazás nem ír. A Google és az Outlook naptárad is bekerül, ha a Mac szinkronizálja (Rendszerbeállítások › Internetes fiókok). A naptár a mérvadó: a naptárban módosított vagy törölt esemény bejegyzése is módosul, illetve törlődik; a kézzel felvitt bejegyzéshez nem nyúl.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Naptár-szinkron bekapcsolása", isOn: Binding(get: { sync.enabled }, set: setEnabled))
            if sync.enabled { details }
        }
        .card()
        .onAppear { sync.refreshAccess() }
    }

    private func setEnabled(_ on: Bool) {
        sync.enabled = on
        guard on else { return }
        Task { @MainActor in
            if sync.access == .notDetermined { await sync.requestAccess() }
            sync.refreshAccess()
            sync.startObserving()
            sync.sync()
        }
    }

    @ViewBuilder private var details: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: sync.access == .granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(sync.access == .granted ? Theme.go : Theme.warn)
            Text(sync.access.text).font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        switch sync.access {
        case .notDetermined:
            Button("Engedély kérése") { Task { @MainActor in await sync.requestAccess(); sync.sync() } }
        case .denied, .writeOnly, .restricted:
            Button("Rendszerbeállítások megnyitása") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") { NSWorkspace.shared.open(url) }
            }
        case .granted:
            calendarList
            HStack {
                Text("Visszamenőleg követett időszak")
                Spacer()
                Picker("", selection: Binding(get: { sync.windowDays }, set: { sync.windowDays = $0 })) {
                    ForEach([30, 60, 90, 180, 365], id: \.self) { Text("\($0) nap").tag($0) }
                }
                .labelsHidden().frame(width: 100)
            }
            Text("Az ennél régebbi bejegyzésekhez a szinkron nem nyúl.").font(.caption2).foregroundStyle(.secondary)
            actions
            result
            held
        }
    }

    private var calendarList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Melyik naptárakból olvasson?").font(.caption).foregroundStyle(.secondary)
            if sync.calendars.isEmpty {
                Text("Nem található naptár.").font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(sync.calendars) { c in
                            Toggle(isOn: Binding(get: { sync.selectedCalendarIDs.contains(c.id) }, set: { on in
                                var ids = sync.selectedCalendarIDs
                                if on { ids.insert(c.id) } else { ids.remove(c.id) }
                                sync.selectedCalendarIDs = ids
                                if on { sync.sync() }
                            })) {
                                HStack(spacing: 6) {
                                    Circle().fill(c.colorHex.flatMap { CategoryColors.color(hex: $0) } ?? Color.secondary).frame(width: 9, height: 9)
                                    Text(c.title)
                                    if !c.account.isEmpty { Text(c.account).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: min(150, CGFloat(sync.calendars.count) * 30 + 4))
            }
            Text("Ajánlott egy külön „OTS Munkajelentő” naptár: így a személyes eseményeid sosem kerülnek be. Több naptárnál csak a felismerhető típussal kezdődő című események kerülnek át.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        let pending = sync.incomplete.count + sync.unrecognized.count
        return HStack {
            Button("Szinkron most") { sync.sync() }
                .disabled(sync.selectedCalendarIDs.isEmpty || sync.isSyncing)
            Button(pending > 0 ? "Átnézésre vár (\(pending))…" : "Átnézésre vár…") {
                CalendarPendingWindow.shared.show(model: m)
            }
            Button("Jelölések…") { CalendarNotationWindow.shared.show() }
        }
    }

    @ViewBuilder private var result: some View {
        if let r = sync.lastResult {
            VStack(alignment: .leading, spacing: 2) {
                Text("Utolsó szinkron: \(Fmt.timeFormatter.string(from: r.date)) · átvett \(r.added), frissített \(r.updated), törölt \(r.deleted)")
                    .font(.caption).foregroundStyle(.secondary)
                if r.incomplete + r.unrecognized > 0 {
                    Text("Átnézésre vár: \(r.incomplete) hiányos, \(r.unrecognized) nem felismert esemény.")
                        .font(.caption).foregroundStyle(Theme.warn)
                }
                if let e = r.error { Text(e).font(.caption).foregroundStyle(Theme.stop) }
            }
        } else if !sync.selectedCalendarIDs.isEmpty {
            Text("Még nem futott szinkron.").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var held: some View {
        if !sync.heldDeletions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("\(sync.heldDeletions.count) bejegyzés törlését a védelem visszatartotta", systemImage: "exclamationmark.shield")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.warn)
                Text("A naptárban nem találom a hozzájuk tartozó eseményeket. Ha a naptár csak átmenetileg üres (például szinkronhiba miatt), válaszd a „Megtartom” gombot.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Törlöm őket") { sync.confirmHeldDeletions() }
                    Button("Megtartom (kézi bejegyzésként)") { sync.keepHeldDeletionsAsManual() }
                    Button("Később") { sync.discardHeldDeletions() }
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.warn.opacity(0.12)))
        }
    }
}

// MARK: Hiányos és nem felismert események

struct CalendarPendingView: View {
    @ObservedObject var sync: CalendarSyncer
    @EnvironmentObject var m: AppModel

    var body: some View {
        let empty = sync.incomplete.isEmpty && sync.unrecognized.isEmpty
        VStack(alignment: .leading, spacing: 8) {
            Text("Naptár: átnézésre váró események").font(.headline)
            Text("Ezeket az eseményeket nem vettem át magamtól. Egészítsd ki őket, és vedd át egy érintéssel, vagy hagyd ki végleg.")
                .font(.caption).foregroundStyle(.secondary)
            if empty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 30)).foregroundStyle(Theme.go)
                    Text("Nincs átnézésre váró esemény.").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !sync.incomplete.isEmpty {
                            Text("Hiányos (\(sync.incomplete.count))").font(.subheadline.weight(.semibold))
                            ForEach(sync.incomplete) { CalendarPendingRow(item: $0, sync: sync).id($0.id) }
                        }
                        if !sync.unrecognized.isEmpty {
                            Text("Nem felismert (\(sync.unrecognized.count))").font(.subheadline.weight(.semibold)).padding(.top, 4)
                            ForEach(sync.unrecognized) { CalendarPendingRow(item: $0, sync: sync).id($0.id) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(14)
    }
}

struct CalendarPendingRow: View {
    let item: CalendarPendingItem
    @ObservedObject var sync: CalendarSyncer
    @EnvironmentObject var m: AppModel
    @State private var fix = CalendarFix()
    @State private var error: String?
    @State private var loaded = false

    private var typeChoices: [ActivityType] {
        if item.type == nil { return ActivityType.builtins }
        if item.problems.contains(.wholeDayNotAllowed) { return ActivityType.builtins.filter { $0.isWholeDay } }
        return []
    }
    private var current: ActivityType? { fix.type ?? item.type }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.event.title.isEmpty ? "(cím nélkül)" : item.event.title).font(.subheadline.weight(.semibold))
            Text(whenText).font(.caption).foregroundStyle(.secondary)
            if !item.event.location.isEmpty { Text("Helyszín: \(item.event.location)").font(.caption).foregroundStyle(.secondary) }
            if item.type == nil {
                Text("A cím nem ismert típussal kezdődik. Válassz típust: ez egyszeri döntés ennél az eseménynél.")
                    .font(.caption).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(item.problems.enumerated()), id: \.offset) { _, p in
                Text(p.text).font(.caption).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
            }
            editor
            if let e = error { Text(e).font(.caption).foregroundStyle(Theme.stop).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Átvétel") { error = sync.resolve(item, fix: fix) }
                    .disabled(item.problems.contains(.noDuration) || item.problems.contains(.tooLong))
                Button("Kihagyom") { sync.dismiss(item.id) }
                    .help("Az esemény többé nem kerül erre a listára")
            }
        }
        .card()
        .onAppear(perform: load)
    }

    @ViewBuilder private var editor: some View {
        if !typeChoices.isEmpty {
            Picker("Típus", selection: Binding(get: { fix.type }, set: { fix.type = $0 })) {
                Text("Válassz…").tag(ActivityType?.none)
                ForEach(typeChoices) { Text($0.label).tag(ActivityType?.some($0)) }
            }
        }
        if let t = current {
            if !t.isWholeDay {
                TextField(t.isTravel ? "Munkahely(ek), vesszővel elválasztva" : "Munkahely", text: $fix.workplace).textFieldStyle(.roundedBorder)
            }
            if t.isTravel {
                HStack {
                    TextField("Indulás", text: $fix.departure).textFieldStyle(.roundedBorder)
                    TextField("Érkezés", text: $fix.arrival).textFieldStyle(.roundedBorder)
                }
            }
            TextField(t.isTravel ? "Tevékenység (kötelező: az út célja)" : "Tevékenység (nem kötelező)", text: $fix.activity).textFieldStyle(.roundedBorder)
            if t.hasQuantity {
                Stepper("\(fix.quantity ?? 1) \(t.quantityUnit)", value: Binding(get: { fix.quantity ?? 1 }, set: { fix.quantity = $0 }), in: 1...999)
            }
        }
    }

    private var whenText: String {
        let e = item.event
        if e.isAllDay { return Fmt.longDay.string(from: e.start) + " · egész napos" }
        return Fmt.longDay.string(from: e.start) + " · " + Fmt.timeFormatter.string(from: e.start) + "–" + Fmt.timeFormatter.string(from: e.end)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let d = item.drafts.first {
            fix = CalendarFix(type: nil, workplace: d.workplace, activity: d.activity, departure: d.departure ?? m.homePlace,
                              arrival: d.arrival ?? m.homePlace, quantity: d.quantity)
        } else {
            let town = CalendarParser.splitLocations(item.event.location).first.flatMap { CalendarParser.place($0).settlement } ?? ""
            fix = CalendarFix(type: nil, workplace: town, activity: item.event.title, departure: m.homePlace, arrival: m.homePlace, quantity: 1)
        }
    }
}

// MARK: Jelölések leírása

struct CalendarNotationView: View {
    private let types: [(String, String)] = [
        ("Istentisztelet", "Istentisztelet"), ("Látogatás (gyülekezet)", "Látogatás"), ("Látogatás (misszió)", "Missziós látogatás"),
        ("Ügyintézés", "Ügyintézés, Ügy"), ("Értekezlet", "Értekezlet, Ért"), ("Evangelizáció", "Evangelizáció, Evang"),
        ("Bibliaóra", "Bibliaóra, Bibl"), ("Továbbképzés – résztvevő", "Továbbképzés, Képzés"), ("Továbbképzés – tartott", "Tartott képzés, Tartott továbbképzés"),
        ("Adminisztráció", "Adminisztráció, Admin"), ("Felkészülés", "Felkészülés, Felk"), ("Utazás", "Utazás, Utaz"),
        ("Szabadság", "Szabadság"), ("Szabadnap", "Szabadnap"), ("Munkaszüneti nap", "Munkaszüneti nap, Munkaszüneti")
    ]
    private let examples: [(String, String)] = [
        ("Értekezlet: Heti megbeszélés · 9:00–10:30 · Helyszín: Győr", "Értekezlet, 1:30 óra, Győr"),
        ("Felkészülés @Mór: Prédikáció · 11:00–13:00", "Felkészülés, 2 óra, Mór"),
        ("Látogatás ×3: Idősek otthona · Helyszín: Mór", "Látogatás, 3 fő, Mór"),
        ("Istentisztelet · 10:00–12:00 · Helyszín: Tata", "Istentisztelet, 1 alkalom, Tata"),
        ("Utazás: Győr ⇄ Tata, Mór | Kiszállás · 7:30–8:15", "Utazás, 0:45, Győr–Tata–Mór–Győr, cél: Kiszállás"),
        ("Értekezlet: x · Helyszín: Fő utca 3., Győr - Mór u. 5., Mór", "Két cím: a Munkahely az első (Győr), az esemény hiányos"),
        ("Szabadság · egész napos, 3 napos", "3 nap Szabadság")
    ]

    private func block(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.weight(.semibold))
            ForEach(lines, id: \.self) { Text($0).font(.caption).fixedSize(horizontal: false, vertical: true) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Naptári jelölések").font(.headline)
                Text("Egy esemény = egy bejegyzés. A cím így néz ki: Típus: Mit csináltál. A Helyszín mező a munkahely (település vagy teljes cím). Az időpont a kezdés és a vég.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                block("Cím", [
                    "A típus kisbetű- és ékezetfüggetlen; a kettőspont helyett ' - ' is jó. A Tevékenység csak az Utazásnál kötelező.",
                    "Munkahely gyorsan a címben: Értekezlet @Győr: Heti megbeszélés (a @ erősebb a Helyszínnél).",
                    "Mennyiség (alkalom és fő típusoknál): ×3, x3, 3 fő vagy 3 alkalom; nincs megadva: 1."
                ])
                VStack(alignment: .leading, spacing: 2) {
                    Text("Elfogadott típusnevek").font(.subheadline.weight(.semibold))
                    ForEach(types, id: \.0) { t in
                        HStack(alignment: .top) {
                            Text(t.0).font(.caption).frame(width: 190, alignment: .leading)
                            Text(t.1).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                block("Helyszín és pontos cím", [
                    "A Helyszín lehet település (Győr) vagy teljes cím (Fő utca 3., Győr). A település a cím utolsó vessző utáni része (irányítószám és „Magyarország” nélkül); ez lesz a Munkahely, a teljes cím a Cím oszlopba kerül.",
                    "Több címet kötelezően ' - ' (szóköz-kötőjel-szóköz) választ el: Fő utca 3., Győr - Mór u. 5., Mór. A címen belüli kötőjel (Győr-Moson) nem választ el.",
                    "A Google Maps útvonalba a pontos cím megy; ha a cím nem található, a település."
                ])
                block("Utazás", [
                    "Utazás: Győr → Tata, Mór → Győr | Kiszállás, vagy oda-vissza: Utazás: Győr ⇄ Tata, Mór | Kiszállás.",
                    "A → helyett -> , a ⇄ helyett <-> vagy oda-vissza is jó. A cél (a | után, vagy a Leírás első sora) kötelező.",
                    "Útvonal nélkül az Indulás és az Érkezés a székhely."
                ])
                block("Egész napos események", ["Csak Szabadság, Szabadnap és Munkaszüneti nap. A többnapos esemény naponta egy bejegyzés, csak a mai napnál korábbi napokra."])
                block("Mit vesz át, mit hagy ki?", [
                    "Csak a már lezajlott eseményeket; a visszautasítottat és a törölttet nem. Az éjfélen átnyúló esemény két napra bomlik (alkalom és fő típusnál nem).",
                    "Ismeretlen típusú vagy hiányos esemény az „Átnézésre vár” ablakba kerül, ahol egy érintéssel átveheted vagy véglegesen kihagyhatod.",
                    "A naptár a mérvadó: a módosított esemény bejegyzése frissül, a törölt esemény bejegyzése törlődik (kézzel felvitt bejegyzés nem)."
                ])
                VStack(alignment: .leading, spacing: 4) {
                    Text("Példák").font(.subheadline.weight(.semibold))
                    ForEach(examples, id: \.0) { e in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(e.0).font(.system(size: 11, design: .monospaced)).fixedSize(horizontal: false, vertical: true)
                            Text("→ " + e.1).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: Ablakok

private func makeCalendarWindow<V: View>(_ root: V, title: String, size: NSSize, min: NSSize, delegate: NSWindowDelegate) -> NSWindow {
    let paletteID = UserDefaults.standard.string(forKey: "palette") ?? "blue"
    let hosting = NSHostingController(rootView: root.environment(\.palette, Palette.byID(paletteID)))
    // Rögzített méret, nem a tartalom szabja meg (lásd CLAUDE.md).
    hosting.sizingOptions = []
    let w = NSWindow(contentViewController: hosting)
    w.styleMask = [.titled, .closable, .resizable, .miniaturizable]
    w.title = title
    w.isReleasedWhenClosed = false
    let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
    w.setContentSize(NSSize(width: Swift.min(size.width, Swift.max(min.width, visible.width - 80)),
                            height: Swift.min(size.height, Swift.max(min.height, visible.height - 100))))
    w.contentMinSize = min
    w.center()
    w.delegate = delegate
    return w
}

final class CalendarPendingWindow: NSObject, NSWindowDelegate {
    static let shared = CalendarPendingWindow()
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            window = makeCalendarWindow(CalendarPendingView(sync: model.calendarSync).environmentObject(model),
                                        title: "Naptár: hiányos és nem felismert események",
                                        size: NSSize(width: 640, height: 640), min: NSSize(width: 480, height: 360), delegate: self)
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        window = nil
    }
}

final class CalendarNotationWindow: NSObject, NSWindowDelegate {
    static let shared = CalendarNotationWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            window = makeCalendarWindow(CalendarNotationView(), title: "Naptári jelölések",
                                        size: NSSize(width: 620, height: 700), min: NSSize(width: 460, height: 360), delegate: self)
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        window = nil
    }
}
