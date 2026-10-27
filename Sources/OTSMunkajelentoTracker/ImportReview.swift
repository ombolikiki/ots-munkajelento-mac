import SwiftUI
import AppKit

/// Szabad szöveges rögzítés (1.8.0): az MI-asszisztens (a skill „Bejegyzések felvitele szabad szövegből” feladata) a felhasználó szövegéből
/// bejegyzéseket készít, és az adatfájl melletti `bejegyzesek-import.csv` fájlba írja (ugyanaz a CSV-formátum, `Forrás = ai`). Az alkalmazás ezeket
/// **áttekintésre** mutatja: csak a felhasználó jóváhagyása után kerülnek az adatok közé. Az éles adatfájlhoz az asszisztens soha nem nyúl.
struct ImportItem: Identifiable, Equatable {
    var entry: Entry
    /// Akadályozó hibák: az ilyen bejegyzés nem fogadható el (az asszisztensnek ki kell javítania).
    var problems: [String]
    /// Figyelmeztetések (például már van ilyen bejegyzés, átfedés): elfogadható, de alapból nincs kijelölve, ha duplikátum.
    var warnings: [String]
    var duplicate: Bool
    var id: UUID { entry.id }
    var acceptable: Bool { problems.isEmpty }
}

enum ImportReview {
    static let fileName = "bejegyzesek-import.csv"

    /// Egy beolvasott bejegyzés ellenőrzése: kötelező mezők, jövőbeli időpont, időtartam, Utazás mezői, km-állások; duplikátum és átfedés.
    static func check(_ e: Entry, existing: [Entry], now: Date) -> (problems: [String], warnings: [String], duplicate: Bool) {
        var problems: [String] = []
        var warnings: [String] = []
        let type = ActivityType.lookup(code: e.type)
        let today = Fmt.dayFormatter.string(from: now)

        if e.date > today { problems.append("Jövőbeli napra nem lehet bejegyzést felvenni.") }
        if let end = e.end, end > now.addingTimeInterval(60) { problems.append("Jövőbeli időpont nem rögzíthető.") }
        if type?.isCustom == true { warnings.append("Saját kategória: nem kerül az OTS-be.") }

        let isWholeDay = e.unit == Unit.wholeDay.rawValue
        if e.unit == Unit.hours.rawValue {
            if let s = e.start, let en = e.end {
                if en <= s { problems.append("A vég legyen a kezdés után.") }
            } else if e.durationSeconds <= 0 {
                problems.append("Nincs időtartam (kezdés–vég vagy óraszám kell).")
            }
            if e.durationSeconds <= 0 && e.start != nil && e.end != nil { problems.append("Nulla időtartam.") }
        }
        if e.type == ActivityType.travel.code {
            var missing: [String] = []
            if (e.departure ?? "").trimmingCharacters(in: .whitespaces).isEmpty { missing.append("Kiindulás (Indulás)") }
            if e.workplace.trimmingCharacters(in: .whitespaces).isEmpty { missing.append("Cél (Munkahely)") }
            if (e.arrival ?? "").trimmingCharacters(in: .whitespaces).isEmpty { missing.append("Érkezés") }
            if e.activity.trimmingCharacters(in: .whitespaces).isEmpty { missing.append("Tevékenység (az út célja)") }
            if !missing.isEmpty { problems.append("Utazásnál kötelező: " + missing.joined(separator: ", ") + ".") }
        } else if !isWholeDay, e.workplace.trimmingCharacters(in: .whitespaces).isEmpty {
            problems.append("Hiányzik a Munkahely.")
        }
        if let s = e.startKm, let en = e.endKm, en <= s { problems.append("Az érkező km legyen nagyobb az induló km-nél.") }
        if e.type != ActivityType.travel.code, e.startKm != nil || e.endKm != nil { warnings.append("A km-állás csak Utazásnál használt: nem kerül be.") }

        let duplicate = existing.contains {
            $0.date == e.date && $0.type == e.type && $0.start == e.start && $0.end == e.end && $0.durationSeconds == e.durationSeconds
                && $0.workplace == e.workplace && $0.activity == e.activity && $0.quantity == e.quantity
        }
        if duplicate { warnings.append("Már van ilyen bejegyzés.") }
        if let s = e.start, let en = e.end, !duplicate {
            if let o = existing.first(where: { x in
                guard let xs = x.start, let xe = x.end, x.date == e.date else { return false }
                return xs < en && xe > s
            }) { warnings.append("Átfed egy meglévő bejegyzéssel (\(o.typeLabel)).") }
        }
        return (problems, warnings, duplicate)
    }

    /// Az importfájl tartalmából az áttekintendő bejegyzések. A fájlban már szereplő azonosítók (vagy ismétlődők) új azonosítót kapnak.
    static func items(from data: Data, existing: [Entry], now: Date) -> (items: [ImportItem], notes: [String]) {
        let decoded: CSV.DecodeResult
        do { decoded = try CSV.decode(data) } catch {
            return ([], ["Az importfájl nem olvasható: \(error.localizedDescription)"])
        }
        var seen = Set(existing.map { $0.id })
        var items: [ImportItem] = []
        for var e in decoded.entries {
            if seen.contains(e.id) { e.id = UUID() }
            seen.insert(e.id)
            // az asszisztenstől érkező bejegyzés forrása jelölt marad (`ai`); üres forrást a CSV-olvasás `manual`-ra állít
            let r = check(e, existing: existing, now: now)
            items.append(ImportItem(entry: e, problems: r.problems, warnings: r.warnings, duplicate: r.duplicate))
        }
        return (items, decoded.warnings)
    }
}

// MARK: - A modell

extension AppModel {
    var importFileURL: URL { dataFileURL.deletingLastPathComponent().appendingPathComponent(ImportReview.fileName) }

    /// Beolvassa az importfájlt (csak ha változott, vagy `force`), és frissíti az áttekintésre váró bejegyzések listáját.
    func refreshImport(force: Bool = false, announce: Bool = true) {
        let url = importFileURL
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            if !importItems.isEmpty { importItems = [] }
            if !importNotes.isEmpty { importNotes = [] }
            importFileStamp = nil
            return
        }
        let stamp = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        if !force, let stamp = stamp, stamp == importFileStamp { return }
        importFileStamp = stamp
        guard let data = try? Data(contentsOf: url) else { return }
        let before = importItems.count
        let result = ImportReview.items(from: data, existing: entries, now: Date())
        importItems = result.items
        importNotes = result.notes
        if announce, importItems.count > before {
            notifyImport(count: importItems.count)
        }
    }

    /// Az áttekintésre váró bejegyzések elfogadása (csak az elfogadhatók, a megadott azonosítókkal); a fájlból kikerülnek.
    @discardableResult
    func acceptImport(_ ids: Set<UUID>) -> Int {
        var count = 0
        for item in importItems where ids.contains(item.id) && item.acceptable {
            add(item.entry)
            count += 1
        }
        removeFromImport(ids.intersection(Set(importItems.filter { $0.acceptable }.map { $0.id })))
        if count > 0 { showNotice("\(count) bejegyzés felvéve a szabad szöveges rögzítésből.") }
        return count
    }

    /// Az áttekintésre váró bejegyzések elvetése (a megadott azonosítókkal); a fájlból kikerülnek.
    func discardImport(_ ids: Set<UUID>) { removeFromImport(ids) }

    private func removeFromImport(_ ids: Set<UUID>) {
        let remaining = importItems.filter { !ids.contains($0.id) }
        let url = importFileURL
        if remaining.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else {
            try? CSV.encode(remaining.map { $0.entry }).write(to: url, options: .atomic)
        }
        refreshImport(force: true, announce: false)
        if remaining.isEmpty { importItems = []; importNotes = [] }
    }

    private func notifyImport(count: Int) {
        announce(title: "Új bejegyzések várnak jóváhagyásra", body: "\(count) bejegyzés a szabad szöveges rögzítésből. Nyisd meg az áttekintést a fejlécben.")
    }
}

// MARK: - Áttekintő ablak

struct ImportReviewView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.palette) private var palette
    @State private var selection: Set<UUID> = []
    @State private var known: Set<UUID> = []

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "yyyy. MMM d., EEE"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Szabad szöveggel felvitt bejegyzések").font(.title3.weight(.semibold))
            Text("Az MI-asszisztens ezeket a bejegyzéseket készítette a leírásodból. Csak azok kerülnek az adataid közé, amelyeket elfogadsz. A pirossal jelölt bejegyzés nem fogadható el: kérd meg az asszisztenst, hogy javítsa.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(m.importNotes, id: \.self) { Text($0).font(.caption).foregroundStyle(Theme.warn) }
            if m.importItems.isEmpty {
                Spacer()
                Text("Nincs áttekintésre váró bejegyzés.").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(m.importItems) { item in row(item) }
                    }
                }
            }
            Divider()
            HStack(spacing: 10) {
                Text("\(selection.count) kijelölve").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Kijelöltek elvetése") { m.discardImport(selection); selection = [] }
                    .disabled(selection.isEmpty)
                Button("Mind elvetése") { m.discardImport(Set(m.importItems.map { $0.id })); selection = [] }
                    .disabled(m.importItems.isEmpty)
                Button("Kijelöltek elfogadása") { m.acceptImport(selection); selection = selection.intersection(Set(m.importItems.map { $0.id })) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection.isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 360)
        .onAppear { syncSelection() }
        .onChange(of: m.importItems) { syncSelection() }
    }

    /// Új bejegyzések alapból kijelöltek, ha elfogadhatók és nem duplikátumok; a felhasználó korábbi választása megmarad.
    private func syncSelection() {
        let ids = Set(m.importItems.map { $0.id })
        for item in m.importItems where !known.contains(item.id) {
            if item.acceptable && !item.duplicate { selection.insert(item.id) }
        }
        known.formUnion(ids)
        selection = selection.intersection(ids)
    }

    private func row(_ item: ImportItem) -> some View {
        let e = item.entry
        return HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { selection.contains(item.id) },
                set: { on in if on { selection.insert(item.id) } else { selection.remove(item.id) } }
            ))
            .toggleStyle(.checkbox).labelsHidden().disabled(!item.acceptable)
            RoundedRectangle(cornerRadius: 2).fill(CategoryColors.color(code: e.type)).frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline(e)).font(.callout.weight(.semibold))
                Text(detail(e)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(item.problems, id: \.self) { Text($0).font(.caption).foregroundStyle(Theme.stop) }
                ForEach(item.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(Theme.warn) }
            }
            Spacer(minLength: 6)
            Text(amount(e)).font(.callout).monospacedDigit()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(item.acceptable ? 0.05 : 0.0)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(item.acceptable ? Color.clear : Theme.stop.opacity(0.5), lineWidth: 1))
    }

    private func headline(_ e: Entry) -> String {
        let day = Fmt.dayFormatter.date(from: e.date).map { Self.dayFormatter.string(from: $0) } ?? e.date
        var when = ""
        if e.unit == Unit.wholeDay.rawValue { when = "egész nap" }
        else if let s = e.start, let en = e.end { when = "\(Fmt.timeFormatter.string(from: s))–\(Fmt.timeFormatter.string(from: en))" }
        return [day, when, e.typeLabel].filter { !$0.isEmpty }.joined(separator: "  ")
    }

    private func detail(_ e: Entry) -> String {
        if e.type == ActivityType.travel.code {
            let route = ([e.departure ?? ""] + e.workplace.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } + [e.arrival ?? ""])
                .filter { !$0.isEmpty }.joined(separator: " → ")
            return [route, e.activity].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return [e.workplace, e.activity].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func amount(_ e: Entry) -> String {
        switch e.unit {
        case Unit.occasions.rawValue: return "\(e.quantity ?? 1) alkalom"
        case Unit.people.rawValue: return "\(e.quantity ?? 1) fő"
        case Unit.wholeDay.rawValue: return ""
        default: return Fmt.hm(e.durationSeconds)
        }
    }
}

final class ImportReviewWindow: NSObject, NSWindowDelegate {
    static let shared = ImportReviewWindow()
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let hosting = NSHostingController(rootView: ImportReviewView().environmentObject(model).environment(\.palette, Palette.byID(UserDefaults.standard.string(forKey: "palette") ?? "blue")))
            if #available(macOS 13.0, *) { hosting.sizingOptions = [] }
            let w = NSWindow(contentViewController: hosting)
            w.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            w.title = "Szabad szöveges rögzítés: áttekintés"
            w.isReleasedWhenClosed = false
            let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            w.setContentSize(NSSize(width: min(760, max(620, visible.width - 80)), height: min(560, max(380, visible.height - 100))))
            w.contentMinSize = NSSize(width: 620, height: 360)
            w.center()
            w.delegate = self
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        window = nil
    }
}
