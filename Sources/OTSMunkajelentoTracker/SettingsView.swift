import SwiftUI
import AppKit
import ServiceManagement

/// A Beállítások kategóriái (a fülek a lap tetején; az utolsó választás megmarad).
enum SettingsTab: String, CaseIterable, Identifiable {
    case appearance, recording, calendar, ots, data
    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "Megjelenés"
        case .recording: return "Rögzítés"
        case .calendar: return "Naptár"
        case .ots: return "OTS"
        case .data: return "Adatok"
        }
    }

    var symbol: String {
        switch self {
        case .appearance: return "paintbrush"
        case .recording: return "slider.horizontal.3"
        case .calendar: return "calendar.badge.clock"
        case .ots: return "tablecells"
        case .data: return "externaldrive"
        }
    }

    var help: String {
        switch self {
        case .appearance: return "Megjelenés: színséma, ikonok, hangok"
        case .recording: return "Rögzítés: helyszínek, kategóriák, javaslatok, naptár-nézet, emlékeztetők"
        case .calendar: return "Naptár-szinkron (Mac Naptár)"
        case .ots: return "OTS: létszámjelentő, skill, kézi felvitel"
        case .data: return "Adatok: adatfájl, indítás, törlés"
        }
    }
}

/// A Beállítások fülsora (az app többi fülével egyező stílusban).
struct SettingsTabBar: View {
    @Environment(\.palette) private var palette
    @Environment(\.compact) private var compact
    @AppStorage("settings.tab") private var tabRaw = SettingsTab.appearance.rawValue

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                let selected = tabRaw == tab.rawValue
                Button { tabRaw = tab.rawValue } label: {
                    Group {
                        if compact {
                            VStack(spacing: 1) {
                                Image(systemName: tab.symbol)
                                Text(tab.title).font(.system(size: 8.5)).lineLimit(1).minimumScaleFactor(0.7)
                            }
                        } else {
                            Label(tab.title, systemImage: tab.symbol).lineLimit(1).minimumScaleFactor(0.75)
                        }
                    }
                    .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, compact ? 3 : 6)
                    .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.75))
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selected ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(Color.clear))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(tab.help)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.primary.opacity(0.07)))
    }
}

struct SettingsView: View {
    /// Igaz: az összes kategória egymás alatt (csak az útmutató képernyőképeihez).
    var showAllTabs = false
    init(showAllTabs: Bool = false) { self.showAllTabs = showAllTabs }

    @AppStorage("settings.tab") private var tabRaw = SettingsTab.appearance.rawValue
    @Environment(\.palette) private var palette
    @EnvironmentObject var m: AppModel
    @AppStorage("menuIcon") private var mainIcon = "adventist"
    @AppStorage("menuIcon.reminder") private var reminderIcon = "warning"
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("palette") private var paletteID = "blue"
    @AppStorage("cal.startHour") private var calStart = 7
    @AppStorage("cal.endHour") private var calEnd = 20
    @AppStorage("cal.weekStart") private var weekStart = 2
    @AppStorage("reminder.enabled") private var reminderOn = true
    @AppStorage("reminder.days") private var reminderDays = 7
    @AppStorage("target.hours") private var targetHours = 8
    @AppStorage("home") private var home = ""
    @AppStorage("attendance.enabled") private var attendanceOn = false
    @State private var newCongregation = ""
    @AppStorage("menuIcon.pomo") private var pomoIcon = "tomato"
    @AppStorage("menuIcon.break") private var breakIcon = "cup"
    @AppStorage("menu.showPomoTime") private var showPomoTime = true
    @AppStorage("sound.pomoEnd") private var pomoSound = "Glass"
    @AppStorage("sound.breakEnd") private var breakSound = "Ping"
    @AppStorage("missing.lookback") private var lookback = "thisMonth"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var newPlace = ""
    @State private var newCategory = ""
    @State private var showColors = false
    @State private var colorEditing: String?
    @State private var colorHex = ""
    @State private var newCategoryUnit = Unit.hours
    @State private var showBuiltins = false
    @State private var showDanger = false
    @State private var resetDone = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showAllTabs {
                ForEach(SettingsTab.allCases) { tabContent($0) }
            } else {
                tabContent(SettingsTab(rawValue: tabRaw) ?? .appearance)
            }
        }
    }

    /// Egy kategória kártyái.
    @ViewBuilder private func tabContent(_ tab: SettingsTab) -> some View {
        switch tab {
        case .appearance:
            appearanceCard
            iconsCard
            soundsCard
        case .recording:
            placesCard
            categoriesCard
            suggestCard
            calendarCard
            remindersCard
        case .calendar:
            CalendarSyncCard(sync: m.calendarSync)
        case .ots:
            attendanceCard
            skillCard
        case .data:
            dataCard
            otherCard
            dangerCard
        }
    }

    // MARK: Javaslatok gépelés közben

    @AppStorage("suggest.enabled") private var suggestOn = true

    private var suggestCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Javaslatok gépelés közben").font(.subheadline.weight(.semibold))
            Toggle("Javaslatok a mezők alatt", isOn: $suggestOn)
            Text("A Munkahely, a Kiindulás, a Cél, a Tevékenység típusa és a Tevékenység mezőben gépelés közben javaslatokat kapsz a mentett helyszínekből, a típusokból és a korábbi tevékenységekből (például „ügy” → Ügyintézés). ↓ és ↑ lépked, Enter vagy Tab elfogadja, Esc bezárja. Kikapcsolva a Tevékenység típusa a régi legördülő lista.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.card()
    }

    // MARK: Ikonok

    private var iconsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Menüsori ikonok").font(.subheadline.weight(.semibold))
            iconRow("Alap", IconSets.main, $mainIcon)
            iconRow("Pomo közben", IconSets.pomoWork, $pomoIcon)
            iconRow("Szünet közben", IconSets.pomoBreak, $breakIcon)
            iconRow("Hosszú kihagyás után (emlékeztető)", IconSets.reminder, $reminderIcon)
            Toggle("Pomo és szünet közben a hátralévő idő is látszik az ikon mellett", isOn: $showPomoTime)
                .font(.callout)
        }.card()
    }

    private func iconRow(_ title: String, _ choices: [IconChoice], _ selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(choices) { c in
                    let selected = selection.wrappedValue == c.id
                    Button { selection.wrappedValue = c.id } label: {
                        IconView(choice: c)
                            .font(.system(size: 15))
                            .frame(width: 40, height: 32)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(selected ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(Color.primary.opacity(0.08)))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(c.label)
                }
            }
        }
    }

    // MARK: Hangok

    private var soundsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Jelzőhangok").font(.subheadline.weight(.semibold))
            soundRow("Pomo vége", $pomoSound)
            soundRow("Szünet vége", $breakSound)
        }.card()
    }

    private func soundRow(_ title: String, _ selection: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker("", selection: selection) {
                Text("Nincs hang").tag(Sounds.none)
                Divider()
                ForEach(Sounds.names, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(width: 150)
            .onChange(of: selection.wrappedValue) { m.playSound($0) }
            Button {
                m.playSound(selection.wrappedValue)
            } label: {
                Image(systemName: "speaker.wave.2")
            }
            .buttonStyle(.plain)
            .help("Meghallgatás")
        }
    }

    // MARK: Megjelenés

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Megjelenés").font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                modeButton("Világos", "sun.max.fill", "light")
                modeButton("Sötét", "moon.fill", "dark")
                modeButton("Rendszer", "circle.lefthalf.filled", "system")
            }
            Text("Színséma").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(Palette.all) { p in
                    let selected = paletteID == p.id
                    Button { paletteID = p.id } label: {
                        VStack(spacing: 4) {
                            Circle().fill(p.gradient).frame(width: 30, height: 30)
                                .overlay(Circle().strokeBorder(Color.primary, lineWidth: selected ? 2.5 : 0).padding(-4))
                            Text(p.name).font(.caption2).foregroundStyle(selected ? Color.primary : Color.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(p.name)
                }
            }
        }.card()
    }

    private func modeButton(_ title: String, _ symbol: String, _ value: String) -> some View {
        let selected = appearance == value
        return Button { appearance = value } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(Color.primary.opacity(0.08))))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Naptár

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Naptár").font(.subheadline.weight(.semibold))
            HStack {
                Text("A munkanap kezdete")
                Spacer()
                Picker("", selection: $calStart) {
                    ForEach(0..<23, id: \.self) { Text(String(format: "%d:00", $0)).tag($0) }
                }
                .labelsHidden().frame(width: 90)
                .onChange(of: calStart) { v in if calEnd <= v { calEnd = min(24, v + 1) } }
            }
            HStack {
                Text("A munkanap vége")
                Spacer()
                Picker("", selection: $calEnd) {
                    ForEach(1..<25, id: \.self) { Text(String(format: "%d:00", $0)).tag($0) }
                }
                .labelsHidden().frame(width: 90)
                .onChange(of: calEnd) { v in if v <= calStart { calStart = max(0, v - 1) } }
            }
            HStack {
                Text("A hét kezdőnapja")
                Spacer()
                Picker("", selection: $weekStart) {
                    Text("Hétfő").tag(2)
                    Text("Vasárnap").tag(1)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 170)
            }
            Text("A naptár csak a megadott sávot mutatja (egy 6:30-kor kezdődő munkához állítsd a kezdetet 6:00-ra). A sávon kívüli bejegyzéseket a nap tetején egy jel mutatja, a napi listában mindig látszanak.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.card()
    }

    // MARK: Emlékeztetők és jelzések

    private var remindersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Emlékeztetők és jelzések").font(.subheadline.weight(.semibold))
            Picker("Kitöltetlen napok ellenőrzése", selection: $lookback) {
                Text("Elmúlt 7 nap").tag("7")
                Text("Elmúlt 2 hét").tag("14")
                Text("Elmúlt 30 nap").tag("30")
                Text("Előző hónap elejétől").tag("prevMonth")
                Text("E hónap elejétől").tag("thisMonth")
            }
            Text("A vasárnapot is ellenőrzi, a mai napot nem számolja. A szabadság, szabadnap és munkaszüneti nap kitöltött napnak számít.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Toggle("A menüikon jelezze, ha régen nem volt munkajelentő", isOn: $reminderOn)
            if reminderOn {
                Stepper(value: $reminderDays, in: 2...60) {
                    Text("Ennyi egymást követő kitöltetlen nap után: \(reminderDays)").monospacedDigit()
                }
            }
            Divider()
            Stepper(value: $targetHours, in: 1...16) {
                Text("Napi elvárt óraszám (hétfőtől péntekig): \(targetHours)").monospacedDigit()
            }
            Text("Ha egy napon nincs meg, kis piros jel mutatja a napi listában, a naptárban és a kitöltetlen napok között.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.card()
    }

    // MARK: Gyülekezeti létszámjelentő

    private var attendanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gyülekezeti létszámjelentő").font(.subheadline.weight(.semibold))
            Toggle("Kérje a létszámjelentőt az esedékes szombatokon", isOn: $attendanceOn)
            Text("Esedékes: minden negyedév második és hetedik szombatja. Ha még nincs kitöltve, kitöltetlen napként is jelzi. A számokat a skill innen olvassa ki.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if attendanceOn {
                Text("Gyülekezetek (a feladatok sorrendjében)").font(.caption).foregroundStyle(.secondary)
                if m.attendanceCongregations.isEmpty {
                    Text("Adj hozzá legalább egy gyülekezetet.").font(.caption).foregroundStyle(Theme.warn)
                }
                ForEach(m.attendanceCongregations, id: \.self) { c in
                    HStack(spacing: 8) {
                        Text(c)
                        Spacer()
                        Button { m.moveAttendanceCongregation(c, by: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Feljebb")
                        Button { m.moveAttendanceCongregation(c, by: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Lejjebb")
                        Button { m.removeAttendanceCongregation(c) } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Törlés a listából")
                    }
                }
                HStack {
                    TextField("Új gyülekezet", text: $newCongregation)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addCongregation)
                    Button("Hozzáad", action: addCongregation)
                        .disabled(newCongregation.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }.card()
    }

    private func addCongregation() {
        m.addAttendanceCongregation(newCongregation)
        newCongregation = ""
    }

    // MARK: Helyszínek

    private var placesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Székhely és helyszínek").font(.subheadline.weight(.semibold))
            HStack {
                Text("Székhely")
                TextField("pl. Pécs", text: $home).textFieldStyle(.roundedBorder)
            }
            Text("Az Utazás Indulás és Érkezés mezőjének alapértéke, és a Költségelszámolás útvonalainak kiindulópontja.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Text("Mentett helyszínek").font(.caption).foregroundStyle(.secondary)
            if m.places.isEmpty {
                Text("Még nincs mentett helyszín.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(m.places, id: \.self) { p in
                HStack {
                    Text(p)
                    Spacer()
                    Button { m.removePlace(p) } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("Törlés a listából")
                }
            }
            HStack {
                TextField("Új helyszín", text: $newPlace)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addPlace)
                Button("Hozzáad", action: addPlace)
                    .disabled(newPlace.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Rögzítéskor az új helyszín magától bekerül a listába. A törlés a már rögzített bejegyzéseket nem érinti.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.card()
    }

    private func addPlace() {
        m.addPlace(newPlace)
        newPlace = ""
    }

    // MARK: Kategóriák

    private var categoriesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tevékenység-kategóriák").font(.subheadline.weight(.semibold))

            Text("Saját kategóriák").font(.caption).foregroundStyle(.secondary)
            if m.customCategories.isEmpty {
                Text("Még nincs saját kategória.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(m.customCategories) { c in
                HStack(spacing: 8) {
                    TextField("Név", text: Binding(
                        get: { c.label },
                        set: { m.renameCustomCategory(code: c.code, to: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Text(unitName(c.unit)).font(.caption).foregroundStyle(.secondary)
                    Button { m.removeCustomCategory(code: c.code) } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("Kategória törlése")
                }
            }
            HStack {
                TextField("Új kategória", text: $newCategory)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addCategory)
                Picker("", selection: $newCategoryUnit) {
                    Text("óra").tag(Unit.hours)
                    Text("alkalom").tag(Unit.occasions)
                    Text("fő").tag(Unit.people)
                }
                .labelsHidden()
                .frame(width: 85)
                Button("Hozzáad", action: addCategory)
                    .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("A saját kategóriáknak nincs OTS-megfelelője, a munkajelentő skill nem viszi át őket az OTS-be. A törlés a már rögzített bejegyzéseket nem érinti.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
            DisclosureGroup(isExpanded: $showColors) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(ActivityType.all) { t in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Button {
                                    colorEditing = (colorEditing == t.code) ? nil : t.code
                                    colorHex = CategoryColors.hex(of: CategoryColors.color(code: t.code)) ?? ""
                                } label: {
                                    Circle().fill(CategoryColors.color(code: t.code)).frame(width: 18, height: 18)
                                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .help("Kattints a szín módosításához")
                                Text(t.label).font(.callout)
                                Spacer()
                                if CategoryColors.isCustomized(t.code) {
                                    Button("Alapérték") { m.setCategoryColor(t.code, hex: nil); colorHex = "" }
                                        .buttonStyle(.plain).font(.caption).foregroundStyle(palette.accent)
                                }
                                Image(systemName: colorEditing == t.code ? "chevron.up" : "chevron.down")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                colorEditing = (colorEditing == t.code) ? nil : t.code
                                colorHex = CategoryColors.hex(of: CategoryColors.color(code: t.code)) ?? ""
                            }
                            if colorEditing == t.code {
                                colorChooser(for: t)
                            }
                        }
                    }
                    Text("A színek a naptárban, a napi listában és a kézi felviteli ablakban jelennek meg.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            } label: {
                Text("Kategóriák színei").font(.caption)
            }
            Divider()
            DisclosureGroup(isExpanded: $showBuiltins) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(ActivityType.builtins) { t in
                        Toggle(isOn: Binding(
                            get: { !m.hiddenTypeCodes.contains(t.code) },
                            set: { m.setBuiltinHidden(t.code, hidden: !$0) }
                        )) {
                            Text("\(t.label)").font(.callout)
                            + Text("  · \(t.group)").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Text("Az OTS-kategóriák nevét nem lehet módosítani, de elrejthetők a legördülő menüből.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            } label: {
                Text("OTS-kategóriák megjelenítése (\(ActivityType.builtins.count - m.hiddenTypeCodes.count)/\(ActivityType.builtins.count) látható)")
                    .font(.caption)
            }
        }.card()
    }

    static let swatches = [
        "#2E73CC", "#1E88C9", "#2FA3A8", "#2E9E6B", "#7BB241", "#C9B21F",
        "#E08A1E", "#D9622B", "#D2433F", "#C2417A", "#8E5BC4", "#5E6AD2",
        "#B5483A", "#8A6A4F", "#738091", "#333B47"
    ]

    /// Beépített színválasztó (a rendszer színpaneljét a menüsori ablakból nem lehet megbízhatóan megnyitni).
    @ViewBuilder private func colorChooser(for t: ActivityType) -> some View {
        let current = CategoryColors.hex(of: CategoryColors.color(code: t.code))
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 26, maximum: 30), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(Self.swatches, id: \.self) { hex in
                    Button {
                        m.setCategoryColor(t.code, hex: hex)
                        colorHex = hex
                    } label: {
                        Circle().fill(CategoryColors.color(hex: hex) ?? .gray).frame(width: 24, height: 24)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(current == hex ? 0.9 : 0.2), lineWidth: current == hex ? 2.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 6) {
                Text("Egyedi:").font(.caption).foregroundStyle(.secondary)
                TextField("#RRGGBB", text: $colorHex)
                    .textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced)).frame(width: 90)
                    .onSubmit { applyHex(t) }
                Button("Beállít") { applyHex(t) }
                    .disabled(CategoryColors.color(hex: colorHex) == nil)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private func applyHex(_ t: ActivityType) {
        var h = colorHex.trimmingCharacters(in: .whitespaces).uppercased()
        if !h.hasPrefix("#") { h = "#" + h }
        guard CategoryColors.color(hex: h) != nil else { return }
        m.setCategoryColor(t.code, hex: h)
        colorHex = h
    }

    private func addCategory() {
        m.addCustomCategory(name: newCategory, unit: newCategoryUnit)
        newCategory = ""
    }

    private func unitName(_ raw: String) -> String {
        raw == "people" ? "fő" : (raw == "occasions" ? "alkalom" : "óra")
    }

    // MARK: Adatfájl

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Adatfájl").font(.subheadline.weight(.semibold))
            Text(m.dataFileURL.path)
                .font(.caption2).foregroundStyle(.secondary)
                .textSelection(.enabled).lineLimit(3)
            HStack {
                Button("Mappa módosítása…") { chooseFolder() }
                Button("Alapértelmezett") { m.resetDataFolder() }
            }
            Text("CSV fájl (pontosvesszővel tagolt, UTF-8): Excelben, Numbersben vagy LibreOffice-ban megnyitható és szerkeszthető. Szerkesztés után az app a következő megnyitáskor újra beolvassa. A munkajelentő skill ezt a fájlt olvassa. A létszámjelentések ugyanebbe a mappába, a letszamjelentesek.csv fájlba kerülnek.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.card()
    }

    // MARK: Skill (OTS Adminisztráció)

    private var skillCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Skill: OTS Adminisztráció (Claude, ChatGPT/Codex, Antigravity CLI)").font(.subheadline.weight(.semibold))
            Text("Az MI-asszisztens ezzel tölti ki helyetted az OTS adminisztrációt (Havi munkajelentő, Költségelszámolás, névsor, Hittan, Látogatottság), és ennek az alkalmazásnak az adataiból dolgozik. Telepítéskor megadod, hogy a DETKapu vagy a TETKapu oldalon dolgozol-e. Az Antigravity CLI ingyenes megoldás (személyes Google-fiókkal).")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Ha nem a skillel dolgozol, a bejegyzéseket kézzel is felviheted: a külön ablakban naptárban, felsorolásban és az OTS táblázatának megfelelően látod őket (Munkajelentő, Költségelszámolás, Létszámjelentő).")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Kézi felvitel az OTS-be…") {
                OTSManualWindow.shared.show(model: m)
            }
            HStack {
                Button("Skill telepítése…") {
                    SkillInstallerWindow.shared.show(model: m)
                }
                Text(skillStatus).font(.caption).foregroundStyle(.secondary)
            }
            if m.skillUpdateAvailable {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill").foregroundStyle(Theme.warn)
                    Text("Az alkalmazásban újabb skill van, mint a gépeden.").font(.caption)
                    Spacer(minLength: 4)
                    Button("Skill frissítése") { m.updateSkill() }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.warn.opacity(0.12)))
                Text("A frissítés a korábbi telepítés beállításait használja (célok, feladatok, név, székhely), és a régi skillről másolatot készít. Utána indítsd újra az asszisztens alkalmazását.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let msg = m.skillUpdateMessage {
                Text(msg).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.card()
    }

    private var skillStatus: String {
        let installed = SkillTarget.allCases.filter {
            FileManager.default.fileExists(atPath: SkillInstaller.skillDir(for: $0).appendingPathComponent("SKILL.md").path)
        }
        if installed.isEmpty { return "nincs telepítve" }
        return "telepítve: " + installed.map { $0.title }.joined(separator: ", ")
    }

    // MARK: Egyéb

    private var otherCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Indítás bejelentkezéskor", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                        loginError = nil
                    } catch {
                        loginError = "Nem sikerült: \(error.localizedDescription)"
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }
            Button("Használati útmutató megnyitása") { openGuide() }
                .disabled(Self.guideURL == nil)
            HStack {
                Text("Verzió \(Self.version)").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Kilépés") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
        }.card()
    }

    // MARK: Alapállapot (veszélyes zóna)

    private var dangerCard: some View {
        DisclosureGroup(isExpanded: $showDanger) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Törli az összes eddig bevitt adatot (bejegyzések, mentett helyszínek, saját kategóriák), és az alkalmazást alapállapotba állítja. Az ikon-, hang- és nézetbeállítások megmaradnak.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Biztonsági okból a törlés előtti adatfájl egy másolata megmarad a „bejegyzesek.torles-elotti.csv” fájlban, ugyanabban a mappában. A következő törlés felülírja.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(role: .destructive) {
                        confirmAndReset()
                    } label: {
                        Label("Összes adat törlése…", systemImage: "trash")
                            .foregroundStyle(Theme.stop)
                    }
                    if resetDone {
                        Text("✓ Törölve").font(.caption).foregroundStyle(Theme.go)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Label("Adatok törlése, alapállapot", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(showDanger ? Theme.stop : Color.primary)
        }
        .card()
    }

    private func confirmAndReset() {
        resetDone = false
        let count = m.entries.count
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Biztosan törlöd az összes adatot?"
        alert.informativeText = "\(count) bejegyzés, a mentett helyszínek és a saját kategóriák törlődnek, az alkalmazás alapállapotba áll. Ez nem vonható vissza az alkalmazásból (a törlés előtti adatfájl másolata megmarad a mappában)."
        let cancel = alert.addButton(withTitle: "Mégse")
        cancel.keyEquivalent = "\r"          // az Enter a biztonságos választ adja
        let confirm = alert.addButton(withTitle: "Mindent törlök")
        confirm.hasDestructiveAction = true
        confirm.keyEquivalent = ""
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        // második, külön megerősítés: véletlen dupla kattintás ne törölhessen
        let second = NSAlert()
        second.alertStyle = .critical
        second.messageText = "Utolsó megerősítés"
        second.informativeText = "Valóban véglegesen törlöd az összes bevitt adatot?"
        let no = second.addButton(withTitle: "Nem, megtartom")
        no.keyEquivalent = "\r"
        let yes = second.addButton(withTitle: "Igen, törlés")
        yes.hasDestructiveAction = true
        yes.keyEquivalent = ""
        guard second.runModal() == .alertSecondButtonReturn else { return }

        if m.resetAllData() {
            resetDone = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { resetDone = false }
        }
    }

    private static var guideURL: URL? {
        Bundle.main.url(forResource: "utmutato", withExtension: "html", subdirectory: "guide")
    }

    private func openGuide() {
        if let url = Self.guideURL { NSWorkspace.shared.open(url) }
    }

    private static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "fejlesztői"
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Kiválaszt"
        if panel.runModal() == .OK, let url = panel.url {
            m.changeDataFolder(to: url)
        }
    }
}
