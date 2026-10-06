import SwiftUI
import AppKit
import CryptoKit

// MARK: - OTS-oldal

/// Melyik OTS-oldalon dolgozik a felhasználó. A két oldal felépítése megegyezik, csak a cím és a név különbözik.
enum OTSSite: String, CaseIterable, Identifiable {
    case det, tet
    var id: String { rawValue }
    var title: String { self == .det ? "DETKapu" : "TETKapu" }
    var host: String { self == .det ? "ots.detkapu.hu" : "ots.tetkapu.hu" }
    var url: String { "https://" + host + "/" }
}

// MARK: - Célok és feladatok

/// Hová telepíthető a skill. A skill formátuma (egy `SKILL.md`-t tartalmazó mappa) nyílt szabvány.
enum SkillTarget: String, CaseIterable, Identifiable, Hashable {
    case claude, codex, antigravity
    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "ChatGPT desktop / Codex"
        case .antigravity: return "Antigravity CLI (agy)"
        }
    }

    var detail: String {
        switch self {
        case .claude: return "A Claude asztali alkalmazás Code lapja. Kipróbálva. Fizetős Claude-előfizetés kell hozzá."
        case .codex: return "ChatGPT Codex (a ChatGPT asztali alkalmazás és a Codex ugyanazt a mappát használja). Ingyenesen használható. Kipróbálva: látja és olvassa az OTS-t, és kattint rajta."
        case .antigravity: return "A Google parancssori asszisztense (a Gemini CLI utódja): személyes Google-fiókkal, előfizetés nélkül használható, heti kerettel. Kipróbálva: látja és olvassa az OTS-t, és kattint rajta."
        }
    }

    /// Ingyenesen használható megoldás-e (a felületen külön jelezzük).
    var isFree: Bool { self == .codex || self == .antigravity }

    /// A skillek mappája a felhasználó könyvtárához képest.
    var relativePath: String {
        switch self {
        case .claude: return ".claude/skills"
        case .codex: return ".agents/skills"
        case .antigravity: return ".agents/skills"
        }
    }

    var startHint: String {
        switch self {
        case .claude: return "/ots-adminisztracio"
        case .codex: return "$ots-adminisztracio  (a ChatGPT-ben @ jellel is kiválasztható)"
        case .antigravity: return "agy  (a Terminálban), majd /browser, és kérd: „Használd az ots-adminisztracio skillt”"
        }
    }
}

struct SkillTaskInfo: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let files: [String]
    let shared: [String]
    let needs: [String]       // "home" | "congregations"

    var summary: String {
        switch id {
        case "havi": return "Napi bontású munkajelentő az alkalmazás naplójából."
        case "koltseg": return "Havi útiköltség az Utazás bejegyzések útvonalaiból (Google Maps)."
        case "nevsor": return "Negyedéves névsor lezárása gyülekezetenként."
        case "hittan": return "Félévente a hitoktatás lezárása gyülekezetenként."
        case "latogatottsag": return "Létszámjelentő kitöltése a rögzített létszámokból."
        default: return ""
        }
    }
}

private struct TaskManifest: Decodable { let tasks: [SkillTaskInfo] }

// MARK: - Telepítő logika

final class SkillInstaller: ObservableObject {
    /// A skill azonosítója (mappa- és `name:` érték), megjelenített neve: „OTS Adminisztráció”.
    static let skillName = "ots-adminisztracio"
    static let displayName = "OTS Adminisztráció"
    /// A korábbi verziók skill-neve: ha ilyet az alkalmazás telepített, az új telepítés lecseréli (másolat mellett).
    static let legacySkillName = "detkapu-adminisztracio"
    static let markerName = ".ots-tracker-install.json"

    enum Step: Int { case intro, target, tasks, details, review, done }

    enum Installed: Equatable {
        case notInstalled
        case upToDate
        case outdated
        case foreign          // kézzel telepített (nincs jelölés), felülírás előtt másolat készül
    }

    struct Result: Identifiable {
        let id = UUID()
        let targets: [SkillTarget]
        let path: String
        let backup: String?
        /// Tájékoztató sorok (pl. a régi skill lecserélése, az Antigravity CLI telepítettsége).
        var notes: [String] = []
    }

    enum InstallError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
    }

    @Published var step: Step = .intro
    @Published var selectedTargets: Set<SkillTarget> = [.claude]
    @Published var selectedTasks: Set<String> = []
    @Published var userName = ""
    @Published var home = ""
    @Published var congregations = ""
    @Published var site: OTSSite = .det
    @Published var errorText: String?
    @Published var results: [Result] = []
    @Published private(set) var status: [SkillTarget: Installed] = [:]
    @Published private(set) var tasks: [SkillTaskInfo] = []

    private let model: AppModel
    private let ud = UserDefaults.standard

    init(model: AppModel) {
        self.model = model
        tasks = Self.loadTasks()
        let saved = ud.stringArray(forKey: "skill.tasks") ?? []
        let valid = Set(tasks.map { $0.id })
        let chosen = Set(saved).intersection(valid)
        selectedTasks = chosen.isEmpty ? valid : chosen
        if let t = ud.stringArray(forKey: "skill.targets") {
            let set = Set(t.compactMap { SkillTarget(rawValue: $0 == "gemini" ? "antigravity" : $0) })
            if !set.isEmpty { selectedTargets = set }
        }
        userName = ud.string(forKey: "skill.userName") ?? ""
        site = OTSSite(rawValue: ud.string(forKey: "skill.site") ?? "") ?? .det
        let savedHome = ud.string(forKey: "skill.home") ?? ""
        home = savedHome.isEmpty ? (ud.string(forKey: "home") ?? model.places.first ?? "") : savedHome
        let savedCong = ud.string(forKey: "skill.congregations") ?? ""
        congregations = savedCong.isEmpty
            ? (model.attendanceCongregations.isEmpty ? model.places.joined(separator: ", ") : model.attendanceCongregations.joined(separator: ", "))
            : savedCong
        refresh()
    }

    // MARK: Helyek (tesztben felülbírálhatók környezeti változókkal)

    /// A csomagolt skill mappája (az app `Resources/skill/ots-adminisztracio`).
    static var bundledSkill: URL? {
        if let o = ProcessInfo.processInfo.environment["OTS_SKILL_SOURCE"] { return URL(fileURLWithPath: o) }
        return Bundle.main.url(forResource: "skill", withExtension: nil)?.appendingPathComponent(skillName)
    }

    /// A felhasználó könyvtára (tesztben az `OTS_HOME` felülbírálja).
    static var homeDir: URL {
        if let o = ProcessInfo.processInfo.environment["OTS_HOME"] { return URL(fileURLWithPath: o, isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static func skillsRoot(for target: SkillTarget) -> URL { homeDir.appendingPathComponent(target.relativePath, isDirectory: true) }
    static func skillDir(for target: SkillTarget) -> URL { skillsRoot(for: target).appendingPathComponent(skillName, isDirectory: true) }

    static var backupRoot: URL { AppModel.supportDir.appendingPathComponent("skill-mentesek", isDirectory: true) }

    static func loadTasks() -> [SkillTaskInfo] {
        guard let base = bundledSkill,
              let data = try? Data(contentsOf: base.appendingPathComponent("tasks.json")),
              let manifest = try? JSONDecoder().decode(TaskManifest.self, from: data) else { return [] }
        return manifest.tasks
    }

    var bundledAvailable: Bool {
        guard let b = Self.bundledSkill else { return false }
        return FileManager.default.fileExists(atPath: b.appendingPathComponent("SKILL.md").path) && !tasks.isEmpty
    }

    var claudeAppURL: URL? {
        ["/Applications/Claude.app", NSHomeDirectory() + "/Applications/Claude.app"]
            .first { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    /// A tényleges célmappák: a Codex és az Antigravity CLI közös `~/.agents/skills` mappát használ (ellenőrizve: az `agy` onnan tölti be a skillt).
    func effectiveFolders() -> [(url: URL, targets: [SkillTarget])] {
        var result: [(URL, [SkillTarget])] = []
        let sel = SkillTarget.allCases.filter { selectedTargets.contains($0) }
        if sel.contains(.claude) { result.append((Self.skillsRoot(for: .claude), [.claude])) }
        // A Codex és az Antigravity CLI is a közös ~/.agents/skills mappából olvassa a skilleket: oda egyszer másolunk.
        let shared = sel.filter { $0 == .codex || $0 == .antigravity }
        if !shared.isEmpty { result.append((Self.skillsRoot(for: .codex), shared)) }
        return result
    }

    // MARK: Tartalom és azonosítás

    /// A csomagolt fájlok (relatív út -> szöveg), a `tasks.json` nélkül.
    func bundledFiles() throws -> [(path: String, text: String)] {
        guard let base = Self.bundledSkill else { throw InstallError.message("A csomagolt skill nem található az alkalmazásban.") }
        guard let en = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            throw InstallError.message("A csomagolt skill mappája nem olvasható.")
        }
        var result: [(String, String)] = []
        for case let url as URL in en {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let rel = url.path.replacingOccurrences(of: base.path + "/", with: "")
            result.append((rel, try String(contentsOf: url, encoding: .utf8)))
        }
        return result.sorted { $0.0 < $1.0 }
    }

    func bundledFingerprint() -> String? {
        guard let files = try? bundledFiles(), !files.isEmpty else { return nil }
        var hasher = SHA256()
        for f in files {
            hasher.update(data: Data(f.path.utf8))
            hasher.update(data: Data(f.text.utf8))
        }
        return String(hasher.finalize().map { String(format: "%02x", $0) }.joined().prefix(8))
    }

    func refresh() {
        let fp = bundledFingerprint()
        var s: [SkillTarget: Installed] = [:]
        for t in SkillTarget.allCases {
            let dir = Self.skillDir(for: t)
            guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("SKILL.md").path) else { s[t] = .notInstalled; continue }
            let markerURL = dir.appendingPathComponent(Self.markerName)
            if let data = try? Data(contentsOf: markerURL),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let installedFp = obj["fingerprint"] as? String {
                s[t] = installedFp == fp ? .upToDate : .outdated
            } else {
                s[t] = .foreign
            }
        }
        status = s
    }

    // MARK: Feladatok és adatok

    var neededFields: Set<String> {
        Set(tasks.filter { selectedTasks.contains($0.id) }.flatMap { $0.needs })
    }

    var needsHome: Bool { neededFields.contains("home") }
    var needsCongregations: Bool { neededFields.contains("congregations") }

    var parsedCongregations: [String] {
        var seen = Set<String>()
        return congregations.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    var targetsError: String? { selectedTargets.isEmpty ? "Válassz legalább egy célt." : nil }
    var tasksError: String? { selectedTasks.isEmpty ? "Válassz legalább egy feladatot." : nil }

    var detailsError: String? {
        if userName.trimmingCharacters(in: .whitespaces).isEmpty { return "Add meg a neved." }
        if needsHome, home.trimmingCharacters(in: .whitespaces).isEmpty { return "Add meg a székhelyed (ahonnan az útvonalak indulnak)." }
        if needsCongregations, parsedCongregations.isEmpty { return "Add meg legalább egy gyülekezetet." }
        for v in [userName, home, congregations] where v.contains("{{") || v.contains("}}") || v.contains("[[") || v.contains("]]") {
            return "A mezők nem tartalmazhatnak kapcsos vagy szögletes zárójel-párt."
        }
        return nil
    }

    // MARK: Megjelenítés (sablonfeldolgozás)

    static let claudeBrowser = "Böngészőként a beépített Claude böngészőpanelt használd (`mcp__Claude_Browser__*`)."
    static let genericBrowser = "Böngészőként a környezetedben elérhető böngésző- vagy számítógép-vezérlő eszközt használd, a felhasználó bejelentkezett munkamenetével. Ha nincs ilyen eszköz, szólj a felhasználónak, és ne dolgozz a felület nélkül."

    /// A sablon szövegének kitöltése: feladat-jelölők, részek és helyőrzők.
    func render(_ text: String, browser: String) -> String {
        var t = text

        // 1) feladat-jelölők: a nem választott feladat sorai törlődnek, a többiből a jelölő
        var lines: [String] = []
        for line in t.components(separatedBy: "\n") {
            if let r = line.range(of: "[[TASK:"), let e = line.range(of: "]]", range: r.upperBound..<line.endIndex) {
                let id = String(line[r.upperBound..<e.lowerBound])
                if !selectedTasks.contains(id) { continue }
                lines.append(line.replacingOccurrences(of: "[[TASK:\(id)]]", with: "").replacingOccurrences(of: "[[/TASK]]", with: ""))
            } else {
                lines.append(line)
            }
        }
        t = lines.joined(separator: "\n")

        // 2) közös (tracker-adat) szakasz: csak ha olyan feladat is van, ami használja
        let usesTracker = !selectedTasks.isDisjoint(with: ["havi", "koltseg", "latogatottsag"])
        if usesTracker {
            t = t.replacingOccurrences(of: "[[SHARED:tracker]]", with: "").replacingOccurrences(of: "[[/SHARED]]", with: "")
        } else if let regex = try? NSRegularExpression(pattern: "\\[\\[SHARED:tracker\\]\\].*?\\[\\[/SHARED\\]\\]\\n*", options: [.dotMatchesLineSeparators]) {
            t = regex.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
        }

        // 3) feltételes részek: {{#NÉV}}…{{/NÉV}} csak ha az adat meg van adva
        let values = effectiveValues()
        if let regex = try? NSRegularExpression(pattern: "\\{\\{#([A-Z_]+)\\}\\}(.*?)\\{\\{/\\1\\}\\}", options: [.dotMatchesLineSeparators]) {
            let ns = t as NSString
            var out = ""
            var last = 0
            for m in regex.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
                out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let key = ns.substring(with: m.range(at: 1))
                if !(values[key] ?? "").isEmpty { out += ns.substring(with: m.range(at: 2)) }
                last = m.range.location + m.range.length
            }
            out += ns.substring(from: last)
            t = out
        }

        // 4) helyőrzők
        for (k, v) in values { t = t.replacingOccurrences(of: "{{\(k)}}", with: v) }
        t = t.replacingOccurrences(of: "{{BONGESZO}}", with: browser)
        return t
    }

    /// A kitöltendő értékek; amit a kijelölt feladatok nem használnak, üres marad.
    func effectiveValues() -> [String: String] {
        [
            "FELHASZNALO_NEVE": userName.trimmingCharacters(in: .whitespaces),
            "SZEKHELY": needsHome ? home.trimmingCharacters(in: .whitespaces) : "",
            "GYULEKEZETEK": needsCongregations ? parsedCongregations.joined(separator: ", ") : "",
            "OTS_URL": site.url,
            "OTS_NEV": site.title
        ]
    }

    /// Mely fájlok kerülnek a telepítésbe: a SKILL.md, a kijelölt feladatok fájljai és azok közös fájljai.
    func includedPaths() -> Set<String> {
        var p: Set<String> = ["SKILL.md"]
        for t in tasks where selectedTasks.contains(t.id) {
            t.files.forEach { p.insert($0) }
            t.shared.forEach { p.insert($0) }
        }
        return p
    }

    // MARK: Telepítés

    @discardableResult
    func install() -> Bool {
        errorText = nil
        if let e = targetsError ?? tasksError ?? detailsError { errorText = e; return false }
        let fm = FileManager.default
        results = []
        do {
            let allFiles = try bundledFiles()
            guard allFiles.contains(where: { $0.path == "SKILL.md" }) else {
                throw InstallError.message("A csomagolt skillből hiányzik a SKILL.md.")
            }
            let include = includedPaths()
            let files = allFiles.filter { include.contains($0.path) }
            try fm.createDirectory(at: AppModel.supportDir, withIntermediateDirectories: true)

            for (folder, targets) in effectiveFolders() {
                let browser = targets.contains(.claude) ? Self.claudeBrowser : Self.genericBrowser
                let stage = AppModel.supportDir.appendingPathComponent("skill-telepites-\(UUID().uuidString)", isDirectory: true)
                let staged = stage.appendingPathComponent(Self.skillName, isDirectory: true)
                try fm.createDirectory(at: staged, withIntermediateDirectories: true)
                defer { try? fm.removeItem(at: stage) }

                for f in files {
                    let out = staged.appendingPathComponent(f.path)
                    try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try render(f.text, browser: browser).write(to: out, atomically: true, encoding: .utf8)
                }

                // ellenőrzés: nem maradhat helyőrző vagy jelölő, és a SKILL.md fejléce érvényes
                for f in files {
                    let text = try String(contentsOf: staged.appendingPathComponent(f.path), encoding: .utf8)
                    if text.range(of: "\\{\\{[#/]?[A-Z_]+\\}\\}|\\[\\[/?(TASK|SHARED)", options: .regularExpression) != nil {
                        throw InstallError.message("Kitöltetlen helyőrző vagy jelölő maradt a(z) \(f.path) fájlban.")
                    }
                }
                let skillMd = try String(contentsOf: staged.appendingPathComponent("SKILL.md"), encoding: .utf8)
                guard skillMd.hasPrefix("---"), skillMd.contains("name: \(Self.skillName)") else {
                    throw InstallError.message("A SKILL.md fejléce érvénytelen.")
                }

                let marker: [String: Any] = [
                    "installedBy": AppModel.appName,
                    "appVersion": (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev",
                    "fingerprint": bundledFingerprint() ?? "",
                    "date": ISO8601DateFormatter().string(from: Date()),
                    "targets": targets.map { $0.rawValue },
                    "tasks": selectedTasks.sorted(),
                    "values": effectiveValues()
                ]
                try JSONSerialization.data(withJSONObject: marker, options: [.prettyPrinted, .sortedKeys])
                    .write(to: staged.appendingPathComponent(Self.markerName), options: .atomic)

                // a meglévő telepítés mentése (a skillek mappáján kívülre), majd csere
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let dest = folder.appendingPathComponent(Self.skillName, isDirectory: true)
                var backupPath: String?
                if fm.fileExists(atPath: dest.path) {
                    let backup = try makeBackupDir()
                    try fm.copyItem(at: dest, to: backup.appendingPathComponent(Self.skillName))
                    backupPath = backup.path
                    _ = try fm.replaceItemAt(dest, withItemAt: staged)
                } else {
                    try fm.moveItem(at: staged, to: dest)
                }
                guard fm.fileExists(atPath: dest.appendingPathComponent("SKILL.md").path) else {
                    throw InstallError.message("A telepítés után nem található a SKILL.md.")
                }
                var notes = replaceLegacySkill(in: folder)
                if targets.contains(.antigravity) {
                    if let n = retireGeminiCopy() { notes.append(n) }
                    if !Self.agyInstalled { notes.append("Az Antigravity CLI (agy) még nincs telepítve a gépen. Telepítés: \(Self.agyInstallCommand)") }
                }
                results.append(Result(targets: targets, path: dest.path, backup: backupPath, notes: notes))
            }

            ud.set(userName.trimmingCharacters(in: .whitespaces), forKey: "skill.userName")
            ud.set(home.trimmingCharacters(in: .whitespaces), forKey: "skill.home")
            ud.set(parsedCongregations.joined(separator: ", "), forKey: "skill.congregations")
            ud.set(selectedTasks.sorted(), forKey: "skill.tasks")
            ud.set(selectedTargets.map { $0.rawValue }.sorted(), forKey: "skill.targets")
            ud.set(site.rawValue, forKey: "skill.site")
            refresh()
            step = .done
            return true
        } catch {
            errorText = "A telepítés nem sikerült: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: Egykattintásos frissítés

    struct UpdateOutcome: Equatable {
        var updated: [SkillTarget] = []
        var problems: [String] = []
        var didUpdate: Bool { !updated.isEmpty }
        var message: String {
            if updated.isEmpty && problems.isEmpty { return "A skill naprakész." }
            var parts: [String] = []
            if !updated.isEmpty { parts.append("Frissítve: " + updated.map { $0.title }.joined(separator: ", ") + ". Indítsd újra az asszisztens alkalmazását, hogy az új skillt töltse be.") }
            parts += problems
            return parts.joined(separator: " ")
        }
    }

    /// Az alkalmazás által telepített, de elavult skill frissítése **a korábbi telepítés beállításaival** (célok, feladatok, név,
    /// székhely, gyülekezetek, DETKapu/TETKapu), amelyek a skill jelölőfájljában vannak. Frissítés előtt a meglévő telepítésről másolat készül
    /// (mint a telepítőnél). A kézzel telepített skillt (jelölés nélkül) nem bántja. Ha a jelölés hiányos, a telepítőt kell használni.
    @discardableResult
    func updateOutdated() -> UpdateOutcome {
        var outcome = UpdateOutcome()
        refresh()
        let keys = ["skill.userName", "skill.home", "skill.congregations", "skill.tasks", "skill.targets", "skill.site"]
        let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, ud.object(forKey: $0)) })
        defer { for (k, v) in saved { if let v = v { ud.set(v, forKey: k) } else { ud.removeObject(forKey: k) } } }
        let validTasks = Set(tasks.map { $0.id })

        // két tényleges mappa: Claude, és a Codex/Antigravity közös
        for (rep, group) in [(SkillTarget.claude, [SkillTarget.claude]), (SkillTarget.codex, [SkillTarget.codex, SkillTarget.antigravity])] {
            guard status[rep] == .outdated else { continue }
            let markerURL = Self.skillDir(for: rep).appendingPathComponent(Self.markerName)
            guard let data = try? Data(contentsOf: markerURL),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let values = obj["values"] as? [String: String] else {
                outcome.problems.append("\(rep.title): a telepítés jelölése hiányos, használd a telepítő varázslót (Beállítások › Skill telepítése).")
                continue
            }
            let markedTasks = Set((obj["tasks"] as? [String]) ?? []).intersection(validTasks)
            let markedTargets = Set(((obj["targets"] as? [String]) ?? []).compactMap { SkillTarget(rawValue: $0) }).intersection(group)
            selectedTasks = markedTasks.isEmpty ? validTasks : markedTasks
            selectedTargets = markedTargets.isEmpty ? [rep] : markedTargets
            userName = values["FELHASZNALO_NEVE"] ?? ""
            home = values["SZEKHELY"] ?? ""
            congregations = values["GYULEKEZETEK"] ?? ""
            site = (values["OTS_NEV"] == OTSSite.tet.title) ? .tet : .det
            if let e = detailsError {
                outcome.problems.append("\(rep.title): a korábbi beállítások nem elégségesek (\(e)) Használd a telepítő varázslót.")
                continue
            }
            if install() { outcome.updated += selectedTargets.sorted { $0.rawValue < $1.rawValue } }
            else { outcome.problems.append("\(rep.title): \(errorText ?? "a frissítés nem sikerült.")") }
        }
        refresh()
        return outcome
    }

    // MARK: Mentések, régi skill

    /// Új, még nem létező mentési mappa (időbélyeggel) a skill-mentések alatt; azonos másodpercen belül is egyedi.
    static func uniqueBackupDir(prefix: String = "") throws -> URL {
        let fm = FileManager.default
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = prefix + f.string(from: Date())
        var backup = backupRoot.appendingPathComponent(stamp, isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: backup.path) {
            backup = backupRoot.appendingPathComponent("\(stamp)-\(n)", isDirectory: true)
            n += 1
        }
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)
        return backup
    }

    private func makeBackupDir() throws -> URL { try Self.uniqueBackupDir() }

    /// A korábbi verziók `detkapu-adminisztracio` skilljét, ha az alkalmazás telepítette (jelölőfájl van benne), másolat után eltávolítja,
    /// hogy ne legyen két skill. A kézzel telepített (jelölés nélküli) skillhez, például a sajátodhoz, nem nyúl.
    private func replaceLegacySkill(in folder: URL) -> [String] {
        let fm = FileManager.default
        let legacy = folder.appendingPathComponent(Self.legacySkillName, isDirectory: true)
        guard fm.fileExists(atPath: legacy.appendingPathComponent("SKILL.md").path) else { return [] }
        guard fm.fileExists(atPath: legacy.appendingPathComponent(Self.markerName).path) else {
            return ["A mappában van egy kézzel telepített „\(Self.legacySkillName)” skill is. Ezt nem módosítottuk; ha nincs rá szükséged, töröld, hogy ne legyen két hasonló skill."]
        }
        do {
            let backup = try makeBackupDir()
            try fm.copyItem(at: legacy, to: backup.appendingPathComponent(Self.legacySkillName))
            try fm.removeItem(at: legacy)
            return ["A korábbi „\(Self.legacySkillName)” skillt lecseréltük az új „\(Self.skillName)” névre (másolat: \(backup.path))."]
        } catch {
            return ["A korábbi „\(Self.legacySkillName)” skillt nem sikerült eltávolítani (\(error.localizedDescription)); töröld kézzel."]
        }
    }

    /// A korábbi (Gemini CLI-s) telepítés, ha az alkalmazás telepítette: a Gemini CLI magánszemélyeknek megszűnt, ezért a másolatot
    /// mentés után eltávolítjuk. A jelölés nélküli (kézzel másolt) skillhez nem nyúlunk.
    private func retireGeminiCopy() -> String? {
        let fm = FileManager.default
        let old = Self.homeDir.appendingPathComponent(".gemini/skills/\(Self.skillName)", isDirectory: true)
        guard fm.fileExists(atPath: old.appendingPathComponent("SKILL.md").path),
              fm.fileExists(atPath: old.appendingPathComponent(Self.markerName).path) else { return nil }
        do {
            let backup = try Self.uniqueBackupDir(prefix: "gemini-")
            try fm.copyItem(at: old, to: backup.appendingPathComponent(Self.skillName))
            try fm.removeItem(at: old)
            return "A régi, Gemini CLI-hez telepített másolatot (~/.gemini/skills) eltávolítottuk, mert a Gemini CLI magánszemélyeknek megszűnt (másolat: \(backup.path))."
        } catch {
            return "A régi Gemini CLI-s másolatot (~/.gemini/skills) nem sikerült eltávolítani (\(error.localizedDescription)); töröld kézzel."
        }
    }

    // MARK: Antigravity CLI

    static let agyInstallCommand = "curl -fsSL https://antigravity.google/cli/install.sh | bash"
    /// Az `agy` parancs a telepítő alapértelmezett helyén (~/.local/bin/agy).
    static var agyURL: URL { homeDir.appendingPathComponent(".local/bin/agy") }
    static var agyInstalled: Bool { FileManager.default.isExecutableFile(atPath: agyURL.path) }

    // MARK: Segédek a „Kész” lépéshez

    func revealInFinder() {
        guard let first = results.first else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: first.path).appendingPathComponent("SKILL.md")])
    }

    func openClaude() {
        if let url = claudeAppURL { NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) }
        else if let url = URL(string: "https://claude.ai/download") { NSWorkspace.shared.open(url) }
    }

    /// A csomagolt Antigravity CLI útmutató (az alkalmazás Resources/guide/antigravity.html fájlja).
    static var antigravityGuideURL: URL? { Bundle.main.url(forResource: "antigravity", withExtension: "html", subdirectory: "guide") }

    func openAntigravityGuide() {
        if let u = Self.antigravityGuideURL { NSWorkspace.shared.open(u) }
    }

    func copyAgyInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.agyInstallCommand, forType: .string)
    }

    func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("/\(Self.skillName)", forType: .string)
    }
}

// MARK: - Ablak

final class SkillInstallerWindow: NSObject, NSWindowDelegate {
    static let shared = SkillInstallerWindow()
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let installer = SkillInstaller(model: model)
            let paletteID = UserDefaults.standard.string(forKey: "palette") ?? "blue"
            let root = SkillInstallerView(installer: installer)
                .environmentObject(model)
                .environment(\.palette, Palette.byID(paletteID))
            let hosting = NSHostingController(rootView: root)
            if #available(macOS 13.0, *) { hosting.sizingOptions = [] }
            let w = NSWindow(contentViewController: hosting)
            w.styleMask = [.titled, .closable]
            w.title = "OTS Adminisztráció skill telepítése"
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 580, height: 640))
            w.center()
            w.delegate = self
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil   // legközelebb frissen indul a varázsló
        window = nil
    }
}
