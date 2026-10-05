import SwiftUI

/// Szám beviteli mező (csak számjegyek, 0–99 999).
struct CountField: View {
    @Binding var value: Int

    var body: some View {
        TextField("0", text: Binding(
            get: { value == 0 ? "" : String(value) },
            set: { value = min(99_999, Int($0.filter(\.isNumber)) ?? 0) }
        ))
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
    }
}

/// A gyülekezeti létszámjelentő kártyája: az esedékes szombaton beviteli űrlap, egyébként a lemaradt dátumok listája.
/// Nincs külön lapfül: a napi lista alatt jelenik meg, csak ha van tennivaló.
struct AttendanceCard: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.compact) private var compact
    @Environment(\.attendanceBlocks) private var blocks
    @Environment(\.palette) private var palette
    @AppStorage("missing.lookback") private var lookback = "thisMonth"
    @State private var drafts: [String: AttendanceReport] = [:]
    @State private var loadedKey = ""
    @State private var message: String?

    private static var lookbackSetting: String { UserDefaults.standard.string(forKey: "missing.lookback") ?? "thisMonth" }

    /// A kiválasztott nap esedékes létszámjelentő nap, és nem a jövőben van.
    static func formVisible(_ m: AppModel) -> Bool {
        m.attendanceEnabled && m.isAttendanceDue(on: m.selectedDay) && !m.isFuture(m.selectedDay)
    }

    static func isVisible(_ m: AppModel) -> Bool {
        formVisible(m) || !m.pendingAttendanceDates(lookback: lookbackSetting).isEmpty
    }

    /// Egy gyülekezet blokkjának magassága (név + két sor) a kitöltési űrlapon, a köztes hellyel együtt.
    /// Normál nézetben gyülekezetenként egy táblázatsor, kompakt nézetben (szűk hely) egy három soros blokk.
    static func blockHeight(compact: Bool) -> CGFloat { compact ? 86 : 34 }
    /// A legtöbb ennyi gyülekezet látszik egyszerre a normál nézetben, kompaktban 3.
    static func maxBlocks(compact: Bool) -> Int { compact ? 3 : 6 }
    /// A gyülekezet-blokkok listájának magassága: legfeljebb `blocks` blokk látszik egyszerre, a többi görgetéssel érhető el.
    static func listHeight(_ count: Int, blocks: Int, compact: Bool) -> CGFloat {
        CGFloat(min(max(count, 1), max(blocks, 1))) * blockHeight(compact: compact)
    }

    /// Az űrlap blokklistán kívüli része (fejléc, oszlopcímek, Mentés gomb, kártya-keret).
    static func formChrome(compact: Bool) -> CGFloat { compact ? 96 : 150 }

    /// Becsült magasság (a napi lista görgethető részének méretezéséhez).
    static func estimatedHeight(_ m: AppModel, compact: Bool, blocks: Int) -> CGFloat {
        if formVisible(m) {
            return listHeight(m.attendanceCongregations.count, blocks: blocks, compact: compact) + formChrome(compact: compact)
        }
        return compact ? 56 : 66
    }

    private var fieldWidth: CGFloat { compact ? 52 : 74 }
    private var labelWidth: CGFloat { compact ? 70 : 90 }

    var body: some View {
        if AttendanceCard.formVisible(m) {
            form
        } else {
            let pending = m.pendingAttendanceDates(lookback: lookback)
            if !pending.isEmpty { pendingList(pending) }
        }
    }

    // MARK: Űrlap

    private var day: Date { m.selectedDay }
    private var key: String { Fmt.dayFormatter.string(from: day) }
    private var saved: [AttendanceReport] { m.reports(on: day) }
    private var complete: Bool { saved.count == m.attendanceCongregations.count && !saved.isEmpty }
    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    private var form: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.3.fill").foregroundStyle(palette.accent)
                Text("Gyülekezeti létszámjelentő").font(.subheadline.weight(.semibold))
                Spacer()
                if complete {
                    Label("Mentve", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Theme.go)
                } else {
                    Text(isToday ? "Ma esedékes" : "Kitöltetlen")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.warn)
                }
            }
            if compact { blockLayout } else { tableLayout }
            HStack(spacing: 10) {
                BigButton(title: complete ? "Frissítés" : "Mentés", symbol: "checkmark", color: palette.accent, enabled: true) { save() }
                if let message { Text(message).font(.caption).foregroundStyle(Theme.go) }
            }
        }
        .card()
        .onAppear { load() }
        .onChange(of: key) { _ in load() }
        .onChange(of: m.attendanceCongregations) { _ in load() }
    }

    // MARK: Normál nézet: egy sor gyülekezetenként

    private let nameWidth: CGFloat = 84
    private let cellWidth: CGFloat = 40

    private var tableLayout: some View {
        let groupWidth = cellWidth * 3 + 5 * 2
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("").frame(width: nameWidth)
                Text("Szombatiskola").font(.caption.weight(.semibold)).frame(width: groupWidth)
                Text("Istentisztelet").font(.caption.weight(.semibold)).frame(width: groupWidth)
            }
            HStack(spacing: 10) {
                Text("").frame(width: nameWidth)
                HStack(spacing: 5) { miniCaption("gyerm."); miniCaption("felnőtt"); miniCaption("vendég") }
                HStack(spacing: 5) { miniCaption("gyerm."); miniCaption("felnőtt"); miniCaption("vendég") }
            }
            ScrollView(showsIndicators: m.attendanceCongregations.count > blocks) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(m.attendanceCongregations, id: \.self) { c in
                        HStack(spacing: 10) {
                            Text(c).font(.caption.weight(.semibold)).lineLimit(1).frame(width: nameWidth, alignment: .leading)
                            HStack(spacing: 5) {
                                CountField(value: binding(c, \.sabbathSchool.children)).frame(width: cellWidth)
                                CountField(value: binding(c, \.sabbathSchool.adults)).frame(width: cellWidth)
                                CountField(value: binding(c, \.sabbathSchool.guests)).frame(width: cellWidth)
                            }
                            HStack(spacing: 5) {
                                CountField(value: binding(c, \.worship.children)).frame(width: cellWidth)
                                CountField(value: binding(c, \.worship.adults)).frame(width: cellWidth)
                                CountField(value: binding(c, \.worship.guests)).frame(width: cellWidth)
                            }
                        }
                        .frame(height: AttendanceCard.blockHeight(compact: false) - 6)
                    }
                }
            }
            .frame(height: AttendanceCard.listHeight(m.attendanceCongregations.count, blocks: blocks, compact: false))
        }
    }

    private func miniCaption(_ t: String) -> some View {
        Text(t).font(.system(size: 9)).foregroundStyle(.secondary).frame(width: cellWidth).lineLimit(1).minimumScaleFactor(0.7)
    }

    // MARK: Kompakt nézet: háromsoros blokk gyülekezetenként

    private var blockLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("").frame(width: labelWidth)
                caption("gyermek"); caption("felnőtt adv."); caption("vendég")
            }
            ScrollView(showsIndicators: m.attendanceCongregations.count > blocks) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(m.attendanceCongregations, id: \.self) { c in congregationBlock(c) }
                }
            }
            .frame(height: AttendanceCard.listHeight(m.attendanceCongregations.count, blocks: blocks, compact: true))
        }
    }

    private func caption(_ t: String) -> some View {
        Text(t).font(.system(size: 9)).foregroundStyle(.secondary).frame(width: fieldWidth).lineLimit(1).minimumScaleFactor(0.7)
    }

    private func congregationBlock(_ c: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(c).font(.caption.weight(.semibold))
            countRow("Szombatiskola", \.sabbathSchool, c)
            countRow("Istentisztelet", \.worship, c)
        }
        .frame(height: AttendanceCard.blockHeight(compact: compact), alignment: .top)
    }

    private func countRow(_ title: String, _ path: WritableKeyPath<AttendanceReport, AttendanceCounts>, _ c: String) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: labelWidth, alignment: .leading)
            CountField(value: binding(c, path.appending(path: \.children))).frame(width: fieldWidth)
            CountField(value: binding(c, path.appending(path: \.adults))).frame(width: fieldWidth)
            CountField(value: binding(c, path.appending(path: \.guests))).frame(width: fieldWidth)
        }
    }

    private func binding(_ c: String, _ path: WritableKeyPath<AttendanceReport, Int>) -> Binding<Int> {
        Binding(
            get: { drafts[c]?[keyPath: path] ?? 0 },
            set: { v in
                var r = drafts[c] ?? AttendanceReport(date: key, congregation: c)
                r[keyPath: path] = v
                drafts[c] = r
            }
        )
    }

    private func load() {
        let existing = Dictionary(saved.map { ($0.congregation.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var d: [String: AttendanceReport] = [:]
        for c in m.attendanceCongregations {
            d[c] = existing[c.lowercased()] ?? AttendanceReport(date: key, congregation: c)
        }
        drafts = d
        message = nil
    }

    private func save() {
        let reports = m.attendanceCongregations.map { c in
            var r = drafts[c] ?? AttendanceReport(date: key, congregation: c)
            r.date = key; r.congregation = c
            return r
        }
        m.saveReports(day: day, reports: reports)
        message = "✓ Mentve"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { message = nil }
    }

    // MARK: Lemaradt dátumok

    private func pendingList(_ dates: [Date]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.3.fill").foregroundStyle(Theme.warn)
                Text("Esedékes létszámjelentő").font(.caption.weight(.semibold))
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(dates.reversed(), id: \.self) { d in
                        Button {
                            m.selectedDay = d
                        } label: {
                            Text(Fmt.shortDay.string(from: d))
                                .font(.caption)
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(Capsule().fill(Color.purple.opacity(0.18)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .card()
    }
}
