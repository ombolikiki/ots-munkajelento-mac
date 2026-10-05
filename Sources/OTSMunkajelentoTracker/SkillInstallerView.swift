import SwiftUI
import AppKit

/// Az „OTS Adminisztráció” skill telepítő varázslója: áttekintés, cél, feladatok, adatok, telepítés, kész.
struct SkillInstallerView: View {
    @Environment(\.palette) private var palette
    @ObservedObject var installer: SkillInstaller
    @EnvironmentObject var m: AppModel
    @State private var showValidation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            progress
            ScrollView {
                Group {
                    switch installer.step {
                    case .intro: intro
                    case .target: target
                    case .tasks: tasksStep
                    case .details: details
                    case .review: review
                    case .done: done
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.trailing, 4)
            }
            if let e = installer.errorText {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(Theme.stop)
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttons
        }
        .padding(22)
        .frame(width: 580, height: 640)
    }

    // MARK: Lépésjelző

    private var progress: some View {
        let titles = ["Áttekintés", "Cél", "Feladatok", "Adataid", "Telepítés", "Kész"]
        return HStack(spacing: 5) {
            ForEach(Array(titles.enumerated()), id: \.offset) { i, t in
                let active = installer.step.rawValue == i
                let past = installer.step.rawValue > i
                HStack(spacing: 5) {
                    ZStack {
                        Circle().fill(active || past ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(Color.primary.opacity(0.12)))
                            .frame(width: 22, height: 22)
                        if past { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) }
                        else { Text("\(i + 1)").font(.system(size: 11, weight: .semibold)).foregroundStyle(active ? Color.white : Color.secondary) }
                    }
                    if active { Text(t).font(.system(size: 12, weight: .semibold)) }
                }
                if i < titles.count - 1 { Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1).frame(maxWidth: 18) }
            }
            Spacer()
        }
    }

    // MARK: 1. Áttekintés

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OTS Adminisztráció skill telepítése").font(.title2.weight(.semibold))
            Text("A skill („OTS Adminisztráció”) megtanítja az MI-asszisztenst, hogyan töltse ki helyetted az OTS adminisztrációs feladatait: Havi munkajelentő, Költségelszámolás, Gyülekezeti névsor, Hittan, Látogatottság. A munkajelentőhöz, a költségelszámoláshoz és a létszámjelentőhöz ennek az alkalmazásnak az adatait használja.")
                .fixedSize(horizontal: false, vertical: true)
            Text("A telepítés egy mappát másol a gépedre. Semmit nem küld az internetre, és az OTS-ben semmit nem módosít.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Ellenőrzés").font(.subheadline.weight(.semibold))
                row(installer.bundledAvailable, "A csomagolt skill megvan az alkalmazásban",
                    installer.bundledFingerprint().map { "azonosító: \($0)" } ?? "nem található")
                row(FileManager.default.fileExists(atPath: m.dataFileURL.path), "Az alkalmazás adatfájlja létezik", "\(m.entries.count) bejegyzés")
                ForEach(SkillTarget.allCases) { t in statusRow(t) }
            }.card()
        }
    }

    @ViewBuilder private func statusRow(_ t: SkillTarget) -> some View {
        switch installer.status[t] ?? .notInstalled {
        case .notInstalled: row(true, "\(t.title): még nincs telepítve", nil, neutral: true)
        case .upToDate: row(true, "\(t.title): telepítve van, és naprakész", nil)
        case .outdated: row(true, "\(t.title): telepítve van, de elérhető újabb változat", "A telepítés frissíti.", neutral: true)
        case .foreign: row(false, "\(t.title): már van egy kézzel telepített skill ugyanezen a néven", "Felülírás előtt másolat készül róla.")
        }
    }

    private func row(_ ok: Bool, _ title: String, _ detail: String?, neutral: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: neutral ? "info.circle.fill" : (ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"))
                .foregroundStyle(neutral ? palette.accent : (ok ? Theme.go : Theme.warn))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout)
                if let d = detail { Text(d).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }

    // MARK: 2. Cél

    private var target: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hová telepítsük?").font(.title2.weight(.semibold))
            Text("Több célt is választhatsz. Ugyanaz a skill kerül mindegyikbe, csak a mappa különbözik.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(SkillTarget.allCases) { t in
                let on = installer.selectedTargets.contains(t)
                Button {
                    if on { installer.selectedTargets.remove(t) } else { installer.selectedTargets.insert(t) }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: on ? "checkmark.square.fill" : "square")
                            .font(.system(size: 18)).foregroundStyle(on ? palette.accent : Color.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(t.title).font(.headline)
                                if t.isFree {
                                    Text("Ingyenes")
                                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                        .padding(.horizontal, 7).padding(.vertical, 2)
                                        .background(Capsule().fill(Theme.go))
                                }
                            }
                            Text(t.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Text("~/" + t.relativePath + "/" + SkillInstaller.skillName)
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .card()
            }
            if installer.selectedTargets.contains(.antigravity) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: SkillInstaller.agyInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(SkillInstaller.agyInstalled ? Theme.go : Theme.warn)
                        Text(SkillInstaller.agyInstalled ? "Az Antigravity CLI (agy) telepítve van ezen a gépen." : "Az Antigravity CLI (agy) még nincs telepítve ezen a gépen.")
                            .font(.callout.weight(.medium))
                    }
                    if !SkillInstaller.agyInstalled {
                        Text("Telepítés a Terminálban (a telepítés után a skillt is ide másoljuk, a részletek az Antigravity CLI útmutatóban vannak):")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Text(SkillInstaller.agyInstallCommand).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            Spacer()
                            Button("Másolás") { installer.copyAgyInstallCommand() }.controlSize(.small)
                        }
                    }
                }.card()
            }
            if installer.selectedTargets.contains(.codex) && installer.selectedTargets.contains(.antigravity) {
                Label("A Codex és az Antigravity CLI ugyanazt a mappát (~/.agents/skills) olvassa, ezért oda egyszer telepítünk.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if installer.selectedTargets.contains(.codex) || installer.selectedTargets.contains(.antigravity) {
                Label("A Codex és az Antigravity CLI is kipróbálva: látja és olvassa az OTS-t, és kattint rajta. Mint minden asszisztensnél, a lezárás előtt itt is nézd át az eredményt.", systemImage: "checkmark.seal")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 3. Feladatok

    private var tasksStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mely feladatokat telepítsük?").font(.title2.weight(.semibold))
            Text("Csak a kijelölt feladatokhoz kér adatot a telepítő. A Határidők kiolvasása mindig része a skillnek.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(installer.tasks) { task in
                let on = installer.selectedTasks.contains(task.id)
                Button {
                    if on { installer.selectedTasks.remove(task.id) } else { installer.selectedTasks.insert(task.id) }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: on ? "checkmark.square.fill" : "square")
                            .font(.system(size: 18)).foregroundStyle(on ? palette.accent : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.name).font(.headline)
                            Text(task.summary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            if !task.needs.isEmpty {
                                Text("Kér: " + task.needs.map { $0 == "home" ? "székhely" : "gyülekezetek" }.joined(separator: ", "))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .card()
            }
        }
    }

    // MARK: 4. Adatok

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Az adataid").font(.title2.weight(.semibold))
            Text("Ezekkel az adatokkal személyre szabjuk a skillt. Bármikor újra lefuttathatod a telepítést, ha változnak.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Melyik OTS-oldalon dolgozol?").font(.subheadline.weight(.medium))
                Picker("", selection: $installer.site) {
                    ForEach(OTSSite.allCases) { site in Text("\(site.title) (\(site.host))").tag(site) }
                }
                .pickerStyle(.segmented).labelsHidden()
                Text("A két oldal felépítése megegyezik. A skill a kiválasztott címet használja (\(installer.site.url)).")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            field("Neved", "pl. Kovács János", $installer.userName, help: "A skill így szólítja meg a felhasználót.")
            if installer.needsHome {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Székhelyed").font(.subheadline.weight(.medium))
                    HStack {
                        TextField("pl. Pécs", text: $installer.home).textFieldStyle(.roundedBorder)
                        if !m.places.isEmpty {
                            Menu {
                                ForEach(m.places, id: \.self) { p in Button(p) { installer.home = p } }
                            } label: { Image(systemName: "chevron.down") }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
                        }
                    }
                    Text("A település, ahonnan a költségelszámolás útvonalai indulnak, ha egy Utazás bejegyzésben nincs megadva az Indulás vagy az Érkezés.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if installer.needsCongregations {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gyülekezeteid").font(.subheadline.weight(.medium))
                    TextField("pl. Pécs, Mohács, Szigetvár", text: $installer.congregations).textFieldStyle(.roundedBorder)
                    Text("Vesszővel elválasztva, abban a sorrendben, ahogy a feladatokat végig kell csinálni. Ez \(installer.parsedCongregations.count) gyülekezet.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !installer.needsHome && !installer.needsCongregations {
                Text("A kijelölt feladatokhoz nincs szükség további adatra.").font(.callout).foregroundStyle(.secondary)
            }
            if let e = installer.detailsError, showValidation {
                Label(e, systemImage: "info.circle").font(.caption).foregroundStyle(Theme.warn)
            }
        }
    }

    private func field(_ title: String, _ prompt: String, _ text: Binding<String>, help: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.medium))
            TextField(prompt, text: text).textFieldStyle(.roundedBorder)
            Text(help).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 5. Összegzés

    private var review: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Telepítés").font(.title2.weight(.semibold))
            Text("Ellenőrizd az adatokat, majd kattints a Telepítés gombra.").font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                reviewRow("OTS-oldal", "\(installer.site.title) (\(installer.site.url))")
                reviewRow("Neved", installer.userName.trimmingCharacters(in: .whitespaces))
                if installer.needsHome { reviewRow("Székhelyed", installer.home.trimmingCharacters(in: .whitespaces)) }
                if installer.needsCongregations { reviewRow("Gyülekezeteid", installer.parsedCongregations.joined(separator: ", ")) }
                Divider()
                reviewRow("Feladatok", installer.tasks.filter { installer.selectedTasks.contains($0.id) }.map { $0.name }.joined(separator: ", "))
                Divider()
                ForEach(Array(installer.effectiveFolders().enumerated()), id: \.offset) { _, f in
                    reviewRow(f.targets.map { $0.title }.joined(separator: " + "),
                              f.url.appendingPathComponent(SkillInstaller.skillName).path)
                }
            }.card()
            if installer.selectedTargets.contains(.antigravity) {
                Label("Antigravity CLI: a telepítés után indítsd az agy-t, kapcsold be a /browser parancsot, és engedélyezd a böngészőeszközt (több engedélyt is kér).",
                      systemImage: "terminal")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            let existing = installer.effectiveFolders().filter { FileManager.default.fileExists(atPath: $0.url.appendingPathComponent(SkillInstaller.skillName + "/SKILL.md").path) }
            if !existing.isEmpty {
                Label("Ahol már van ilyen nevű skill, a telepítő lecseréli, de előtte másolatot ment ide: ~/Library/Application Support/OTS Munkajelentő Tracker/skill-mentesek.", systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func reviewRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.callout).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            Text(v).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: 6. Kész

    private var done: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 30)).foregroundStyle(Theme.go)
                Text("A skill telepítve van").font(.title2.weight(.semibold))
            }
            ForEach(installer.results) { r in
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.targets.map { $0.title }.joined(separator: " + ")).font(.subheadline.weight(.semibold))
                    Text(r.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    if let b = r.backup {
                        Text("A korábbi változat másolata: \(b)").font(.caption2).foregroundStyle(.secondary)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(r.notes, id: \.self) { n in
                        Label(n, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(r.targets) { t in
                        HStack(alignment: .top, spacing: 6) {
                            Text("Indítás:").font(.caption.weight(.semibold))
                            Text(.init("`\(t.startHint)`")).font(.caption).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .card()
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Így használd").font(.subheadline.weight(.semibold))
                step(1, "Indítsd újra az asszisztens alkalmazását (kilépés, majd megnyitás), hogy betöltse az új skillt.")
                step(2, "Nyiss új munkamenetet, és add ki a fent látható indítóparancsot.")
                step(3, "Amikor kéri, jelentkezz be az OTS-be a böngészőjében. A jelszavadat az asszisztens soha nem írja be.")
                step(4, "A munkajelentő, a költségelszámolás és a létszámjelentő az alkalmazás naplójából dolgozik, ehhez nem kell semmit csinálnod.")
                if installer.selectedTargets.contains(.antigravity) {
                    step(5, "**Antigravity CLI (ingyenes, kipróbálva):** a Terminálban indítsd az `agy` parancsot, jelentkezz be a Google-fiókoddal, kapcsold be a `/browser` parancsot, és kérd: „Használd az ots-adminisztracio skillt.” Az első böngészőhívásnál több engedélyt is kér; olvasd el őket. Amikor megnyílik a Chrome, jelentkezz be az OTS-be (\(installer.site.url)).")
                }
            }.card()
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(Circle().fill(palette.gradient))
            Text(.init(text)).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Gombok

    private var buttons: some View {
        HStack {
            switch installer.step {
            case .intro:
                Button("Bezárás") { NSApp.keyWindow?.close() }
                Spacer()
                Button("Tovább") { go(.target) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!installer.bundledAvailable)
            case .target:
                Button("Vissza") { go(.intro) }
                Spacer()
                Button("Tovább") { if let e = installer.targetsError { installer.errorText = e } else { go(.tasks) } }
                    .keyboardShortcut(.defaultAction)
            case .tasks:
                Button("Vissza") { go(.target) }
                Spacer()
                Button("Tovább") { if let e = installer.tasksError { installer.errorText = e } else { go(.details) } }
                    .keyboardShortcut(.defaultAction)
            case .details:
                Button("Vissza") { go(.tasks) }
                Spacer()
                Button("Tovább") {
                    showValidation = true
                    if installer.detailsError == nil { go(.review) }
                }
                .keyboardShortcut(.defaultAction)
            case .review:
                Button("Vissza") { go(.details) }
                Spacer()
                Button("Telepítés") { installer.install() }
                    .keyboardShortcut(.defaultAction)
            case .done:
                Button("Mappa megnyitása") { installer.revealInFinder() }
                if installer.selectedTargets.contains(.claude) {
                    Button("Parancs másolása") { installer.copyCommand() }
                }
                if installer.selectedTargets.contains(.antigravity), SkillInstaller.antigravityGuideURL != nil {
                    Button("Antigravity CLI útmutató") { installer.openAntigravityGuide() }
                }
                Spacer()
                if installer.selectedTargets.contains(.claude) {
                    Button(installer.claudeAppURL != nil ? "Claude megnyitása" : "Claude letöltése") { installer.openClaude() }
                }
                Button("Bezárás") { NSApp.keyWindow?.close() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func go(_ s: SkillInstaller.Step) {
        installer.errorText = nil
        installer.step = s
    }
}
