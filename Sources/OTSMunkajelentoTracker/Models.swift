import Foundation

enum Mode: String, CaseIterable, Identifiable {
    case timer = "Időzítő"
    case manual = "Kézi bevitel"
    case pomodoro = "Pomodoro"
    case calendar = "Naptár"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .timer: return "stopwatch"
        case .manual: return "square.and.pencil"
        case .pomodoro: return "timer"
        case .calendar: return "calendar"
        }
    }
}

/// Mértékegység az OTS Havi munkajelentő oszlopai szerint.
enum Unit: String, Codable {
    case hours = "ora"
    case occasions = "alkalom"
    case people = "fo"
    case wholeDay = "egesz_nap"
}

/// Menüsori ikon: SF Symbol, emoji vagy az Adventista jelkép.
struct IconChoice: Identifiable, Hashable {
    enum Kind: Hashable {
        case symbol(String)
        case emoji(String)
        case logo
    }
    let id: String
    let label: String
    let kind: Kind
}

enum IconSets {
    static let main: [IconChoice] = [
        IconChoice(id: "clock", label: "Óra", kind: .symbol("clock")),
        IconChoice(id: "stopwatch", label: "Stopper", kind: .symbol("stopwatch")),
        IconChoice(id: "hourglass", label: "Homokóra", kind: .symbol("hourglass")),
        IconChoice(id: "clipboard", label: "Napló", kind: .symbol("list.bullet.clipboard")),
        IconChoice(id: "book", label: "Könyv", kind: .symbol("book.closed")),
        IconChoice(id: "adventist", label: "Adventista jelkép", kind: .logo)
    ]
    static let pomoWork: [IconChoice] = [
        IconChoice(id: "tomato", label: "Paradicsom", kind: .emoji("🍅")),
        IconChoice(id: "timer", label: "Időzítő", kind: .symbol("timer")),
        IconChoice(id: "flame", label: "Láng", kind: .symbol("flame.fill")),
        IconChoice(id: "brain", label: "Fókusz", kind: .symbol("brain.head.profile")),
        IconChoice(id: "bolt", label: "Villám", kind: .symbol("bolt.fill")),
        IconChoice(id: "clock", label: "Óra", kind: .symbol("clock"))
    ]
    static let pomoBreak: [IconChoice] = [
        IconChoice(id: "cup", label: "Csésze", kind: .symbol("cup.and.saucer")),
        IconChoice(id: "coffee", label: "Kávé", kind: .emoji("☕️")),
        IconChoice(id: "tea", label: "Tea", kind: .emoji("🍵")),
        IconChoice(id: "leaf", label: "Levél", kind: .symbol("leaf")),
        IconChoice(id: "walk", label: "Séta", kind: .symbol("figure.walk")),
        IconChoice(id: "moon", label: "Pihenés", kind: .symbol("moon.zzz"))
    ]

    static let reminder: [IconChoice] = [
        IconChoice(id: "warning", label: "Figyelmeztetés", kind: .symbol("exclamationmark.triangle.fill")),
        IconChoice(id: "bell", label: "Csengő", kind: .symbol("bell.badge.fill")),
        IconChoice(id: "circle", label: "Felkiáltójel", kind: .symbol("exclamationmark.circle.fill")),
        IconChoice(id: "calendar", label: "Naptár", kind: .symbol("calendar.badge.exclamationmark")),
        IconChoice(id: "flag", label: "Zászló", kind: .symbol("flag.fill")),
        IconChoice(id: "hourglass", label: "Homokóra", kind: .symbol("hourglass.bottomhalf.filled"))
    ]

    static func choice(_ id: String, in list: [IconChoice]) -> IconChoice { list.first { $0.id == id } ?? list[0] }
}

/// A lejárt időzítőket jelző hangok (rendszerhangok).
enum Sounds {
    static let none = "none"
    static let names = ["Glass", "Ping", "Hero", "Submarine", "Funk", "Pop", "Tink", "Bottle", "Blow", "Frog", "Morse", "Purr", "Basso", "Sosumi"]
}

/// A tevékenység kategóriája. A `code` az OTS Havi munkajelentő grid mezőazonosítója (a beépített OTS-típusoknál),
/// az egyéni kategóriáknál `EGYEDI_…` kezdetű kód, ezeknek nincs OTS-megfelelőjük.
struct ActivityType: Identifiable, Hashable {
    let code: String
    let group: String
    let shortLabel: String
    let label: String
    let unit: Unit
    var isCustom = false

    var id: String { code }
    var rawValue: String { code }
    var isWholeDay: Bool { unit == .wholeDay }
    /// Az Utazás típus: Indulás – Munkahely(ek) – Érkezés mezőkkel.
    var isTravel: Bool { code == "TRAVEL" }
    var hasQuantity: Bool { unit == .occasions || unit == .people }
    /// A szám után írt mértékegység.
    var quantityUnit: String { unit == .people ? "fő" : "alkalom" }

    private static func b(_ code: String, _ group: String, _ short: String, _ label: String? = nil, _ unit: Unit) -> ActivityType {
        ActivityType(code: code, group: group, shortLabel: short, label: label ?? short, unit: unit)
    }

    static let preaching = b("PREACHING", "Gyülekezet", "Istentisztelet", nil, .occasions)
    static let visiting = b("VISITING", "Gyülekezet", "Látogatás", "Látogatás (gyülekezet)", .people)
    static let officeWork = b("OFFICE_WORK", "Gyülekezet", "Ügyintézés", nil, .hours)
    static let meeting = b("MEETING", "Gyülekezet", "Értekezlet", nil, .hours)
    static let evangelisation = b("EVANGELISATION", "Misszió", "Evangelizáció", nil, .occasions)
    static let bibleHour = b("BIBLE_HOUR", "Misszió", "Bibliaóra", nil, .occasions)
    static let missionVisiting = b("MISSION_VISITING", "Misszió", "Látogatás", "Látogatás (misszió)", .people)
    static let training = b("TRAINING", "Továbbképzés", "Résztvevő", "Továbbképzés – résztvevő", .hours)
    static let heldTraining = b("HELD_TRAINING", "Továbbképzés", "Tartott", "Továbbképzés – tartott", .hours)
    static let administration = b("ADMINISTRATION", "Hivatal", "Adminisztráció", nil, .hours)
    static let preparing = b("PREPARING", "Hivatal", "Felkészülés", nil, .hours)
    static let travel = b("TRAVEL", "Egyéb", "Utazás", nil, .hours)
    static let holiday = b("HOLIDAY", "Nem munkaidő", "Szabadság", nil, .wholeDay)
    static let dayOff = b("DAY_OFF", "Nem munkaidő", "Szabadnap", nil, .wholeDay)
    static let publicHoliday = b("PUBLIC_HOLIDAY", "Nem munkaidő", "Munkaszüneti nap", nil, .wholeDay)

    static let builtins: [ActivityType] = [
        preaching, visiting, officeWork, meeting, evangelisation, bibleHour, missionVisiting,
        training, heldTraining, administration, preparing, travel, holiday, dayOff, publicHoliday
    ]

    static let customGroup = "Egyéni"
    static let customPrefix = "EGYEDI_"

    /// A felhasználó saját kategóriái és az elrejtett beépítettek (az AppModel tartja szinkronban).
    static var custom: [ActivityType] = []
    static var hidden: Set<String> = []

    /// A legördülő menüben megjelenő kategóriák.
    static var all: [ActivityType] { builtins.filter { !hidden.contains($0.code) } + custom }

    static func lookup(code: String) -> ActivityType? {
        let c = code.trimmingCharacters(in: .whitespaces).uppercased()
        return (builtins + custom).first { $0.code == c }
    }

    static func lookup(label: String) -> ActivityType? {
        let l = label.trimmingCharacters(in: .whitespaces).lowercased()
        guard !l.isEmpty else { return nil }
        return (builtins + custom).first { $0.label.lowercased() == l || $0.shortLabel.lowercased() == l }
    }

    static var groups: [(name: String, types: [ActivityType])] {
        var result: [(String, [ActivityType])] = []
        for t in all {
            if let i = result.firstIndex(where: { $0.0 == t.group }) {
                result[i].1.append(t)
            } else {
                result.append((t.group, [t]))
            }
        }
        return result
    }
}

/// A felhasználó saját kategóriája (mentett forma).
struct CustomCategory: Codable, Hashable, Identifiable {
    var code: String
    var label: String
    var unit: String   // hours | occasions | people
    var id: String { code }

    var activityType: ActivityType {
        let u: Unit = unit == "occasions" ? .occasions : (unit == "people" ? .people : .hours)
        return ActivityType(code: code, group: ActivityType.customGroup, shortLabel: label, label: label, unit: u, isCustom: true)
    }
}

struct Entry: Codable, Identifiable, Equatable {
    var id: UUID
    /// Helyi dátum (YYYY-MM-DD), a kezdés napja.
    var date: String
    var start: Date?
    var end: Date?
    var durationSeconds: Int
    var workplace: String
    /// OTS mezőazonosító (pl. MEETING, PREPARING, DAY_OFF).
    var type: String
    var typeLabel: String
    /// ora | alkalom | fo | egesz_nap
    var unit: String
    /// Alkalom vagy fő; óránál és egész napos típusnál null.
    var quantity: Int?
    var activity: String
    /// timer | pomodoro | manual | calendar
    var source: String
    /// Csak az Utazás típusnál: honnan indult / hová érkezett. A `workplace` ilyenkor a Munkahely(ek) listája.
    var departure: String? = nil
    var arrival: String? = nil
    /// Pontos cím(ek) ` - `-vel elválasztva (a `workplace` település marad). Régi fájlokban nincs.
    var address: String? = nil
    /// A naptáresemény azonosítója (+ `#` és a nap), ha a bejegyzés a naptárból jött.
    var calendarID: String? = nil
    /// Utazásnál: az Indulás és az Érkezés pontos címe, ha meg van adva (a `departure` és az `arrival` település marad).
    var departureAddress: String? = nil
    var arrivalAddress: String? = nil

    var activityType: ActivityType? { ActivityType.lookup(code: type) }

    /// Az összesítésben beszámított idő másodpercben: az óra típusoknál az időtartam,
    /// az alkalom és a fő típusoknál darabonként 1 óra, az egész napos típusoknál nulla.
    var creditSeconds: Int {
        switch unit {
        case Unit.hours.rawValue: return durationSeconds
        case Unit.occasions.rawValue, Unit.people.rawValue: return max(1, quantity ?? 1) * 3600
        default: return 0
        }
    }
}

struct EntryFile: Codable {
    var formatVersion: Int
    var app: String
    var timezone: String
    var entries: [Entry]
}

enum Fmt {
    static let isoWithOffset: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "HH:mm"
        return f
    }()

    static let longDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "yyyy. MMMM d., EEEE"
        return f
    }()

    static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "MMM d., EEE"
        return f
    }()

    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    static func hm(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 3600, (s % 3600) / 60)
    }
}
