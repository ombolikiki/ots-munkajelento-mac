import SwiftUI
import AppKit

// MARK: - Pipák: mely sorokat vitte már fel a felhasználó az OTS-be

/// A "felvittem" jelölések. Egy jelölés csak addig érvényes, amíg a sor tartalma nem változik.
final class OTSChecklist: ObservableObject {
    private let defaults: UserDefaults
    private static let key = "ots.done"
    @Published private var done: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        done = (defaults.dictionary(forKey: Self.key) as? [String: String]) ?? [:]
    }

    func isDone(_ key: String, _ signature: String) -> Bool { done[key] == signature }

    func set(_ key: String, _ signature: String, done value: Bool) {
        if value { done[key] = signature } else { done[key] = nil }
        defaults.set(done, forKey: Self.key)
    }
}

// MARK: - Nézetek

enum OTSDataset: String, CaseIterable, Identifiable {
    case work = "Munkajelentő"
    case cost = "Költségelszámolás"
    case attendance = "Létszámjelentő"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .work: return "list.bullet.clipboard"
        case .cost: return "car"
        case .attendance: return "person.3"
        }
    }
}

enum OTSViewMode: String, CaseIterable, Identifiable {
    case calendar = "Naptár"
    case list = "Felsorolás"
    case table = "OTS-táblázat"
    var id: String { rawValue }
}

private struct OTSContext {
    var year: Int
    var month: Int
    var rules: Bool
    var today: Date
}

struct OTSManualView: View {
    @EnvironmentObject var m: AppModel
    @StateObject private var checklist = OTSChecklist()
    @AppStorage("palette") private var paletteID = "blue"
    @AppStorage("cal.weekStart") private var weekStart = 2
    @AppStorage("ots.rules") private var rules = false
    @AppStorage("ots.dataset") private var datasetRaw = OTSDataset.work.rawValue
    @AppStorage("ots.viewMode") private var viewModeRaw = OTSViewMode.table.rawValue
    @State private var year = DateUtil.components(Date()).year
    @State private var month = DateUtil.components(Date()).month
    @State private var copied: String?
    @State private var started = false
    /// Induló hónap (alapból a mai hónap, hónap elején az előző, ha annak van adata).
    private let initialMonth: (year: Int, month: Int)?

    init(initialMonth: (year: Int, month: Int)? = nil) { self.initialMonth = initialMonth }

    private var palette: Palette { Palette.byID(paletteID) }
    private var dataset: OTSDataset { OTSDataset(rawValue: datasetRaw) ?? .work }
    private var viewMode: OTSViewMode { OTSViewMode(rawValue: viewModeRaw) ?? .table }
    private var today: Date { DateUtil.startOfDay(Date()) }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "yyyy. MMMM"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            Group {
                switch dataset {
                case .work: workBody
                case .cost: costBody
                case .attendance: attendanceBody
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .environment(\.palette, palette)
        .onAppear(perform: pickInitialMonth)
    }

    /// Hónap elején általában az előző hónapot kell lezárni: ha annak van adata, azzal indul.
    private func pickInitialMonth() {
        guard !started else { return }
        started = true
        let c = DateUtil.components(today)
        year = c.year; month = c.month
        if let i = initialMonth { year = i.year; month = i.month; return }
        if c.day <= 10 {
            let p = OTSManual.previousMonth(year: c.year, month: c.month)
            let prefix = String(format: "%04d-%02d", p.year, p.month)
            let hasPrev = m.entries.contains { $0.date.hasPrefix(prefix) } || m.attendance.contains { $0.date.hasPrefix(prefix) }
            if hasPrev { year = p.year; month = p.month }
        }
    }

    private var canGoForward: Bool {
        let c = DateUtil.components(today)
        return year < c.year || (year == c.year && month < c.month)
    }

    private var monthTitle: String {
        DateUtil.date(year: year, month: month, day: 1).map { Self.monthFormatter.string(from: $0) } ?? "\(year). \(month)."
    }

    // MARK: Eszköztár

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Picker("", selection: $datasetRaw) {
                    ForEach(OTSDataset.allCases) { d in Text(d.rawValue).tag(d.rawValue) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 420)
                Spacer()
                Button { step(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain)
                Text(monthTitle).font(.headline).frame(minWidth: 130)
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain).disabled(!canGoForward).opacity(canGoForward ? 1 : 0.3)
            }
            HStack(spacing: 12) {
                Picker("", selection: $viewModeRaw) {
                    ForEach(OTSViewMode.allCases) { v in Text(v.rawValue).tag(v.rawValue) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
                Spacer()
                if dataset == .work {
                    Toggle("Üres napok jelölése (!!!)", isOn: $rules)
                        .toggleStyle(.checkbox)
                        .help("Az üres napokat (hétköznap, szombat és vasárnap is) !!! jelöli, ahogy a skill is írná; a szabadnapot Szabadnap bejegyzés jelöli (SZABADNAP). A sorokat a skill nem egészíti ki 8 órára. Kikapcsolva csak a rögzített napok látszanak.")
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func step(_ d: Int) {
        let n = d < 0 ? OTSManual.previousMonth(year: year, month: month) : OTSManual.nextMonth(year: year, month: month)
        year = n.year; month = n.month
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let c = copied {
                Label("Másolva: \(c)", systemImage: "doc.on.doc.fill").foregroundStyle(palette.accent)
            } else {
                Text(hint).foregroundStyle(.secondary)
            }
            Spacer()
            Text(progress).foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 16).padding(.vertical, 7)
    }

    private var hint: String {
        switch dataset {
        case .work: return "Kattints egy értékre a vágólapra másoláshoz, a körre pedig a „felvittem” jelöléshez. A saját kategóriák nem vihetők az OTS-be."
        case .cost: return "Az útvonalat másold az OTS-be; a kilométert a Google Maps gombbal számolhatod ki (autóval, a leggyorsabb út, felfelé kerekítve)."
        case .attendance: return "Kattints egy számra a másoláshoz, a körre pedig a „felvittem” jelöléshez."
        }
    }

    private var progress: String {
        switch dataset {
        case .work:
            let rows = workRows.filter { $0.hasData || (rules && !$0.isEmpty) }
            let n = rows.filter { checklist.isDone("w|" + $0.key, $0.signature) }.count
            return "\(n)/\(rows.count) nap felvíve"
        case .cost:
            let rows = costRowsList
            let n = rows.filter { checklist.isDone("c|" + $0.key, $0.signature) }.count
            return "\(n)/\(rows.count) nap felvíve"
        case .attendance:
            let rows = attendanceRowsList.filter { $0.report != nil }
            let n = rows.filter { checklist.isDone("l|" + $0.key + "|" + $0.congregation, $0.signature) }.count
            return "\(n)/\(rows.count) jelentés felvíve"
        }
    }

    // MARK: Adatok

    private var workRows: [OTSWorkRow] {
        let byDate = m.entriesByDate
        return OTSManual.monthDays(year: year, month: month).map { day in
            OTSManual.workRow(day: day, entries: byDate[Fmt.dayFormatter.string(from: day)] ?? [], rules: rules, today: today)
        }
    }
    private var costRowsList: [OTSCostRow] { OTSManual.costRows(entries: m.entries, year: year, month: month, home: m.homePlace) }
    private var attendanceRowsList: [OTSAttendanceRow] {
        OTSManual.attendanceRows(reports: m.attendance, congregations: m.attendanceCongregations, year: year, month: month)
    }

    private func copy(_ text: String, label: String? = nil) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let shown = label ?? text
        copied = shown.count > 60 ? String(shown.prefix(60)) + "…" : shown
        let mine = copied
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { if copied == mine { copied = nil } }
    }

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "d. EEE"
        return f
    }()
    private static let longFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "MMMM d., EEEE"
        return f
    }()

    private func doneButton(_ key: String, _ sig: String) -> some View {
        let on = checklist.isDone(key, sig)
        return Button { checklist.set(key, sig, done: !on) } label: {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(on ? Theme.go : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(on ? "Felvíve – kattintásra törlöd a jelölést" : "Jelöld meg, ha már felvitted az OTS-be")
    }

    private func copyable(_ text: String, width: CGFloat? = nil, alignment: Alignment = .leading, bold: Bool = false) -> some View {
        Text(text.isEmpty ? " " : text)
            .font(.system(size: 12, weight: bold ? .semibold : .regular).monospacedDigit())
            .lineLimit(2)
            .frame(width: width, alignment: alignment)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .onTapGesture { copy(text) }
            .help(text.isEmpty ? "" : "Kattints a másoláshoz")
    }

    private func isWeekend(_ d: Date) -> Bool { DateUtil.isSaturday(d) || DateUtil.isSunday(d) }

    // MARK: Munkajelentő

    @ViewBuilder private var workBody: some View {
        switch viewMode {
        case .calendar:
            let rows = workRows
            monthGrid { day in workChips(day, rows) }
        case .list: workList
        case .table: workTable
        }
    }

    private func workChips(_ day: Date, _ rows: [OTSWorkRow]) -> [Chip] {
        guard let r = rows.first(where: { DateUtil.gregorian.isDate($0.date, inSameDayAs: day) }) else { return [] }
        var chips: [Chip] = []
        if r.holiday { chips.append(Chip(text: "Szabadság", color: CategoryColors.color(code: ActivityType.holiday.code))) }
        if r.workplace == "SZABADNAP" { chips.append(Chip(text: "Szabadnap", color: CategoryColors.color(code: ActivityType.dayOff.code))) }
        if r.workplace == "MUNKASZÜNETI NAP" { chips.append(Chip(text: "Munkaszüneti nap", color: CategoryColors.color(code: ActivityType.publicHoliday.code))) }
        for t in OTSManual.columns {
            if let v = r.values[t.code] {
                chips.append(Chip(text: "\(t.shortLabel) \(v) \(t.unit == .hours ? "óra" : t.quantityUnit)", color: CategoryColors.color(code: t.code)))
            }
        }
        if chips.isEmpty, r.workplace.hasPrefix("!!!") { chips.append(Chip(text: "!!!", color: Theme.warn)) }
        return chips
    }

    private var workList: some View {
        let rows = workRows.filter { $0.hasData || (rules && !$0.isEmpty) }
        let byDate = m.entriesByDate
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if rows.isEmpty { empty("Ebben a hónapban nincs OTS-be vihető bejegyzés.") }
                ForEach(rows, id: \.key) { r in
                    let key = "w|" + r.key
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            doneButton(key, r.signature)
                            Text(Self.longFormat.string(from: r.date)).font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                        if !r.workplace.isEmpty {
                            HStack(spacing: 8) {
                                Text("Munkahely").font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                                copyable(r.workplace, bold: true)
                            }
                        }
                        if r.holiday {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 2).fill(CategoryColors.color(code: ActivityType.holiday.code)).frame(width: 4, height: 16)
                                Text("Szabadság? jelölőnégyzet: pipa").font(.callout)
                            }
                        }
                        ForEach(OTSManual.columns.filter { r.values[$0.code] != nil }) { t in
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 2).fill(CategoryColors.color(code: t.code)).frame(width: 4, height: 16)
                                Text(t.label).font(.callout).frame(width: 150, alignment: .leading)
                                copyable("\(r.values[t.code] ?? 0)", bold: true)
                                Text(t.unit == .hours ? "óra" : t.quantityUnit).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        ForEach(r.notes, id: \.self) { n in
                            Label(n, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                        }
                        let src = (byDate[r.key] ?? []).sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
                        if !src.isEmpty {
                            DisclosureGroup("Rögzített bejegyzések (\(src.count))") {
                                VStack(alignment: .leading, spacing: 3) {
                                    ForEach(src) { e in
                                        HStack(alignment: .top, spacing: 6) {
                                            RoundedRectangle(cornerRadius: 1.5).fill(CategoryColors.color(code: e.type)).frame(width: 3, height: 14)
                                            Text(sourceLine(e)).font(.caption).foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }.padding(.top, 3)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
                }
            }
            .padding(16)
        }
    }

    private func sourceLine(_ e: Entry) -> String {
        var parts: [String] = []
        if let s = e.start, let en = e.end { parts.append("\(Fmt.timeFormatter.string(from: s))–\(Fmt.timeFormatter.string(from: en))") }
        parts.append(e.typeLabel)
        switch e.unit {
        case Unit.occasions.rawValue: parts.append("\(e.quantity ?? 1) alkalom")
        case Unit.people.rawValue: parts.append("\(e.quantity ?? 1) fő")
        case Unit.hours.rawValue: parts.append(Fmt.hm(e.durationSeconds))
        default: break
        }
        if !e.workplace.isEmpty { parts.append(e.workplace) }
        if !e.activity.isEmpty { parts.append(e.activity) }
        return parts.joined(separator: " · ")
    }

    private var workTable: some View {
        let rows = workRows
        let cols = OTSManual.columns
        let wDay: CGFloat = 86, wPlace: CGFloat = 200, wNum: CGFloat = 72, wCheck: CGFloat = 30
        return GeometryReader { geo in ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: wCheck + wDay, height: 1)
                    Text("Munkahely").frame(width: wPlace, alignment: .leading)
                    Text("Szabadság?").frame(width: wNum)
                    ForEach(cols) { t in
                        VStack(spacing: 2) {
                            Rectangle().fill(CategoryColors.color(code: t.code)).frame(height: 4)
                            Text(t.group == "Egyéb" ? "" : t.group).font(.system(size: 9)).foregroundStyle(.secondary)
                            Text(t.shortLabel).lineLimit(1).minimumScaleFactor(0.8)
                            Text(t.unit == .hours ? "óra" : t.quantityUnit).font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        .frame(width: wNum)
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                .padding(.vertical, 4)
                Divider()
                ForEach(rows, id: \.key) { r in
                    let live = r.hasData || (rules && !r.isEmpty)
                    HStack(spacing: 0) {
                        Group {
                            if live { doneButton("w|" + r.key, r.signature) } else { Color.clear.frame(height: 1) }
                        }.frame(width: wCheck)
                        Text(Self.dayFormat.string(from: r.date)).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isWeekend(r.date) ? Theme.stop.opacity(0.85) : Color.primary)
                            .frame(width: wDay, alignment: .leading)
                        copyable(r.workplace, width: wPlace)
                        Group {
                            if r.holiday {
                                Image(systemName: "checkmark.square.fill").foregroundStyle(palette.accent)
                                    .onTapGesture { copy("Szabadság", label: "Szabadság: pipa") }
                            } else { Text(" ") }
                        }.frame(width: wNum)
                        ForEach(cols) { t in
                            let v = r.values[t.code]
                            ZStack {
                                if v != nil { CategoryColors.color(code: t.code).opacity(0.18) }
                                copyable(v.map(String.init) ?? "", width: wNum, alignment: .center, bold: true)
                            }
                            .frame(width: wNum)
                        }
                    }
                    .background(isWeekend(r.date) ? Color.primary.opacity(0.04) : Color.clear)
                    .opacity(checklist.isDone("w|" + r.key, r.signature) ? 0.45 : 1)
                    Divider().opacity(0.5)
                }
                let totals = totalsLine(rows)
                if !totals.isEmpty {
                    Text(totals).font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }
            }
            .padding(16)
            .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
        } }
    }

    private func totalsLine(_ rows: [OTSWorkRow]) -> String {
        var parts: [String] = []
        for t in OTSManual.columns {
            let sum = rows.reduce(0) { $0 + ($1.values[t.code] ?? 0) }
            if sum > 0 { parts.append("\(t.shortLabel) \(sum)") }
        }
        return parts.isEmpty ? "" : "Összesen: " + parts.joined(separator: " · ")
    }

    // MARK: Költségelszámolás

    @ViewBuilder private var costBody: some View {
        switch viewMode {
        case .calendar:
            let rows = costRowsList
            monthGrid { day in costChips(day, rows) }
        case .list: costList
        case .table: costTable
        }
    }

    private func costChips(_ day: Date, _ rows: [OTSCostRow]) -> [Chip] {
        let key = Fmt.dayFormatter.string(from: day)
        guard let r = rows.first(where: { $0.key == key }) else { return [] }
        return r.routes.map { Chip(text: $0.joined(separator: " → "), color: CategoryColors.color(code: ActivityType.travel.code)) }
    }

    /// Megnyitja a Google Maps útvonalát. Ha az útvonalban pontos cím is van, előbb ellenőrzi (Apple geokódoló);
    /// ami nem található, azt a település helyettesíti. Cím nélküli útvonalnál azonnal nyit.
    private func openMaps(_ r: OTSCostRow, index: Int, fallback: URL) {
        guard r.mapRoutes.indices.contains(index) else { NSWorkspace.shared.open(fallback); return }
        let route = r.mapRoutes[index]
        let addresses = route.compactMap { $0.address }
        guard !addresses.isEmpty else { NSWorkspace.shared.open(fallback); return }
        Task { @MainActor in
            let verdicts = await AddressChecker.shared.verdicts(for: addresses)
            NSWorkspace.shared.open(OTSManual.mapsURL(route, useAddress: { verdicts[$0] ?? true }) ?? fallback)
        }
    }

    private func mapsButton(_ r: OTSCostRow) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(r.routes.enumerated()), id: \.offset) { i, route in
                if let url = OTSManual.mapsURL(route) {
                    Button { openMaps(r, index: i, fallback: url) } label: {
                        Label(r.routes.count > 1 ? "Térkép \(i + 1)" : "Google Maps", systemImage: "map")
                    }
                    .controlSize(.small)
                    .help("Megnyitja a Google Maps többpontos útvonalát a kilométer kiszámításához")
                }
            }
        }
    }

    private var costList: some View {
        let rows = costRowsList
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if rows.isEmpty { empty("Ebben a hónapban nincs Utazás bejegyzés.") }
                ForEach(rows, id: \.key) { r in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            doneButton("c|" + r.key, r.signature)
                            Text(Self.longFormat.string(from: r.date)).font(.subheadline.weight(.semibold))
                            Spacer()
                            mapsButton(r)
                        }
                        HStack(alignment: .top, spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(CategoryColors.color(code: ActivityType.travel.code)).frame(width: 4)
                            VStack(alignment: .leading, spacing: 4) {
                                labeled("Útvonal", r.route)
                                labeled("Tevékenység", r.activity)
                            }
                        }
                        if r.multiple {
                            Label("Több útvonal ugyanazon a napon: az OTS egy sorába ` ; ` -vel elválasztva írd, a kilométer a részútvonalak összege.", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(Theme.warn)
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
                }
            }
            .padding(16)
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .leading).padding(.top, 4)
            copyable(value.isEmpty ? "" : value, bold: true)
            if value.isEmpty { Text("(nincs)").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var costTable: some View {
        let rows = costRowsList
        let wCheck: CGFloat = 30, wDay: CGFloat = 86, wRoute: CGFloat = 380, wAct: CGFloat = 300, wMap: CGFloat = 130
        return GeometryReader { geo in ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: wCheck, height: 1)
                    Text("Dátum").frame(width: wDay, alignment: .leading)
                    Text("Útvonal").frame(width: wRoute, alignment: .leading)
                    Text("Tevékenység").frame(width: wAct, alignment: .leading)
                    Text("Kilométer").frame(width: wMap, alignment: .leading)
                }
                .font(.system(size: 11, weight: .semibold)).padding(.vertical, 5)
                Divider()
                if rows.isEmpty { empty("Ebben a hónapban nincs Utazás bejegyzés.") }
                ForEach(rows, id: \.key) { r in
                    HStack(alignment: .top, spacing: 0) {
                        doneButton("c|" + r.key, r.signature).frame(width: wCheck).padding(.top, 3)
                        Text(Self.dayFormat.string(from: r.date)).font(.system(size: 12, weight: .medium))
                            .frame(width: wDay, alignment: .leading).padding(.top, 3)
                        HStack(spacing: 0) {
                            Rectangle().fill(CategoryColors.color(code: ActivityType.travel.code)).frame(width: 3)
                            copyable(r.route, width: wRoute - 3).padding(.leading, 4)
                        }
                        .frame(width: wRoute)
                        copyable(r.activity, width: wAct)
                        Group {
                            if r.routes.contains(where: { $0.count >= 2 }) { mapsButton(r) } else { Text(" ") }
                        }.frame(width: wMap, alignment: .leading).padding(.top, 1)
                    }
                    .opacity(checklist.isDone("c|" + r.key, r.signature) ? 0.45 : 1)
                    Divider().opacity(0.5)
                }
            }
            .padding(16)
            .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
        } }
    }

    // MARK: Létszámjelentő

    @ViewBuilder private var attendanceBody: some View {
        if m.attendanceCongregations.isEmpty && m.attendance.isEmpty {
            empty("Még nincs gyülekezet regisztrálva a létszámjelentőhöz (Beállítások › Létszámjelentő).")
        } else {
            switch viewMode {
            case .calendar:
                let rows = attendanceRowsList
                monthGrid { day in attendanceChips(day, rows) }
            case .list: attendanceList
            case .table: attendanceTable
            }
        }
    }

    private func counts(_ c: AttendanceCounts) -> String { "\(c.children)/\(c.adults)/\(c.guests)" }

    private func attendanceChips(_ day: Date, _ rows: [OTSAttendanceRow]) -> [Chip] {
        let key = Fmt.dayFormatter.string(from: day)
        return rows.filter { $0.key == key }.map { r in
            if let rep = r.report {
                return Chip(text: "\(r.congregation): SI \(counts(rep.sabbathSchool)) · IT \(counts(rep.worship))", color: Palette.byID(paletteID).accent)
            }
            return Chip(text: "\(r.congregation): hiányzik", color: Theme.warn)
        }
    }

    private var attendanceList: some View {
        let rows = attendanceRowsList
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if rows.isEmpty { empty("Ebben a hónapban nincs esedékes létszámjelentő.") }
                ForEach(rows, id: \.id) { r in
                    let key = "l|" + r.key + "|" + r.congregation
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            if r.report != nil { doneButton(key, r.signature) }
                            Text("\(Self.longFormat.string(from: r.date)) · \(r.congregation)").font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                        if let rep = r.report {
                            attendanceLine("Szombatiskola", rep.sabbathSchool)
                            attendanceLine("Istentisztelet", rep.worship)
                        } else {
                            Label("Ehhez a naphoz még nincs rögzített létszám.", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(Theme.warn)
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
                }
            }
            .padding(16)
        }
    }

    private func attendanceLine(_ title: String, _ c: AttendanceCounts) -> some View {
        HStack(spacing: 14) {
            Text(title).font(.callout.weight(.medium)).frame(width: 110, alignment: .leading)
            numberCell("gyermek", c.children)
            numberCell("felnőtt adventista", c.adults)
            numberCell("felnőtt vendég", c.guests)
        }
    }

    private func numberCell(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            copyable(String(value), bold: true)
        }
    }

    private var attendanceTable: some View {
        let rows = attendanceRowsList
        let wCheck: CGFloat = 30, wDay: CGFloat = 86, wName: CGFloat = 150, wNum: CGFloat = 92
        return GeometryReader { geo in ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: wCheck, height: 1)
                    Text("Dátum").frame(width: wDay, alignment: .leading)
                    Text("Gyülekezet").frame(width: wName, alignment: .leading)
                    ForEach(["Szombatiskola", "Istentisztelet"], id: \.self) { g in
                        VStack(spacing: 2) {
                            Rectangle().fill(palette.accent).frame(height: 4)
                            Text(g)
                            HStack(spacing: 0) {
                                Text("gyermek").frame(width: wNum)
                                Text("felnőtt adv.").frame(width: wNum)
                                Text("felnőtt vendég").frame(width: wNum)
                            }.font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        .frame(width: wNum * 3)
                    }
                }
                .font(.system(size: 11, weight: .semibold)).padding(.vertical, 5)
                Divider()
                if rows.isEmpty { empty("Ebben a hónapban nincs esedékes létszámjelentő.") }
                ForEach(rows, id: \.id) { r in
                    let key = "l|" + r.key + "|" + r.congregation
                    HStack(spacing: 0) {
                        Group { if r.report != nil { doneButton(key, r.signature) } else { Color.clear.frame(height: 1) } }.frame(width: wCheck)
                        Text(Self.dayFormat.string(from: r.date)).font(.system(size: 12, weight: .medium)).frame(width: wDay, alignment: .leading)
                        Text(r.congregation).font(.system(size: 12)).frame(width: wName, alignment: .leading)
                        if let rep = r.report {
                            let vals = [rep.sabbathSchool.children, rep.sabbathSchool.adults, rep.sabbathSchool.guests,
                                        rep.worship.children, rep.worship.adults, rep.worship.guests]
                            ForEach(0..<vals.count, id: \.self) { i in
                                copyable(String(vals[i]), width: wNum, alignment: .center, bold: true)
                            }
                        } else {
                            Text("hiányzik").font(.caption).foregroundStyle(Theme.warn)
                        }
                    }
                    .opacity(checklist.isDone(key, r.signature) ? 0.45 : 1)
                    Divider().opacity(0.5)
                }
            }
            .padding(16)
            .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
        } }
    }

    // MARK: Közös elemek

    private func empty(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).padding(20)
    }

    struct Chip: Identifiable {
        let id = UUID()
        let text: String
        let color: Color
    }

    /// Hónap-rács: a hét kezdőnapja a Naptár beállítás szerint, a cellákban színes címkék.
    private func monthGrid(chips: @escaping (Date) -> [Chip]) -> some View {
        let days = OTSManual.monthDays(year: year, month: month)
        let first = days.first ?? today
        let start = DateUtil.startOfWeek(first, firstWeekday: weekStart)
        var cells: [Date] = []
        var d = start
        var n = 0
        while n < 42 {
            cells.append(d)
            d = DateUtil.addDays(d, 1)
            n += 1
            if n % 7 == 0, let last = days.last, d > last { break }
        }
        let names = weekStart == 1 ? ["V", "H", "K", "Sze", "Cs", "P", "Szo"] : ["H", "K", "Sze", "Cs", "P", "Szo", "V"]
        let rowsCount = cells.count / 7
        return ScrollView {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(names, id: \.self) { Text($0).font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
                }
                ForEach(0..<rowsCount, id: \.self) { row in
                    HStack(alignment: .top, spacing: 4) {
                        ForEach(0..<7, id: \.self) { col in
                            let day = cells[row * 7 + col]
                            let inMonth = DateUtil.components(day).month == month
                            let list = inMonth ? chips(day) : []
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(DateUtil.components(day).day)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(inMonth ? (isWeekend(day) ? Theme.stop.opacity(0.85) : Color.primary) : Color.secondary.opacity(0.4))
                                ForEach(list.prefix(5)) { c in
                                    HStack(spacing: 3) {
                                        RoundedRectangle(cornerRadius: 1.5).fill(c.color).frame(width: 3)
                                        Text(c.text).font(.system(size: 10)).lineLimit(2)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 1).padding(.horizontal, 3)
                                    .background(RoundedRectangle(cornerRadius: 3).fill(c.color.opacity(0.16)))
                                }
                                if list.count > 5 { Text("+\(list.count - 5)").font(.system(size: 9)).foregroundStyle(.secondary) }
                                Spacer(minLength: 0)
                            }
                            .padding(4)
                            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(inMonth ? 0.05 : 0.02)))
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Ablak

final class OTSManualWindow: NSObject, NSWindowDelegate {
    static let shared = OTSManualWindow()
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let hosting = NSHostingController(rootView: OTSManualView().environmentObject(model))
            // Rögzített méret, nem a tartalom szabja meg (lásd CLAUDE.md: az ablak nem nőhet a képernyőnél nagyobbra).
            if #available(macOS 13.0, *) { hosting.sizingOptions = [] }
            let w = NSWindow(contentViewController: hosting)
            w.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            w.title = "Kézi felvitel az OTS-be"
            w.isReleasedWhenClosed = false
            let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            let size = NSSize(width: min(1020, max(640, visible.width - 80)), height: min(720, max(420, visible.height - 100)))
            w.setContentSize(size)
            w.contentMinSize = NSSize(width: 640, height: 400)
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
