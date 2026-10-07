import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Stílus és környezet

private struct CompactKey: EnvironmentKey { static let defaultValue = false }
private struct DetachedKey: EnvironmentKey { static let defaultValue = false }
private struct ListBudgetKey: EnvironmentKey { static let defaultValue: CGFloat = 200 }
private struct AvailableSizeKey: EnvironmentKey { static let defaultValue = CGSize.zero }
private struct AttendanceBlocksKey: EnvironmentKey { static let defaultValue = 3 }

extension EnvironmentValues {
    /// Kompakt nézet: kisebb ablak, kevesebb felirat.
    var compact: Bool {
        get { self[CompactKey.self] }
        set { self[CompactKey.self] = newValue }
    }
    /// Igaz, ha a tartalom a leválasztott (külön) ablakban van.
    var detached: Bool {
        get { self[DetachedKey.self] }
        set { self[DetachedKey.self] = newValue }
    }
    /// Hány gyülekezet blokkja látszik egyszerre a létszámjelentő űrlapján (a többi görgethető).
    var attendanceBlocks: Int {
        get { self[AttendanceBlocksKey.self] }
        set { self[AttendanceBlocksKey.self] = newValue }
    }
    /// A leválasztott ablak tartalmi területe (a menüsori ablakban nulla): ehhez igazodik a naptár szélessége és magassága.
    var availableSize: CGSize {
        get { self[AvailableSizeKey.self] }
        set { self[AvailableSizeKey.self] = newValue }
    }
    /// A napi lista legnagyobb magassága a menüsori ablakban (a lap és a további kártyák után megmaradó hely).
    var listBudget: CGFloat {
        get { self[ListBudgetKey.self] }
        set { self[ListBudgetKey.self] = newValue }
    }
}

enum Theme {
    static let go = Color(red: 0.18, green: 0.64, blue: 0.40)
    static let stop = Color(red: 0.85, green: 0.27, blue: 0.27)
    static let warn = Color.orange
}

struct Card: ViewModifier {
    @Environment(\.compact) private var compact

    func body(content: Content) -> some View {
        content
            .padding(compact ? 8 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

extension View {
    func card() -> some View { modifier(Card()) }
}

struct BigButton: View {
    @Environment(\.compact) private var compact
    let title: String
    let symbol: String
    let color: Color
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? 5 : 8)
                .foregroundStyle(.white)
                .background(Capsule().fill(enabled ? color : Color.gray.opacity(0.4)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct Hint: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.caption)
            .foregroundStyle(Theme.warn)
    }
}

struct IconView: View {
    let choice: IconChoice
    var body: some View {
        switch choice.kind {
        case .symbol(let name): Image(systemName: name)
        case .emoji(let e): Text(e)
        case .logo: Image(nsImage: MenuImages.adventist).renderingMode(.template)
        }
    }
}

// MARK: - Fő nézet

struct ContentView: View {
    var detached = false
    @EnvironmentObject var m: AppModel
    @AppStorage("compact") private var compactSetting = false
    @AppStorage("palette") private var paletteID = "blue"
    @State private var showSettings = false
    @StateObject private var panel = PanelController.shared

    /// Alacsony képernyőn (kisebb a látható rész 880 pontnál) az ablak mindig kompakt, hogy beférjen.
    static var smallScreen: Bool { visibleHeight < 880 }

    /// A képernyő látható magassága (tesztben az `OTS_VISIBLE_HEIGHT` felülbírálhatja, kisebb kijelzők szimulálásához).
    static var visibleHeight: CGFloat {
        if let o = ProcessInfo.processInfo.environment["OTS_VISIBLE_HEIGHT"], let v = Double(o), v > 100 { return CGFloat(v) }
        return NSScreen.main?.visibleFrame.height ?? 900
    }
    private var compact: Bool { compactSetting || Self.smallScreen }
    private var palette: Palette { Palette.byID(paletteID) }

    /// A tartalom legnagyobb magassága: a képernyő látható részénél mindig kisebb, különben az ablak
    /// méretezése végtelen ciklusba kerülhet, és a rendszer leállítja az alkalmazást.
    static var maxContentHeight: CGFloat {
        return max(360, visibleHeight - 90)
    }

    var body: some View {
        let width: CGFloat = compact ? 340 : 440
        let base = content.padding(compact ? 8 : 14)
        Group {
            if detached {
                // A leválasztott ablak mérete az ablak átméretezésével változik (szélesség és magasság is):
                // a tartalom kitölti a szélességet, és görgethető. Az ablak mérete nem a tartalomtól függ.
                GeometryReader { geo in
                    ScrollView(.vertical, showsIndicators: true) {
                        base.frame(maxWidth: .infinity)
                    }
                    .environment(\.availableSize, geo.size)
                }
                .frame(minWidth: width, maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
            } else {
                // A menüsori ablak a tartalom természetes magasságát veszi fel. A hosszú részek
                // (napi lista, beállítások) saját, rögzített magasságú görgethető területet kapnak,
                // így az ablak soha nem nő a képernyőnél magasabbra. A végső korlát biztonsági háló:
                // ha valamelyik becslés mégis kevés lenne, az ablak akkor sem lépheti túl a képernyőt
                // (a túllógó rész levágódik, de az alkalmazás nem omlik össze).
                let padded = base.frame(width: width)
                if ProcessInfo.processInfo.environment["OTS_NO_HEIGHT_CLAMP"] != nil {
                    padded   // csak diagnosztikához: a becslések pontosságának mérése a végső korlát nélkül
                } else {
                    padded
                        .frame(maxHeight: Self.maxContentHeight, alignment: .top)
                        .clipped()
                }
            }
        }
        .environment(\.compact, compact)
        .environment(\.detached, detached)
        .environment(\.palette, palette)
        .environment(\.listBudget, listBudget)
        .environment(\.attendanceBlocks, attendanceBlocks)
        .onAppear { m.reloadIfChanged(); m.reloadAttendanceIfChanged() }
        // Ha a menüsori ablakot bezárják (ikonra vagy kívülre kattintva), újranyitáskor a rögzítő oldal jön, nem a Beállítások.
        .onChange(of: panel.menuHiddenCount) { if !detached { showSettings = false } }
        .background(
            WindowReader { window in
                if !detached { PanelController.shared.menuWindow = window }
            }
        )
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            header
            if !showSettings, m.reminderActive { reminderBanner }
            if showSettings {
                SettingsTabBar()
                if detached {
                    SettingsView()
                } else {
                    ScrollView { SettingsView() }
                        .frame(height: min(590, Self.maxContentHeight - 165))
                }
            } else {
                ModeTabs()
                switch m.mode {
                case .timer:
                    FieldsView().zIndex(2)   // a javaslatlista a lentebbi kártyákra takar rá
                    StopwatchView().card()
                case .manual:
                    FieldsView().zIndex(2)
                    ManualView().card()
                case .pomodoro:
                    FieldsView().zIndex(2)
                    PomodoroView().card()
                case .calendar:
                    CalendarTabView()
                    PendingPanel()
                }
                if !hideLower {
                    if !squeezed { DayListView().card() }
                    AttendanceCard()
                    if !squeezed { MissingDaysView() }
                }
                if kmTrack { monthKmLine }
                if !compact { footer }
            }
            if let err = m.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
            } else if let note = m.notice {
                Text(note).font(.caption).foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @AppStorage("km.track") private var kmTrack = false

    /// A hónap (a kiválasztott napé) autós km-ei összesen; csak ha a Beállításokban be van kapcsolva a km-állások vezetése.
    private var monthKmLine: some View {
        let r = m.monthKm(containing: m.selectedDay)
        let c = DateUtil.components(m.selectedDay)
        let name = Fmt.monthName(year: c.year, month: c.month)
        return HStack(spacing: 6) {
            Image(systemName: "car.fill").font(.caption2)
            Text("\(name): \(r.km) km")
                .font(.caption.weight(.medium)).monospacedDigit()
            if r.incomplete > 0 {
                Text("(\(r.incomplete) útnál hiányzik a km-állás)").font(.caption2)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 2)
        .help("Az Utazás bejegyzések km-óra állásainak különbsége a hónapban (csak a két állással rögzített utak)")
    }

    private var header: some View {
        HStack(spacing: compact ? 6 : 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette.gradient)
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: compact ? 12 : 15, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: compact ? 24 : 32, height: compact ? 24 : 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(compact ? "Munkajelentő" : AppModel.appName)
                    .font(.system(size: compact ? 12.5 : 14, weight: .semibold))
                if !compact {
                    Text(todaySummary).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if compact {
                Text(shortSummary).font(.caption2).foregroundStyle(.secondary)
            }
            if m.skillUpdateAvailable {
                Button { m.updateSkill() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: compact ? 12 : 14))
                        .foregroundStyle(Theme.warn)
                }
                .buttonStyle(.plain)
                .help("Frissült az OTS Adminisztráció skill: kattints, és a gépeden lévő skill frissül (a régiről másolat készül)")
            }
            headerButton("tablecells.badge.ellipsis", help: "Kézi felvitel az OTS-be: a bejegyzések listája és táblázata") {
                OTSManualWindow.shared.show(model: m)
            }
            headerButton(compact ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left",
                         help: compact ? "Normál nézet" : "Kompakt nézet") { compactSetting.toggle() }
            if detached {
                headerButton(panel.isPinned ? "pin.fill" : "pin.slash",
                             help: panel.isPinned ? "Mindig legfelül (kattintásra kikapcsol)" : "Mindig legfelül") {
                    panel.togglePin()
                }
            } else {
                headerButton("macwindow.badge.plus", help: "Leválasztás: külön, mozgatható ablak") {
                    PanelController.shared.show(model: m)
                    if let key = NSApp.keyWindow, key !== PanelController.shared.window { key.orderOut(nil) }
                }
            }
            headerButton(showSettings ? "xmark.circle.fill" : "gearshape", help: showSettings ? "Vissza" : "Beállítások") {
                showSettings.toggle()
            }
        }
    }

    private func headerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 12 : 14))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Ha a Pomo-beállítások vagy az új naptári bejegyzés űrlapja nyitva van, a lista és a hiányzó napok rejtve vannak, hogy az ablak ne nőjön túl magasra.
    private var hideLower: Bool {
        (m.mode == .pomodoro && m.pomoSettingsOpen) || (m.mode == .calendar && m.pendingSlot != nil)
    }

    /// A tartalom mért magassága üres napnál (a napi lista soraitól eltekintve), laponként: ebből számoljuk, mennyi hely marad a napi listának.
    /// Ha ez elmarad a valóságtól, a felületi terhelési teszt (scripts/selftest.sh) jelzi.
    private var baseHeight: CGFloat {
        switch (compact, m.mode) {
        case (false, .timer): return 581
        case (false, .manual): return 552
        case (false, .pomodoro): return 673
        case (false, .calendar): return 665
        case (true, .timer): return 408
        case (true, .manual): return 395
        case (true, .pomodoro): return 478
        case (true, .calendar): return 496
        }
    }

    /// Mennyi hely marad a napi lista soraira a képernyőn.
    private var listBudget: CGFloat { max(60, Self.maxContentHeight - baseHeight - extraLowerHeight - 24) }

    private var reminderHeight: CGFloat { compact ? 44 : 54 }

    /// Kis kijelzőn a létszámjelentő űrlapja kiszorítja a napi listát és a kitöltetlen napokat, hogy az ablak beférjen.
    private var squeezed: Bool { Self.smallScreen && m.attendanceEnabled && AttendanceCard.formVisible(m) }

    /// Hány gyülekezet blokkja látszik az űrlapon: a legtöbb, ami még belefér az ablakba.
    private var attendanceBlocks: Int {
        guard m.attendanceEnabled, AttendanceCard.formVisible(m) else { return AttendanceCard.maxBlocks(compact: compact) }
        let others = baseHeight + (m.reminderActive ? reminderHeight : 0) + (squeezed ? -140 : 60) + 24
        for n in Array((1...AttendanceCard.maxBlocks(compact: compact)).reversed()) {
            if others + AttendanceCard.formChrome(compact: compact) + AttendanceCard.listHeight(m.attendanceCongregations.count, blocks: n, compact: compact) + 24 <= Self.maxContentHeight {
                return n
            }
        }
        return 1
    }

    /// A napi lista alatti további kártyák (emlékeztető, létszámjelentő) becsült magassága: a napi lista ennyivel kevesebb helyet kap.
    private var extraLowerHeight: CGFloat {
        var h: CGFloat = 0
        if m.reminderActive { h += reminderHeight }
        if kmTrack { h += 22 }                                              // a havi km sora
        if m.mode != .calendar, m.selectedType?.isTravel == true { h += compact ? 30 : 34 }   // a km-órás sor az Utazás űrlapján
        if m.attendanceEnabled, AttendanceCard.isVisible(m) { h += AttendanceCard.estimatedHeight(m, compact: compact, blocks: attendanceBlocks) + 24 }
        return h
    }

    private var reminderBanner: some View {
        let n = m.consecutiveMissing
        return HStack(spacing: 8) {
            IconView(choice: IconSets.choice(UserDefaults.standard.string(forKey: "menuIcon.reminder") ?? "warning", in: IconSets.reminder))
                .foregroundStyle(Theme.stop)
            Text("\(n) napja nem írtál munkajelentőt.")
                .font(.system(size: compact ? 11.5 : 12.5, weight: .semibold))
            Spacer(minLength: 4)
            Button("Kézi bevitel") {
                m.selectedDay = DateUtil.addDays(Date(), -1)
                m.mode = .manual
            }
            .buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(palette.accent)
        }
        .padding(.horizontal, 10).padding(.vertical, compact ? 6 : 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.stop.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stop.opacity(0.35), lineWidth: 1))
    }

    private var todaySummary: String {
        let today = m.entries(on: Date())
        let secs = today.reduce(0) { $0 + $1.creditSeconds }
        return today.isEmpty ? "Ma még nincs bejegyzés" : "Ma: \(Fmt.hm(secs)) óra · \(today.count) bejegyzés"
    }

    private var shortSummary: String {
        let secs = m.entries(on: Date()).reduce(0) { $0 + $1.creditSeconds }
        return "Ma \(Fmt.hm(secs))"
    }

    private var footer: some View {
        HStack {
            Button("Adatfájl megjelenítése") {
                NSWorkspace.shared.activateFileViewerSelecting([m.dataFileURL])
            }
            Spacer()
            Button("Kilépés") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 2)
    }
}

struct ModeTabs: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject var m: AppModel
    @Environment(\.compact) private var compact

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases) { mode in
                let selected = m.mode == mode
                Button {
                    m.mode = mode
                    if mode != .calendar { m.pendingSlot = nil }
                } label: {
                    Group {
                        if compact {
                            Image(systemName: mode.symbol)
                        } else {
                            Label(mode.rawValue, systemImage: mode.symbol)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, compact ? 4 : 6)
                    .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.75))
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selected ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(Color.clear))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(mode.rawValue)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.primary.opacity(0.07)))
    }
}

// MARK: - Közös mezők

struct FieldsView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.compact) private var compact

    private var isTravel: Bool { m.selectedType?.isTravel == true }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            HStack(alignment: .bottom, spacing: compact ? 6 : 10) {
                if (!m.type.isWholeDay || m.selectedType == nil) && !isTravel {
                    labeled("Munkahely") {
                        placeField(text: $m.workplace, prompt: "Munkahely", append: false)
                    }
                }
                labeled("Tevékenység típusa") {
                    TypeSuggestField()
                }
            }

            if isTravel { travelRow }

            if m.type.hasQuantity && m.selectedType != nil {
                HStack {
                    Text("Mennyiség").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Stepper(value: $m.quantity, in: 1...99) {
                        Text("\(m.quantity) \(m.type.quantityUnit)").monospacedDigit()
                    }
                    .fixedSize()
                }
            }

            labeled(activityTitle) {
                SuggestTextField(prompt: activityPrompt, text: $m.activity, candidates: { m.activitySuggestions() })
            }
        }
        .card()
    }

    /// Csak az Utazásnál kötelező a Tevékenység (a Költségelszámolás táblázatba kerül), máshol csak referencia.
    private var activityTitle: String {
        isTravel ? "Tevékenység (kötelező, a Költségelszámoláshoz)" : (m.type.isWholeDay ? "Megjegyzés (nem kötelező)" : "Tevékenység (nem kötelező)")
    }
    private var activityPrompt: String {
        isTravel ? "Mi volt az út célja?" : (m.type.isWholeDay ? "Megjegyzés" : "Mit csináltál? (nem kötelező)")
    }

    /// Utazás: Kiindulás és Cél (a Cél több helyet is tartalmazhat, akár pontos címmel: Tata, Fő út 1., Mór), a két mező mellett az
    /// „Oda-vissza” jelölő (alapból bejelölt: a munka után visszatértem a Kiindulásra; kivéve egyirányú út). A mezők fölött a „Munkahely”
    /// választógomb jelöli, hogy a Kiindulás vagy a Cél volt a munkahely (alapból a Cél).
    private var travelRow: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            travelPlaceRow
            kmRow
        }
    }

    /// Kilométeróra: induló és érkező állás, mindkettő opcionális (az induló az előző út végállásával előtöltve).
    private var kmRow: some View {
        HStack(spacing: 8) {
            Text("Km-óra").font(.caption).foregroundStyle(.secondary)
            TextField("induló km", text: $m.startKmText).textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                .help("A kilométeróra állása az út elején (nem kötelező; az előző út végállásával előtöltve)")
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
            TextField("érkező km", text: $m.endKmText).textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                .help("A kilométeróra állása az út végén (nem kötelező)")
        }
    }

    private var travelPlaceRow: some View {
        HStack(alignment: .top, spacing: compact ? 6 : 8) {
            travelColumn("Kiindulás", isWorkplace: m.workplaceIsDeparture, select: { m.workplaceIsDeparture = true }) {
                placeField(text: $m.departure, prompt: "pl. Győr", append: false)
            }
            travelColumn("Cél", isWorkplace: !m.workplaceIsDeparture, select: { m.workplaceIsDeparture = false }) {
                placeField(text: $m.destination, prompt: "pl. Tata, Fő út 1., Mór", append: true)
            }
            VStack(spacing: 3) {
                Text("Oda-\nvissza").font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(height: 26)
                Toggle("", isOn: $m.roundTrip).toggleStyle(.checkbox).labelsHidden()
                    .help(m.roundTrip ? "Oda-vissza: a munka után visszatértem a Kiindulásra. Kikapcsolva egyirányú út." : "Egyirányú út. Bejelölve oda-vissza: a munka után visszatértem a Kiindulásra.")
            }
            .frame(width: compact ? 40 : 46)
        }
    }

    private func travelColumn<Content: View>(_ title: String, isWorkplace: Bool, select: @escaping () -> Void,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Button(action: select) {
                    HStack(spacing: 3) {
                        Image(systemName: isWorkplace ? "largecircle.fill.circle" : "circle")
                        Text("Munkahely")
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(isWorkplace ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Ez a hely volt a munkahely (az OTS Munkahely mezőjébe ez kerül)")
            }
            .frame(height: 26, alignment: .bottom)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Szövegmező a mentett helyszínek menüjével. `append`: a menü a listához fűz (Munkahely(ek)), egyébként lecserél.
    private func placeField(text: Binding<String>, prompt: String, append: Bool) -> some View {
        HStack(spacing: 2) {
            SuggestTextField(prompt: prompt, text: text, candidates: { m.workplaceSuggestions }, list: append)
            Menu {
                if m.workplaceSuggestions.isEmpty {
                    Text("Még nincs mentett helyszín")
                }
                ForEach(m.workplaceSuggestions, id: \.self) { w in
                    Button(w) {
                        if append {
                            var list = text.wrappedValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                            if !list.contains(where: { $0.caseInsensitiveCompare(w) == .orderedSame }) { list.append(w) }
                            text.wrappedValue = list.joined(separator: ", ")
                        } else {
                            text.wrappedValue = w
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20)
            .help(append ? "Hozzáadás a listához a mentett helyszínekből" : "Mentett helyszínek")
        }
    }

    @ViewBuilder
    private func labeled<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if !compact { Text(title).font(.caption).foregroundStyle(.secondary) }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Időzítő

struct StopwatchView: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject var m: AppModel
    @Environment(\.compact) private var compact
    @State private var pulse = false

    var body: some View {
        VStack(spacing: compact ? 6 : 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(m.stopwatchRunning ? Theme.stop : Color.secondary.opacity(0.4))
                    .frame(width: 9, height: 9)
                    .opacity(m.stopwatchRunning && pulse ? 0.3 : 1)
                    .animation(m.stopwatchRunning ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: pulse)
                Text(Fmt.clock(m.stopwatchElapsed))
                    .font(.system(size: compact ? 28 : 42, weight: .light, design: .rounded))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .onAppear { pulse = true }

            startRow

            if m.stopwatchRunning {
                HStack(spacing: 8) {
                    BigButton(title: "Stop és mentés", symbol: "stop.fill", color: Theme.stop, enabled: m.fieldsComplete) {
                        m.stopStopwatch()
                    }
                    Button("Elvetés") { m.discardStopwatch() }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                }
                if let h = m.missingFieldsHint { Hint(text: h) }
            } else {
                BigButton(title: "Start", symbol: "play.fill", color: Theme.go, enabled: canStart) {
                    m.startStopwatch()
                }
                if let h = startHint { Hint(text: h) }
            }
        }
    }

    /// A kezdés ideje: indítás előtt megadható egy korábbi időpont (ma, egy gyors gombbal vagy óó:pp-vel), futás közben korrigálható.
    /// Az eltelt idő a megadott kezdéstől számolódik.
    private var startRow: some View {
        let nowDate = Date()
        let dayStart = DateUtil.startOfDay(m.timerStart ?? nowDate)
        let binding = Binding<Date>(
            get: { m.stopwatchRunning ? (m.timerStart ?? nowDate) : (m.plannedStart ?? Date()) },
            set: { v in
                if m.stopwatchRunning { m.setTimerStart(v) }
                else { m.plannedStart = v >= Date().addingTimeInterval(-30) ? nil : AppModel.clampedStart(v, now: Date()) }
            })
        return VStack(spacing: 3) {
            HStack(spacing: 6) {
                Text("Kezdés").font(.caption).foregroundStyle(.secondary)
                DatePicker("", selection: binding, in: dayStart...nowDate, displayedComponents: .hourAndMinute)
                    .labelsHidden().environment(\.locale, Locale(identifier: "hu_HU"))
                    .fixedSize()
                Spacer(minLength: 2)
                if !m.stopwatchRunning {
                    ForEach([5, 10, 15, 30], id: \.self) { mins in
                        Button("−\(mins)") { m.plannedStart = AppModel.clampedStart(Date().addingTimeInterval(-Double(mins) * 60), now: Date()) }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(palette.accent)
                            .help("\(mins) perccel korábbi kezdés")
                    }
                    if m.plannedStart != nil {
                        Button("Most") { m.plannedStart = nil }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.accent)
                    }
                }
            }
            if let note = startNote { Text(note).font(.caption2).foregroundStyle(.secondary) }
        }
    }

    private var startNote: String? {
        if m.stopwatchRunning { return "A kezdés itt korrigálható: az idő onnantól számolódik." }
        if let p = m.plannedStart {
            let mins = max(0, Int(Date().timeIntervalSince(p) / 60))
            return mins > 0 ? "\(mins) perccel ezelőttől számolom az időt." : nil
        }
        return nil
    }

    private var canStart: Bool { !m.pomodoroActive && m.fieldsComplete && !m.type.isWholeDay }
    private var startHint: String? {
        if m.pomodoroActive { return "A Pomodoro fut, előbb állítsd le." }
        if m.type.isWholeDay { return "Ez a típus csak a Kézi bevitelnél használható." }
        return m.missingFieldsHint
    }
}

// MARK: - Pomodoro

struct PomodoroView: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject var m: AppModel
    @Environment(\.compact) private var compact
    @AppStorage("pomo.work") private var work = 25
    @AppStorage("pomo.short") private var short = 5
    @AppStorage("pomo.long") private var long = 15
    @AppStorage("pomo.every") private var every = 4
    @AppStorage("pomo.autoBreak") private var autoBreak = true
    @AppStorage("pomo.autoWork") private var autoWork = false

    var body: some View {
        let showSettings = m.pomoSettingsOpen
        let ring: CGFloat = compact ? 84 : 118
        return VStack(spacing: compact ? 6 : 10) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: compact ? 5 : 7)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: compact ? 5 : 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
                VStack(spacing: 0) {
                    Text(m.pomodoroActive ? Fmt.clock(m.pomoRemaining) : Fmt.clock(work * 60))
                        .font(.system(size: compact ? 19 : 26, weight: .light, design: .rounded)).monospacedDigit()
                        .foregroundStyle(m.pomodoroActive ? Color.primary : Color.secondary)
                    Text(phaseTitle).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: ring, height: ring)

            switch m.pomoPhase {
            case .idle:
                BigButton(title: "Pomo indítása", symbol: "play.fill", color: Theme.go, enabled: canStart) {
                    m.startPomodoro()
                }
                if let h = startHint { Hint(text: h) }
            case .work:
                HStack(spacing: 8) {
                    BigButton(title: "Leállítás és mentés", symbol: "stop.fill", color: Theme.stop, enabled: m.fieldsComplete) {
                        m.stopPomodoro()
                    }
                    Button("Elvetés") { m.discardPomodoro() }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                }
                if let h = m.missingFieldsHint { Hint(text: h) }
            case .shortBreak, .longBreak:
                HStack(spacing: 8) {
                    BigButton(title: "Szünet kihagyása", symbol: "forward.fill", color: palette.accent) { m.skipPomodoroBreak() }
                    Button("Leállítás") { m.stopPomodoro() }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Text("Elvégzett pomo: \(m.pomoDone)").font(.caption).foregroundStyle(.secondary)
                if m.pomoDone > 0 {
                    Button("Nulláz") { m.resetPomodoroCounter() }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(palette.accent)
                }
                Spacer()
                Button {
                    m.pomoSettingsOpen.toggle()
                } label: {
                    Label("Pomo beállítások", systemImage: showSettings ? "chevron.up" : "slider.horizontal.3")
                        .font(.caption)
                }
                .buttonStyle(.plain).foregroundStyle(palette.accent)
            }

            if showSettings {
                VStack(alignment: .leading, spacing: 8) {
                    stepper("Pomo hossza (perc)", $work, 1...180)
                    stepper("Rövid szünet (perc)", $short, 1...60)
                    stepper("Hosszú szünet (perc)", $long, 1...120)
                    stepper("Hosszú szünet minden … pomo után", $every, 2...12)
                    Toggle("A szünet automatikusan induljon", isOn: $autoBreak)
                    Toggle("A következő pomo automatikusan induljon", isOn: $autoWork)
                    Button("Alapértelmezett (25 / 5 / 15, minden 4.)") {
                        work = 25; short = 5; long = 15; every = 4; autoBreak = true; autoWork = false
                    }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(palette.accent)
                    Text("A módosítás a következő pomo indításától érvényes.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var progress: Double {
        guard m.pomodoroActive else { return 0 }
        let total: Int
        switch m.pomoPhase {
        case .work: total = work * 60
        case .shortBreak: total = short * 60
        case .longBreak: total = long * 60
        case .idle: return 0
        }
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - Double(m.pomoRemaining) / Double(total)))
    }

    private var ringColor: Color {
        m.pomoPhase == .work || m.pomoPhase == .idle ? Theme.stop : Theme.go
    }

    private var phaseTitle: String {
        switch m.pomoPhase {
        case .idle: return "Nem fut"
        case .work: return "Pomo"
        case .shortBreak: return "Rövid szünet"
        case .longBreak: return "Hosszú szünet"
        }
    }

    private var canStart: Bool { m.timerStart == nil && m.fieldsComplete && !m.type.isWholeDay }
    private var startHint: String? {
        if m.stopwatchRunning { return "Az időzítő fut, előbb állítsd le." }
        if m.type.isWholeDay { return "Ez a típus csak a Kézi bevitelnél használható." }
        return m.missingFieldsHint
    }

    private func stepper(_ title: String, _ value: Binding<Int>, _ range: ClosedRange<Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Stepper(value: value, in: range) { Text("\(value.wrappedValue)").monospacedDigit() }
                .fixedSize()
        }
    }
}

// MARK: - Kézi bevitel

struct ManualView: View {
    @Environment(\.palette) private var palette
    enum TimeMode: String, CaseIterable, Identifiable {
        case range = "Időpont (tól–ig)"
        case duration = "Óraszám"
        var id: String { rawValue }
    }

    @EnvironmentObject var m: AppModel
    @Environment(\.compact) private var compact
    @State private var timeMode: TimeMode = .range
    @State private var startTime = Calendar.current.date(byAdding: .hour, value: -1, to: Date()) ?? Date()
    @State private var endTime = Date()
    @State private var hours = 1
    @State private var minutes = 0
    @State private var message: String?

    private var day: Binding<Date> { $m.selectedDay }
    private var needsTime: Bool { m.type.unit == .hours }
    private var isToday: Bool { Calendar.current.isDateInToday(m.selectedDay) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            DatePicker("Nap", selection: day, in: ...Date(), displayedComponents: .date)
                .environment(\.locale, Locale(identifier: "hu_HU"))

            if needsTime && m.selectedType != nil {
                HStack(spacing: 8) {
                    ForEach(TimeMode.allCases) { tm in
                        Button {
                            timeMode = tm
                        } label: {
                            Text(tm.rawValue)
                                .font(.system(size: 12, weight: timeMode == tm ? .semibold : .regular))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .foregroundStyle(timeMode == tm ? Color.white : Color.primary)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(timeMode == tm ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(Color.primary.opacity(0.08)))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                if timeMode == .range {
                    HStack(spacing: 14) {
                        DatePicker("Tól", selection: $startTime, displayedComponents: .hourAndMinute)
                        DatePicker("Ig", selection: $endTime, displayedComponents: .hourAndMinute)
                    }
                } else {
                    HStack(spacing: 16) {
                        Stepper(value: $hours, in: 0...16) {
                            Text("\(hours) óra").monospacedDigit()
                        }
                        Stepper(value: $minutes, in: 0...55, step: 5) {
                            Text("\(minutes) perc").monospacedDigit()
                        }
                    }
                }
            } else if m.selectedType != nil && !m.type.isWholeDay {
                Text("Ennél a típusnál nem kell időtartam, csak a mennyiség.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                BigButton(title: "Rögzítés", symbol: "checkmark", color: palette.accent, enabled: canSave) { save() }
                if let message {
                    Text(message).font(.caption).foregroundStyle(message.hasPrefix("✓") ? Theme.go : Theme.warn)
                }
            }
            if let h = m.missingFieldsHint {
                Hint(text: h)
            } else if needsTime && timeMode == .range && !timesValid {
                Hint(text: isToday && combine(endTime) > Date() ? "Jövőbeli időpont nem rögzíthető." : "Az „Ig” időpont legyen a „Tól” után.")
            } else if needsTime && timeMode == .duration && durationSeconds == 0 {
                Hint(text: "Adj meg legalább 5 percet.")
            }
        }
    }

    private var durationSeconds: Int { hours * 3600 + minutes * 60 }

    private func combine(_ time: Date) -> Date {
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: m.selectedDay) ?? m.selectedDay
    }

    private var timesValid: Bool {
        let s = combine(startTime), e = combine(endTime)
        return e > s && e <= Date()
    }

    private var canSave: Bool {
        guard m.fieldsComplete, !m.isFuture(m.selectedDay) else { return false }
        guard needsTime else { return true }
        return timeMode == .range ? timesValid : durationSeconds > 0
    }

    private func save() {
        guard !m.isFuture(m.selectedDay) else { message = "Jövőbeli napra nem lehet rögzíteni."; return }
        if m.type.isWholeDay {
            if m.entries(on: m.selectedDay).contains(where: { $0.type == m.type.rawValue }) {
                message = "Erre a napra már van ilyen bejegyzés."
                return
            }
            m.add(m.makeWholeDayEntry(day: m.selectedDay))
        } else if !needsTime {
            m.add(m.makeManualEntry(day: m.selectedDay, durationSeconds: 0))
        } else if timeMode == .range {
            m.add(m.makeEntry(start: combine(startTime), end: combine(endTime), source: "manual"))
        } else {
            m.add(m.makeManualEntry(day: m.selectedDay, durationSeconds: durationSeconds))
        }
        m.clearDraft()
        hours = 1
        minutes = 0
        message = "✓ Mentve"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { message = nil }
    }
}

// MARK: - Napi lista

struct DayListView: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject var m: AppModel
    @Environment(\.compact) private var compact
    @State private var pendingDelete: UUID?
    /// Az éppen javított út (km-állások) és a mezők szövege.
    @State private var editingKm: UUID?
    @State private var editStart = ""
    @State private var editEnd = ""
    @State private var editError: String?

    @Environment(\.detached) private var detached
    private var isToday: Bool { Calendar.current.isDateInToday(m.selectedDay) }

    /// A lista legnagyobb magassága a menüsori ablakban: ami a képernyőből a többi elem után megmarad.
    @Environment(\.listBudget) private var listBudget
    private var listHeight: CGFloat { listBudget }
    private func needsScroll(_ count: Int) -> Bool {
        !detached && CGFloat(count) * (compact ? 50 : 60) > listHeight
    }

    var body: some View {
        let items = m.entries(on: m.selectedDay)
        let total = items.reduce(0) { $0 + $1.creditSeconds }
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            HStack(spacing: 8) {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain)
                Spacer()
                HStack(spacing: 5) {
                    Text(compact ? Fmt.shortDay.string(from: m.selectedDay) : Fmt.longDay.string(from: m.selectedDay))
                        .font(.subheadline.weight(.medium))
                    targetDot
                }
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain)
                    .disabled(isToday)
                    .opacity(isToday ? 0.3 : 1)
                Button {
                    m.selectedDay = Date()
                    pendingDelete = nil
                } label: {
                    Text("Ma")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .foregroundStyle(isToday ? Color.secondary : Color.white)
                        .background(Capsule().fill(isToday ? AnyShapeStyle(Color.primary.opacity(0.08)) : AnyShapeStyle(palette.gradient)))
                }
                .buttonStyle(.plain)
                .disabled(isToday)
                .help("Ugrás a mai napra")
            }
            let reports = m.reports(on: m.selectedDay)
            if items.isEmpty {
                Text("Nincs bejegyzés erre a napra.").font(.caption).foregroundStyle(.secondary)
                if state == .short {
                    HStack(spacing: 5) {
                        Circle().fill(Theme.stop).frame(width: 7, height: 7)
                        Text("0:00 / \(m.targetHours):00 – még nincs meg a napi \(m.targetHours) óra")
                            .font(.caption).foregroundStyle(Theme.stop)
                    }
                }
            } else {
                if needsScroll(items.count) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: compact ? 5 : 7) {
                            ForEach(items) { row($0) }
                        }
                    }
                    .frame(height: listHeight)
                } else {
                    VStack(alignment: .leading, spacing: compact ? 5 : 7) {
                        ForEach(items) { row($0) }
                    }
                }
                HStack(spacing: 6) {
                    totalLine(all: total)
                    Spacer(minLength: 6)
                    colorDots(items)
                }
            }
            ForEach(reports) { r in
                Label("Létszámjelentő · \(r.congregation): Szombatiskola \(r.sabbathSchool.children)/\(r.sabbathSchool.adults)/\(r.sabbathSchool.guests), Istentisztelet \(r.worship.children)/\(r.worship.adults)/\(r.worship.guests)",
                      systemImage: "person.3.fill")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var state: Insights.TargetState { m.targetState(on: m.selectedDay) }

    /// A nap kategóriáinak színes pontjai az összesítő sor jobb szélén.
    private func colorDots(_ items: [Entry]) -> some View {
        var codes: [String] = []
        for e in items where !codes.contains(e.type) { codes.append(e.type) }
        return HStack(spacing: 3) {
            ForEach(codes.prefix(8), id: \.self) { c in
                Circle().fill(CategoryColors.color(code: c)).frame(width: 7, height: 7)
            }
        }
        .fixedSize()
        .allowsHitTesting(false)
    }

    /// Kis jelzés a dátum mellett: piros = nincs meg a napi óraszám, narancs = a mai nap még folyamatban, zöld pipa = megvan.
    @ViewBuilder private var targetDot: some View {
        switch state {
        case .short: Circle().fill(Theme.stop).frame(width: 8, height: 8)
            .help(DateUtil.isWeekday(m.selectedDay) ? "Még nincs meg a napi \(m.targetHours) óra" : "Üres hétvégi nap: rögzíts bejegyzést, vagy jelöld Szabadnapnak (bármilyen bejegyzés elég, hétvégén nincs napi óraszám)")
        case .inProgress: Circle().fill(Theme.warn).frame(width: 8, height: 8)
            .help(DateUtil.isWeekday(m.selectedDay) ? "A mai napon még nincs meg a napi \(m.targetHours) óra" : "A mai napon még nincs bejegyzés")
        case .reached: Image(systemName: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(Theme.go).help("Megvan a napi \(m.targetHours) óra")
        case .exempt: EmptyView()
        }
    }

    @ViewBuilder private func totalLine(all: Int) -> some View {
        let official = m.officialSeconds(on: m.selectedDay)
        if state == .exempt || !DateUtil.isWeekday(m.selectedDay) {
            Text("Összesen: \(Fmt.hm(all))").font(.caption).foregroundStyle(.secondary)
                .help("1 fő és 1 alkalom is 1 órának számít")
        } else {
            HStack(spacing: 5) {
                Text("Összesen: \(Fmt.hm(official)) / \(m.targetHours):00")
                    .font(.caption)
                    .foregroundStyle(state == .short ? Theme.stop : Color.secondary)
                if official != all {
                    Text("(saját kategóriákkal együtt \(Fmt.hm(all)))").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .help("1 fő és 1 alkalom is 1 órának számít; a saját kategóriák nem számítanak az OTS-órák közé")
        }
    }

    private func shift(_ d: Int) {
        let next = DateUtil.addDays(m.selectedDay, d)
        if m.isFuture(next) { return }
        m.selectedDay = next
        pendingDelete = nil
    }

    private func row(_ e: Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(CategoryColors.color(code: e.type)).frame(width: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text([when(e), e.typeLabel].filter { !$0.isEmpty }.joined(separator: "  "))
                        .font(.caption.weight(.medium))
                    Text(detail(e))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                    if let km = kmText(e) {
                        Text(km).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Spacer(minLength: 4)
                Text(amount(e)).font(.caption).monospacedDigit()
                if e.type == ActivityType.travel.code {
                    Button {
                        if editingKm == e.id {
                            editingKm = nil
                        } else {
                            editingKm = e.id
                            editStart = e.startKm.map(String.init) ?? ""
                            editEnd = e.endKm.map(String.init) ?? ""
                            editError = nil
                        }
                    } label: { Image(systemName: "pencil") }
                    .buttonStyle(.plain)
                    .foregroundStyle(editingKm == e.id ? palette.accent : Color.secondary)
                    .help("Km-állások javítása")
                }
                Button {
                    if pendingDelete == e.id {
                        m.delete(e.id)
                        pendingDelete = nil
                    } else {
                        pendingDelete = e.id
                    }
                } label: {
                    if pendingDelete == e.id {
                        Text("Biztos?").font(.caption2)
                    } else {
                        Image(systemName: "trash")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(pendingDelete == e.id ? Theme.stop : Color.secondary)
            }
            if editingKm == e.id { kmEditor(e) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Az út km-állásainak javítása a sor alatt (mindkettő opcionális; üresen törli az értéket).
    private func kmEditor(_ e: Entry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                TextField("induló km", text: $editStart).textFieldStyle(.roundedBorder)
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                TextField("érkező km", text: $editEnd).textFieldStyle(.roundedBorder)
                Button("Mentés") {
                    if let err = m.updateKm(e.id, start: editStart, end: editEnd) {
                        editError = err
                    } else {
                        editingKm = nil
                        editError = nil
                    }
                }
                .buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(palette.accent)
            }
            if let err = editError {
                Text(err).font(.caption2).foregroundStyle(Theme.stop).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 12)
    }

    /// Utazásnál a km-állások és az út hossza (ha van).
    private func kmText(_ e: Entry) -> String? {
        guard e.type == ActivityType.travel.code, e.startKm != nil || e.endKm != nil else { return nil }
        let s = e.startKm.map(String.init) ?? "?", en = e.endKm.map(String.init) ?? "?"
        return "km-óra: \(s) → \(en)" + (e.kmDriven.map { " (\($0) km)" } ?? "")
    }

    /// Második sor: utazásnál az útvonal (Indulás → Munkahely(ek) → Érkezés), egyébként munkahely · tevékenység.
    private func detail(_ e: Entry) -> String {
        if let dep = e.departure, let arr = e.arrival, !dep.isEmpty || !arr.isEmpty {
            let route = ([dep] + e.workplace.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } + [arr])
                .filter { !$0.isEmpty }.joined(separator: " → ")
            return [route, e.activity].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return [e.workplace, e.activity].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func when(_ e: Entry) -> String {
        if e.unit == Unit.wholeDay.rawValue { return "egész nap" }
        guard let s = e.start, let en = e.end else { return e.unit == Unit.hours.rawValue ? "óraszám" : "" }
        return "\(Fmt.timeFormatter.string(from: s))–\(Fmt.timeFormatter.string(from: en))"
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

// MARK: - Kitöltetlen napok

struct MissingDaysView: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject var m: AppModel
    @Environment(\.compact) private var compact
    @AppStorage("missing.lookback") private var lookback = "thisMonth"

    private static let chipFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "MMM d. EEE"
        return f
    }()

    var body: some View {
        let missing = m.missingDays(lookback: lookback)
        let short = m.shortDays(lookback: lookback)
        let attendance = m.pendingAttendanceDates(lookback: lookback)
        let nothing = missing.isEmpty && short.isEmpty && attendance.isEmpty
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: nothing ? "checkmark.seal.fill" : "calendar.badge.exclamationmark")
                    .foregroundStyle(nothing ? Theme.go : Theme.warn)
                title(missing: missing.count, short: short.count, attendance: attendance.count)
                Spacer()
                let sundays = missing.filter { DateUtil.isSunday($0) }.count
                if sundays > 0 {
                    Button { m.markEmptySundaysAsDayOff(lookback: lookback) } label: {
                        Label(compact ? "\(sundays)" : "Vasárnapok → szabadnap (\(sundays))", systemImage: "moon.zzz")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(Theme.warn.opacity(0.18)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Az összes kitöltetlen vasárnap (\(MissingDaysView.label(for: lookback))) szabadnapnak jelölése")
                }
                if !compact {
                    Text(MissingDaysView.label(for: lookback)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if !nothing {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        // létszámjelentők, majd a kitöltetlen és a hiányos napok, mindegyik a legfrissebbtől
                        ForEach(attendance.reversed(), id: \.self) { d in
                            chip(d, kind: .attendance)
                        }
                        ForEach(missing.reversed(), id: \.self) { d in
                            chip(d, kind: .missing)
                        }
                        ForEach(short.reversed(), id: \.self) { d in
                            chip(d, kind: .short)
                        }
                    }
                }
            }
        }
        .card()
    }

    private enum ChipKind { case missing, short, attendance }

    private func title(missing: Int, short: Int, attendance: Int) -> some View {
        var parts: [String] = []
        if missing > 0 { parts.append("Kitöltetlen napok (\(missing))") }
        if short > 0 { parts.append("hiányos (\(short))") }
        if attendance > 0 { parts.append("létszámjelentő (\(attendance))") }
        return Text(parts.isEmpty ? "Nincs kitöltetlen nap" : parts.joined(separator: " · "))
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func chip(_ d: Date, kind: ChipKind) -> some View {
        let selected = Calendar.current.isDate(d, inSameDayAs: m.selectedDay)
            && (kind == .attendance || m.mode == .manual)
        let tint: Color = kind == .missing ? Theme.warn : (kind == .short ? Theme.stop : Color.purple)
        let main = Button {
            m.selectedDay = d
            if kind != .attendance { m.mode = .manual }
        } label: {
            HStack(spacing: 4) {
                if kind == .short { Circle().fill(Theme.stop).frame(width: 6, height: 6) }
                if kind == .attendance { Image(systemName: "person.3.fill").font(.system(size: 9)) }
                Text(MissingDaysView.chipFormatter.string(from: d))
                    .font(.caption)
                if kind == .short {
                    Text(Fmt.hm(m.officialSeconds(on: d))).font(.caption2).monospacedDigit().foregroundStyle(selected ? Color.white : Color.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(kind == .missing ? "Kitöltetlen nap" : (kind == .short ? "Nincs meg a napi \(m.targetHours) óra" : "Létszámjelentő esedékes"))
        return HStack(spacing: 5) {
            main
            if kind == .missing {
                // egykattintásos jelölés: ha ezen a napon pihentél, ne kelljen megnyitni a Kézi bevitelt
                Button { m.markDayOff(d) } label: {
                    Image(systemName: "moon.zzz").font(.system(size: 9.5, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Szabadnapnak jelölöm ezt a napot")
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(Capsule().fill(selected ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(tint.opacity(0.18))))
        .contextMenu {
            if kind == .missing {
                Button("Szabadnapnak jelölöm") { m.markDayOff(d) }
                Button("Megnyitás a Kézi bevitelben") { m.selectedDay = d; m.mode = .manual }
            }
        }
    }

    static func label(for key: String) -> String {
        switch key {
        case "7": return "elmúlt 7 nap"
        case "14": return "elmúlt 2 hét"
        case "30": return "elmúlt 30 nap"
        case "prevMonth": return "előző hónaptól"
        case "thisMonth": return "e hónaptól"
        default: return "elmúlt \(key) nap"
        }
    }
}
