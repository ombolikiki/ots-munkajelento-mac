import SwiftUI

/// Heti naptárnézet: a rögzített bejegyzések idősávként látszanak, egérrel húzva új idősáv jelölhető ki.
struct CalendarTabView: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject var m: AppModel
    @Environment(\.compact) private var compact

    @AppStorage("cal.weekStart") private var weekFirst = 2          // 1 = vasárnap, 2 = hétfő
    @AppStorage("cal.startHour") private var startHourSetting = 7
    @AppStorage("cal.endHour") private var endHourSetting = 20
    @State private var weekStart: Date = DateUtil.startOfWeek(Date(), firstWeekday: UserDefaults.standard.integer(forKey: "cal.weekStart"))
    @State private var dragDay: Date?
    @State private var scrolled = false

    private var hourHeight: CGFloat { compact ? 22 : 28 }
    private let timeColumn: CGFloat = 30
    /// A rács szélessége. A görgetősáv rejtett (a görgetés kerékkel/érintőpaddel megy), így a fejléc, a sáv és a rács oszlopai gépfüggetlenül egy vonalba esnek.
    private let scrollerWidth: CGFloat = 0
    @Environment(\.availableSize) private var available
    @Environment(\.detached) private var detached
    /// A rács szélessége: a menüsori ablakban rögzített, a leválasztott ablakban az ablak szélességét követi.
    private var gridWidth: CGFloat {
        let base: CGFloat = compact ? 286 : 374
        guard detached, available.width > 0 else { return base }
        let contentPadding: CGFloat = (compact ? 8 : 14) * 2
        let cardPadding: CGFloat = 8 * 2
        return min(max(base, available.width - contentPadding - cardPadding - scrollerWidth - 6), 860)
    }
    /// A rács látható magassága: a leválasztott ablakban a magasabb ablak több órát mutat.
    private var viewportHeight: CGFloat {
        let base: CGFloat = compact ? 160 : 230
        guard detached, available.height > 0 else { return base }
        let extra = max(0, available.height - (compact ? 720 : 840))
        return base + min(extra * 0.7, 360)
    }
    private var dayWidth: CGFloat { (gridWidth - timeColumn) / 7 }

    private var currentWeekStart: Date { DateUtil.startOfWeek(Date(), firstWeekday: weekFirst) }

    private var days: [Date] {
        (0..<7).map { DateUtil.addDays(weekStart, $0) }
    }

    private var weekEntries: [Date: [Entry]] {
        var result: [Date: [Entry]] = [:]
        for d in days { result[d] = m.entries(on: d) }
        return result
    }

    /// A beállított munkanap sávja (kezdő és záró óra), érvényesítve.
    private var bandHours: (lo: Int, hi: Int) {
        let lo = min(max(startHourSetting, 0), 22)
        let hi = min(max(endHourSetting, lo + 1), 24)
        return (lo, hi)
    }

    /// A rácsban megjelenő óra-sorok: a kezdő órától a záró óra előtti utolsó óráig.
    private var hourRange: ClosedRange<Int> {
        let b = bandHours
        return b.lo...max(b.lo, b.hi - 1)
    }

    /// Hány időponttal rögzített bejegyzés lóg ki a látható sávból az adott napon.
    private func outsideCount(_ entries: [Entry]) -> Int {
        let b = bandHours
        let cal = DateUtil.gregorian
        return entries.filter { e in
            guard let s = e.start, let en = e.end else { return false }
            let sm = cal.component(.hour, from: s) * 60 + cal.component(.minute, from: s)
            let em = cal.isDate(en, inSameDayAs: s) ? cal.component(.hour, from: en) * 60 + cal.component(.minute, from: en) : 24 * 60
            return sm < b.lo * 60 || em > b.hi * 60
        }.count
    }

    var body: some View {
        let range = hourRange
        let entriesByDay = weekEntries
        VStack(alignment: .leading, spacing: 6) {
            nav
            // a fejléc és a sáv ugyanolyan széles és ugyanoda igazított, mint a görgethető rács (a napok az oszlopuk fölé esnek)
            dayHeader.frame(maxWidth: .infinity, alignment: .center)
            allDayStrip(entriesByDay).frame(maxWidth: .infinity, alignment: .center)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    grid(range: range, entriesByDay: entriesByDay)
                        .frame(width: gridWidth, height: CGFloat(range.count) * hourHeight, alignment: .topLeading)
                        .padding(.vertical, 7)
                        .id("grid")
                }
                .frame(width: gridWidth, height: viewportHeight)
                .frame(maxWidth: .infinity, alignment: .center)
                .onAppear { scrolled = true }
            }
            Text(compact ? "Húzással jelölj ki új idősávot." : "Húzd az egeret az üres idősávon új bejegyzés kijelöléséhez (jövőbeli nap nem választható).")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
        .onChange(of: weekFirst) { newValue in
            weekStart = DateUtil.startOfWeek(weekStart, firstWeekday: newValue)
            m.pendingSlot = nil
        }
    }

    // MARK: Fejléc

    private static let weekFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "MMM d."
        return f
    }()
    private static let dayName: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "EEE"
        return f
    }()

    private var nav: some View {
        HStack {
            Button { shiftWeek(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain)
            Spacer()
            Text("\(Self.weekFormatter.string(from: weekStart)) – \(Self.weekFormatter.string(from: days.last ?? weekStart))")
                .font(.subheadline.weight(.medium))
            Spacer()
            Button("Ma") {
                weekStart = currentWeekStart
                m.selectedDay = Date()
            }
            .buttonStyle(.plain).font(.caption).foregroundStyle(palette.accent)
            Button { shiftWeek(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
                .disabled(isCurrentWeek)
                .opacity(isCurrentWeek ? 0.3 : 1)
        }
        .padding(.horizontal, 2)
    }

    private var isCurrentWeek: Bool { weekStart >= currentWeekStart }

    private func shiftWeek(_ n: Int) {
        if n > 0 && isCurrentWeek { return }
        weekStart = DateUtil.addDays(weekStart, 7 * n)
        m.pendingSlot = nil
    }

    private var dayHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: timeColumn, height: 1)
            ForEach(days, id: \.self) { d in
                let isToday = DateUtil.gregorian.isDateInToday(d)
                let selected = DateUtil.gregorian.isDate(d, inSameDayAs: m.selectedDay)
                let future = m.isFuture(d)
                Button { if !future { m.selectedDay = d } } label: {
                    VStack(spacing: 1) {
                        Text(Self.dayName.string(from: d)).font(.system(size: 10)).foregroundStyle(.secondary)
                        Text("\(DateUtil.gregorian.component(.day, from: d))")
                            .font(.system(size: 12, weight: isToday || selected ? .semibold : .regular))
                            .frame(width: 22, height: 22)
                            .foregroundStyle(isToday ? Color.white : Color.primary)
                            .background(Circle().fill(isToday ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(Color.clear)))
                            .overlay(Circle().strokeBorder(selected && !isToday ? palette.accent : Color.clear, lineWidth: 1.5))
                        Circle().fill(targetColor(d)).frame(width: 5, height: 5)
                            .help("Nincs meg a napi \(m.targetHours) óra")
                    }
                    .frame(width: dayWidth)
                    .opacity(future ? 0.35 : 1)
                }
                .buttonStyle(.plain)
                .disabled(future)
            }
        }
        .frame(width: gridWidth)
    }

    /// Piros = múltbeli nap, nincs meg a napi óraszám; narancs = a mai nap még folyamatban; egyébként átlátszó.
    private func targetColor(_ d: Date) -> Color {
        switch m.targetState(on: d) {
        case .short: return Theme.stop
        case .inProgress: return Theme.warn.opacity(0.8)
        default: return Color.clear
        }
    }

    // MARK: Időponttal nem rendelkező bejegyzések (óraszám, alkalom/fő, egész nap)

    @ViewBuilder private func allDayStrip(_ byDay: [Date: [Entry]]) -> some View {
        let untimed = byDay.mapValues { $0.filter { $0.start == nil || $0.end == nil } }
        let outside = byDay.mapValues { outsideCount($0) }
        if untimed.values.contains(where: { !$0.isEmpty }) || outside.values.contains(where: { $0 > 0 }) {
            HStack(alignment: .top, spacing: 0) {
                Text("nap").font(.system(size: 8)).foregroundStyle(.secondary)
                    .frame(width: timeColumn - 4, alignment: .trailing).padding(.trailing, 4)
                ForEach(days, id: \.self) { d in
                    VStack(spacing: 2) {
                        let list = untimed[d] ?? []
                        ForEach(list.prefix(3)) { e in
                            Text(tag(e))
                                .font(.system(size: 8, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 2)
                                .foregroundStyle(.white)
                                .background(RoundedRectangle(cornerRadius: 3).fill(color(for: e)))
                                .onTapGesture { m.selectedDay = d }
                                .help(help(for: e))
                        }
                        if list.count > 3 {
                            Text("+\(list.count - 3)").font(.system(size: 8)).foregroundStyle(.secondary)
                        }
                        if let n = outside[d], n > 0 {
                            Text("↕ \(n)")
                                .font(.system(size: 8, weight: .semibold))
                                .padding(.horizontal, 3).padding(.vertical, 1)
                                .foregroundStyle(Theme.stop)
                                .background(Capsule().fill(Theme.stop.opacity(0.14)))
                                .help("\(n) bejegyzés a beállított munkanapon (\(bandHours.lo):00–\(bandHours.hi):00) kívül van")
                        }
                    }
                    .frame(width: dayWidth - 2)
                    .padding(.horizontal, 1)
                }
            }
            .frame(width: gridWidth, alignment: .leading)
        }
    }

    private func tag(_ e: Entry) -> String {
        switch e.unit {
        case Unit.hours.rawValue: return "\(Fmt.hm(e.durationSeconds)) \(e.activityType?.shortLabel ?? e.typeLabel)"
        case Unit.occasions.rawValue: return "\(e.quantity ?? 1)× \(e.activityType?.shortLabel ?? e.typeLabel)"
        case Unit.people.rawValue: return "\(e.quantity ?? 1) fő"
        default: return e.activityType?.shortLabel ?? e.typeLabel
        }
    }

    // MARK: Rács

    private func grid(range: ClosedRange<Int>, entriesByDay: [Date: [Entry]]) -> some View {
        ZStack(alignment: .topLeading) {
            // óravonalak és címkék
            ForEach(Array(range), id: \.self) { h in
                let y = CGFloat(h - range.lowerBound) * hourHeight
                Text(String(format: "%02d", h))
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .frame(width: timeColumn - 4, alignment: .trailing)
                    .offset(x: 0, y: y - 5)
                Rectangle().fill(Color.primary.opacity(0.08))
                    .frame(width: gridWidth - timeColumn, height: 1)
                    .offset(x: timeColumn, y: y)
            }
            // naposzlopok
            ForEach(Array(days.enumerated()), id: \.element) { (i, d) in
                dayColumn(day: d, range: range, entries: entriesByDay[d] ?? [])
                    .offset(x: timeColumn + CGFloat(i) * dayWidth, y: 0)
            }
        }
    }

    private func dayColumn(day: Date, range: ClosedRange<Int>, entries: [Entry]) -> some View {
        let selected = DateUtil.gregorian.isDate(day, inSameDayAs: m.selectedDay)
        let future = m.isFuture(day)
        let isToday = DateUtil.gregorian.isDateInToday(day)
        let nowMin = DateUtil.gregorian.component(.hour, from: Date()) * 60 + DateUtil.gregorian.component(.minute, from: Date())
        let origin = range.lowerBound * 60
        let total = range.count * 60
        let placed = layout(entries.filter { $0.start != nil && $0.end != nil })
            .compactMap { p -> Placed? in
                var q = p
                let q0 = max(p.startMin, origin), q1 = min(p.endMin, origin + total)
                guard q1 > q0 else { return nil }   // teljesen a sávon kívül: nem rajzoljuk
                q = Placed(entry: p.entry, startMin: q0, endMin: q1, lane: p.lane, lanes: p.lanes)
                return q
            }
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(future ? Color.primary.opacity(0.06) : (selected ? palette.accent.opacity(0.07) : Color.clear))
                .overlay(Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1), alignment: .leading)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { g in
                            if future { return }
                            let a = snap(minutes(at: g.startLocation.y, origin: origin, total: total))
                            let b = snap(minutes(at: g.location.y, origin: origin, total: total))
                            var lo = min(a, b), hi = max(a, b)
                            if hi - lo < 15 { hi = lo + 15 }
                            hi = min(hi, origin + total)
                            lo = min(lo, hi - 15)
                            if isToday {   // a mai napon a jövőbeli rész nem jelölhető ki
                                let limit = (nowMin / 15) * 15
                                hi = min(hi, limit)
                                if hi - lo < 15 { return }
                            }
                            m.pendingSlot = AppModel.PendingSlot(day: day, startMin: lo, endMin: hi)
                            m.selectedDay = day
                        }
                )
                .simultaneousGesture(TapGesture().onEnded { if !future { m.selectedDay = day } })

            ForEach(placed, id: \.entry.id) { p in
                block(p, origin: origin)
            }

            if let slot = m.pendingSlot, DateUtil.gregorian.isDate(slot.day, inSameDayAs: day) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(palette.accent.opacity(0.25))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(palette.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                    .frame(width: dayWidth - 3, height: max(6, CGFloat(slot.endMin - slot.startMin) / 60 * hourHeight))
                    .offset(x: 1.5, y: CGFloat(slot.startMin - origin) / 60 * hourHeight)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: dayWidth, height: CGFloat(range.count) * hourHeight)
        .clipped()
    }

    private func block(_ p: Placed, origin: Int) -> some View {
        let w = (dayWidth - 3) / CGFloat(p.lanes)
        let h = max(8, CGFloat(p.endMin - p.startMin) / 60 * hourHeight - 1)
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color(for: p.entry).opacity(0.9))
            .overlay(
                Text(p.entry.activityType?.shortLabel ?? p.entry.typeLabel)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(.horizontal, 2).padding(.top, 1),
                alignment: .topLeading
            )
            .frame(width: w - 1, height: h)
            .offset(x: 1.5 + CGFloat(p.lane) * w, y: CGFloat(p.startMin - origin) / 60 * hourHeight)
            .onTapGesture { m.selectedDay = DateUtil.gregorian.startOfDay(for: p.entry.start ?? Date()) }
            .help(help(for: p.entry))
    }

    // MARK: Segédek

    private func minutes(at y: CGFloat, origin: Int, total: Int) -> Int {
        let raw = Int((y / hourHeight * 60).rounded()) + origin
        return min(max(raw, origin), origin + total)
    }

    private func snap(_ min: Int) -> Int { Int((Double(min) / 15).rounded()) * 15 }

    private func help(for e: Entry) -> String {
        [e.typeLabel, e.workplace, e.activity].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func color(for e: Entry) -> Color { CategoryColors.color(code: e.type) }

    struct Placed {
        let entry: Entry
        let startMin: Int
        let endMin: Int
        var lane: Int
        var lanes: Int
    }

    /// Az egymást átfedő bejegyzések egymás mellé kerülnek (sávokra osztva).
    private func layout(_ items: [Entry]) -> [Placed] {
        let cal = DateUtil.gregorian
        func minuteOfDay(_ d: Date) -> Int { cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d) }
        var base: [Placed] = items.compactMap { e in
            guard let s = e.start, let en = e.end else { return nil }
            let sm = minuteOfDay(s)
            var em = cal.isDate(en, inSameDayAs: s) ? minuteOfDay(en) : 24 * 60
            em = max(em, sm + 10)
            return Placed(entry: e, startMin: sm, endMin: em, lane: 0, lanes: 1)
        }
        base.sort { $0.startMin < $1.startMin }

        var result: [Placed] = []
        var cluster: [Placed] = []
        var laneEnds: [Int] = []
        var clusterEnd = -1
        for var p in base {
            if !cluster.isEmpty, p.startMin >= clusterEnd {
                for var c in cluster { c.lanes = laneEnds.count; result.append(c) }
                cluster = []; laneEnds = []; clusterEnd = -1
            }
            if let lane = laneEnds.firstIndex(where: { $0 <= p.startMin }) {
                laneEnds[lane] = p.endMin
                p.lane = lane
            } else {
                laneEnds.append(p.endMin)
                p.lane = laneEnds.count - 1
            }
            cluster.append(p)
            clusterEnd = max(clusterEnd, p.endMin)
        }
        for var c in cluster { c.lanes = laneEnds.count; result.append(c) }
        return result
    }
}

/// Az új, kijelölt idősáv adatainak megadása a Naptár lapon.
struct PendingPanel: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject var m: AppModel

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "MMM d., EEEE"
        return f
    }()

    var body: some View {
        if let slot = m.pendingSlot {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "plus.circle.fill").foregroundStyle(palette.accent)
                    Text("Új bejegyzés: \(Self.dayFormatter.string(from: slot.day)), \(hm(slot.startMin))–\(hm(slot.endMin))")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                FieldsView()
                HStack(spacing: 10) {
                    BigButton(title: "Rögzítés", symbol: "checkmark", color: palette.accent, enabled: m.fieldsComplete) {
                        m.commitPending()
                    }
                    Button("Mégse") { m.pendingSlot = nil }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                }
                if let h = m.missingFieldsHint { Hint(text: h) }
            }
        }
    }

    private func hm(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
}
