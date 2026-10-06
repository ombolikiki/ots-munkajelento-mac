import Foundation

/// A naptáresemények értelmezése (docs/NAPTAR_JELOLESEK.md). Tiszta függvények: nem használ EventKitet,
/// ezért valódi naptár nélkül tesztelhető. A dátumszámítás csak a védett `DateUtil` függvényeivel történik.

/// Egy naptáresemény az értelmezőnek (az EventKit-réteg tölti ki).
struct CalendarEventInput: Equatable {
    /// Az esemény egyedi azonosítója (ismétlődő eseménynél a példány kezdetével kiegészítve).
    var id: String
    var title: String
    var location: String = ""
    var notes: String = ""
    var start: Date
    var end: Date
    var isAllDay: Bool = false
    var isDeclined = false
    var isCancelled = false
}

/// Egy napra eső, bejegyzésre váltható rész.
struct CalendarDraft: Equatable {
    /// Az esemény azonosítója + `#` + a nap (YYYY-MM-DD); így egy esemény minden napja külön azonosítót kap.
    var calendarID: String
    var date: String
    var start: Date?
    var end: Date?
    var durationSeconds: Int
    var type: ActivityType
    var workplace: String
    /// Pontos címek ` - `-vel elválasztva (csak a teljes címek, a puszta településnév nem).
    var address: String?
    var quantity: Int?
    var activity: String
    var departure: String?
    var arrival: String?

    func entry(id: UUID = UUID()) -> Entry {
        Entry(id: id, date: date, start: start, end: end, durationSeconds: durationSeconds,
              workplace: workplace, type: type.rawValue, typeLabel: type.label, unit: type.unit.rawValue,
              quantity: type.hasQuantity ? max(1, quantity ?? 1) : nil, activity: activity, source: "calendar",
              departure: departure, arrival: arrival, address: address, calendarID: calendarID)
    }
}

/// Ami miatt egy esemény „Hiányos” listára kerül (automatikusan nem vihető át).
enum CalendarProblem: Equatable {
    case missingWorkplace, missingActivity, missingDeparture, multipleAddresses
    case wholeDayNotAllowed, noDuration, tooLong

    var text: String {
        switch self {
        case .missingWorkplace: return "Nincs megadva a munkahely (Helyszín mező vagy @Település)."
        case .missingActivity: return "Az Utazásnál a Tevékenység (az út célja) kötelező."
        case .missingDeparture: return "Nincs megadva az Indulás, és nincs székhely sem a Beállításokban."
        case .multipleAddresses: return "Több cím szerepel a Helyszínben; válaszd ki a munkahelyet."
        case .wholeDayNotAllowed: return "Egész napos eseményként csak a Szabadság, a Szabadnap és a Munkaszüneti nap értelmezett."
        case .noDuration: return "Az esemény időtartama nulla vagy negatív."
        case .tooLong: return "Az esemény túl hosszú (több mint 31 nap)."
        }
    }
}

enum CalendarSkipReason: Equatable { case notFinished, declined, cancelled }

enum CalendarOutcome: Equatable {
    /// Hiánytalan: a bejegyzések automatikusan átvehetők.
    case imported([CalendarDraft])
    /// A típus felismerhető, de valami hiányzik; a részleges adatok az előtöltéshez.
    case incomplete(type: ActivityType, drafts: [CalendarDraft], problems: [CalendarProblem])
    /// A cím nem ismert típussal kezdődik.
    case unrecognized(title: String)
    case skipped(CalendarSkipReason)
}

enum CalendarParser {
    // MARK: Típusnevek

    /// A felismert típusnevek (kisbetű- és ékezetfüggetlenül, a leghosszabb egyező előtag nyer).
    private static let typeNames: [(name: String, type: ActivityType)] = [
        ("Istentisztelet", .preaching),
        ("Látogatás", .visiting),
        ("Missziós látogatás", .missionVisiting),
        ("Ügyintézés", .officeWork), ("Ügy", .officeWork),
        ("Értekezlet", .meeting), ("Ért", .meeting),
        ("Evangelizáció", .evangelisation), ("Evang", .evangelisation),
        ("Bibliaóra", .bibleHour), ("Bibl", .bibleHour),
        ("Továbbképzés", .training), ("Képzés", .training),
        ("Tartott képzés", .heldTraining), ("Tartott továbbképzés", .heldTraining),
        ("Adminisztráció", .administration), ("Admin", .administration),
        ("Felkészülés", .preparing), ("Felk", .preparing),
        ("Utazás", .travel), ("Utaz", .travel),
        ("Szabadság", .holiday),
        ("Szabadnap", .dayOff),
        ("Munkaszüneti nap", .publicHoliday), ("Munkaszüneti", .publicHoliday)
    ]

    private static let foldedTypeNames: [(chars: [String], type: ActivityType)] = typeNames
        .map { (foldChars(Array($0.name)), $0.type) }
        .sorted { $0.0.count > $1.0.count }

    /// Karakterenkénti kisbetű- és ékezetfüggetlen forma (a hosszt megtartja).
    static func foldChars(_ chars: [Character]) -> [String] {
        chars.map { c in
            c.isWhitespace ? " " : String(c).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "hu_HU"))
        }
    }

    /// Kisbetű- és ékezetfüggetlen, egyszerűsített szóközű forma (összehasonlításhoz).
    static func fold(_ s: String) -> String {
        foldChars(Array(s)).joined().split(separator: " ").joined(separator: " ")
    }

    /// A cím elején álló típus és a maradék szöveg. Nil, ha nincs ismert típus.
    static func matchType(_ title: String) -> (type: ActivityType, rest: String)? {
        let chars = Array(normalizeSpaces(title))
        let folded = foldChars(chars)
        for entry in foldedTypeNames {
            let n = entry.chars.count
            guard folded.count >= n, Array(folded[0..<n]) == entry.chars else { continue }
            if n < chars.count, chars[n].isLetter || chars[n].isNumber { continue }   // szóhatár: „Ügyes” nem „Ügy”
            return (entry.type, String(chars[n...]))
        }
        return nil
    }

    /// A felesleges szóközök törlése, a szokatlan szóközök (pl. nem törhető) sima szóközre cserélése.
    static func normalizeSpaces(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// A típus első (kanonikus) neve a táblázatból; a felhasználó által választott típus beillesztéséhez.
    static func canonicalName(for type: ActivityType) -> String? {
        typeNames.first { $0.type == type }?.name
    }

    /// Értelmezés kényszerített típussal (a „Nem felismert” listáról egyszeri döntésként): a cím elé a típus neve kerül.
    static func parse(_ event: CalendarEventInput, forcedType: ActivityType, now: Date, home: String) -> CalendarOutcome {
        guard let name = canonicalName(for: forcedType) else { return .unrecognized(title: normalizeSpaces(event.title)) }
        var e = event
        e.title = name + ": " + normalizeSpaces(event.title)
        return parse(e, now: now, home: home)
    }

    // MARK: Címek

    private static let countries: Set<String> = ["magyarorszag", "hungary", "hu"]

    /// A Helyszín mező szétvágása ` - ` (szóközzel körülvett kötőjel; a telefonok „–” és „—” jele is) mentén.
    static func splitLocations(_ s: String) -> [String] {
        let chars = Array(s)
        var parts: [String] = []
        var cur = ""
        var i = 0
        while i < chars.count {
            if chars[i].isWhitespace, i + 2 < chars.count, "-–—".contains(chars[i + 1]), chars[i + 2].isWhitespace {
                parts.append(cur); cur = ""; i += 3
            } else {
                cur.append(chars[i]); i += 1
            }
        }
        parts.append(cur)
        return parts.map { normalizeSpaces($0) }.filter { !$0.isEmpty }
    }

    struct Place: Equatable {
        var settlement: String?
        /// A teljes cím, ha több részből áll (vessző); a puszta településnév nem pontos cím.
        var address: String?
    }

    /// Egy helyszín településének és pontos címének kinyerése. A település az utolsó vessző utáni, szám nélküli rész
    /// (az irányítószám és a záró „Magyarország” nélkül); ha az utolsó rész házszámos, a megelőző szám nélküli részt nézzük.
    static func place(_ raw: String) -> Place {
        let parts = raw.split(separator: ",").map { normalizeSpaces(String($0)) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return Place(settlement: nil, address: nil) }
        var usable = parts
        if usable.count > 1, let last = usable.last, countries.contains(fold(last)) { usable.removeLast() }
        var settlement: String?
        for p in usable.reversed() {
            let s = stripPostalCode(p)
            if !s.isEmpty && !s.contains(where: { $0.isNumber }) { settlement = s; break }
        }
        return Place(settlement: settlement, address: parts.count >= 2 ? parts.joined(separator: ", ") : nil)
    }

    private static func stripPostalCode(_ p: String) -> String {
        let chars = Array(p)
        var i = 0
        while i < chars.count, chars[i].isNumber { i += 1 }
        if i > 0, i < chars.count, chars[i] == " " { return normalizeSpaces(String(chars[(i + 1)...])) }
        return p
    }

    // MARK: Cím (típus utáni rész)

    private struct Parts {
        var settlement: String?      // @Település
        var quantity: Int?
        var activity: String         // a kettőspont / ` - ` utáni szöveg (vagy a maradék)
    }

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
    private static let qtyX = regex("(?<![\\p{L}\\p{N}])[×x]\\s*(\\d{1,3})(?![\\p{L}\\p{N}])")
    private static let qtyWord = regex("(?<![\\p{L}\\p{N}])(\\d{1,3})\\s*(?:fő|fo|alkalom)(?![\\p{L}])")

    /// Kinyeri az utolsó mennyiség-jelölést (×3, x3, 3 fő, 3 alkalom), és kivágja a szövegből.
    private static func extractQuantity(_ s: String) -> (rest: String, quantity: Int?) {
        let ns = s as NSString
        var best: (range: NSRange, value: Int)?
        for re in [qtyX, qtyWord] {
            guard let re = re else { continue }
            for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) where m.numberOfRanges > 1 {
                let v = Int(ns.substring(with: m.range(at: 1))) ?? 1
                if best == nil || m.range.location > best!.range.location { best = (m.range, v) }
            }
        }
        guard let b = best else { return (s, nil) }
        let rest = normalizeSpaces(ns.replacingCharacters(in: b.range, with: " "))
        return (rest, min(999, max(1, b.value)))
    }

    /// A típus utáni szöveg szétvágása: [@Település] [mennyiség] [: vagy - Tevékenység].
    private static func splitRest(_ rest: String, wantsQuantity: Bool) -> Parts {
        let chars = Array(rest)
        var head = String(chars), tail = "", hasSeparator = false
        var i = 0
        while i < chars.count {
            if chars[i] == ":" {
                head = String(chars[..<i]); tail = String(chars[(i + 1)...]); hasSeparator = true; break
            }
            if chars[i].isWhitespace, i + 2 < chars.count, "-–—".contains(chars[i + 1]), chars[i + 2].isWhitespace {
                head = String(chars[..<i]); tail = String(chars[(i + 3)...]); hasSeparator = true; break
            }
            i += 1
        }
        var quantity: Int?
        if wantsQuantity {
            let r = extractQuantity(head)
            head = r.rest; quantity = r.quantity
        }
        var settlement: String?
        if let at = head.firstIndex(of: "@") {
            let s = normalizeSpaces(String(head[head.index(after: at)...]))
            settlement = s.isEmpty ? nil : s
            head = normalizeSpaces(String(head[..<at]))
        }
        head = normalizeSpaces(head)
        var activity = normalizeSpaces(tail)
        if !hasSeparator { activity = head }                  // „Értekezlet heti megbeszélés”
        else if activity.isEmpty { activity = head }
        if wantsQuantity && quantity == nil {
            let r = extractQuantity(activity)
            activity = r.rest; quantity = r.quantity
        }
        return Parts(settlement: settlement, quantity: quantity, activity: activity)
    }

    // MARK: Utazás

    private struct Route {
        var departure: String?
        var workplaces: [String] = []
        var arrival: String?
        var roundTrip = false
    }

    private static func commaList(_ s: String) -> [String] {
        s.split(separator: ",").map { normalizeSpaces(String($0)) }.filter { !$0.isEmpty }
    }

    private static func hasRouteMarker(_ s: String) -> Bool {
        s.contains("→") || s.contains("->") || s.contains("⇄") || s.contains("<->")
            || s.range(of: "oda-vissza", options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static func parseRoute(_ s: String) -> Route {
        var text = s
        var roundMarker: Range<String.Index>?
        for m in ["⇄", "<->"] { if let r = text.range(of: m) { roundMarker = r; break } }
        if roundMarker == nil { roundMarker = text.range(of: "oda-vissza", options: [.caseInsensitive, .diacriticInsensitive]) }
        if let r = roundMarker {
            let dep = normalizeSpaces(String(text[..<r.lowerBound]))
            let mids = commaList(String(text[r.upperBound...]))
            return Route(departure: dep.isEmpty ? nil : dep, workplaces: mids, arrival: dep.isEmpty ? nil : dep, roundTrip: true)
        }
        text = text.replacingOccurrences(of: "->", with: "→")
        let pieces = text.components(separatedBy: "→").map { normalizeSpaces($0) }
        var route = Route()
        guard pieces.count >= 2 else { return route }
        route.departure = pieces[0].isEmpty ? nil : pieces[0]
        if pieces.count == 2 {
            // „A → B”: nincs külön munkahely; az Érkezés a második pont, a munkahely hiányos marad (nem tippelünk).
            route.arrival = pieces[1].isEmpty ? nil : pieces[1]
        } else {
            route.arrival = pieces[pieces.count - 1].isEmpty ? nil : pieces[pieces.count - 1]
            route.workplaces = pieces[1..<(pieces.count - 1)].flatMap { commaList($0) }
        }
        return route
    }

    // MARK: Beírt hely (Indulás, Érkezés)

    /// Egy beírt hely: település, és ha pontos címet is megadtak, a cím (utcával elöl, településsel a végén, mint a naptári címek).
    struct ParsedPlace: Equatable {
        var settlement: String
        var address: String?
    }

    /// Az utcára, házszámra utaló szavak (kisbetű- és ékezetfüggetlenül): ezekből tudjuk, hogy a vesszők közti rész cím, nem újabb település.
    private static let streetWords: Set<String> = ["ut", "utca", "u", "ter", "korut", "krt", "setany", "koz", "dulo", "sor", "fasor",
                                                   "rakpart", "liget", "major", "emelet", "em", "ajto", "fszt", "lepcsohaz", "epulet", "ep", "hrsz"]
    /// A cím folytatása (az utcarész után): emelet, ajtó stb.; ezek nem új cím.
    private static let continuationWords: Set<String> = ["emelet", "em", "ajto", "fszt", "lepcsohaz", "epulet", "ep", "hrsz"]

    private static func words(_ token: String) -> [String] {
        fold(token).split(separator: " ").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,;")) }.filter { !$0.isEmpty }
    }
    private static func isStreetLike(_ token: String) -> Bool {
        token.contains(where: { $0.isNumber }) || words(token).contains { streetWords.contains($0) }
    }
    private static func isContinuation(_ token: String) -> Bool {
        words(token).contains { continuationWords.contains($0) }
    }

    /// Egy vagy több beírt hely: „Tata”, „Tata, Fő út 1.”, „Tata, Mór”, „Tata, Fő út 1., Mór”.
    /// - A vesszővel elválasztott részek közül az utcára/házszámra utaló rész (Fő út 1., Kossuth u.) a **megelőző településhez** tartozó cím
    ///   (település elöl); ha még nincs település, a következőhöz (a fordított „Fő út 1., Tata” is érthető).
    /// - Minden más rész új település. A helyeket ` - ` vagy `;` is elválaszthatja (például `Tata - Mór u. 5., Mór`).
    /// - Az irányítószám (`9021 Győr`) és a záró „Magyarország” elmarad.
    /// Nil, ha üres, vagy egy cím mellé nem kerül település.
    static func parsePlaces(_ raw: String) -> [ParsedPlace]? {
        var groups: [String] = []
        for g in raw.split(separator: ";") { groups += splitLocations(String(g)) }
        guard !groups.isEmpty else { return nil }
        var out: [ParsedPlace] = []
        for g in groups {
            var tokens = g.split(separator: ",").map { normalizeSpaces(String($0)) }.filter { !$0.isEmpty }
            if tokens.count > 1, let last = tokens.last, countries.contains(fold(last)) { tokens.removeLast() }
            var pending: [String] = []                       // település nélküli (utcával kezdődő) cím
            var current: (settlement: String, street: [String])?
            func flush() {
                if let c = current {
                    out.append(ParsedPlace(settlement: c.settlement, address: c.street.isEmpty ? nil : (c.street + [c.settlement]).joined(separator: ", ")))
                    current = nil
                }
            }
            for t in tokens {
                let core = stripPostalCode(t)
                if !core.isEmpty, isStreetLike(core) {
                    if var c = current {
                        if c.street.isEmpty || isContinuation(core) {
                            c.street.append(core); current = c
                        } else {
                            flush(); pending = [core]        // új, utcával kezdődő cím
                        }
                    } else {
                        pending.append(core)
                    }
                } else if !core.isEmpty {
                    if pending.isEmpty {
                        flush(); current = (core, [])
                    } else {
                        out.append(ParsedPlace(settlement: core, address: (pending + [core]).joined(separator: ", ")))
                        pending = []
                    }
                }
            }
            flush()
            if !pending.isEmpty { return nil }
        }
        return out.isEmpty ? nil : out
    }

    /// Egyetlen beírt hely (például a Kiindulás); nil, ha több helyet adtak meg vagy hibás.
    static func parsePlace(_ raw: String) -> ParsedPlace? {
        guard let list = parsePlaces(raw), list.count == 1 else { return nil }
        return list[0]
    }

    // MARK: Fő belépési pont

    /// Egy naptáresemény értelmezése. `now`: a pillanatnyi idő (csak a már lezajlott események kerülnek át),
    /// `home`: a székhely (az Utazás Indulás/Érkezés alapértéke).
    static func parse(_ event: CalendarEventInput, now: Date, home: String) -> CalendarOutcome {
        if event.isCancelled { return .skipped(.cancelled) }
        if event.isDeclined { return .skipped(.declined) }

        let todayStart = DateUtil.startOfDay(now)
        // A napok, amelyekre bejegyzés készülhet.
        var wholeDays: [Date] = []
        do {
            let first = DateUtil.startOfDay(event.start)
            let last = event.end > event.start ? DateUtil.startOfDay(event.end.addingTimeInterval(-1)) : first
            var d = first
            var n = 0
            while d <= last, n < 400 { wholeDays.append(d); d = DateUtil.addDays(d, 1); n += 1 }
        }
        if event.isAllDay {
            if !wholeDays.contains(where: { $0 < todayStart }) { return .skipped(.notFinished) }
        } else if max(event.start, event.end) > now {
            return .skipped(.notFinished)
        }

        guard let (type, rest) = matchType(event.title) else {
            return .unrecognized(title: normalizeSpaces(event.title))
        }

        var problems: [CalendarProblem] = []
        let parts = splitRest(rest, wantsQuantity: type.hasQuantity)

        // Helyszín: települések és pontos címek.
        let places = splitLocations(event.location).map { place($0) }
        let locationSettlements = places.compactMap { $0.settlement }
        let exactAddresses = places.compactMap { $0.address }

        var workplace = ""
        var departure: String?, arrival: String?
        var activity = parts.activity
        var addressList = exactAddresses

        if type.isTravel {
            var route = Route()
            var goal = activity
            if let bar = activity.firstIndex(of: "|") {
                let left = normalizeSpaces(String(activity[..<bar]))
                goal = normalizeSpaces(String(activity[activity.index(after: bar)...]))
                if hasRouteMarker(left) { route = parseRoute(left) } else { route.workplaces = commaList(left) }
            } else if hasRouteMarker(activity) {
                route = parseRoute(activity)
                goal = ""
            }
            if goal.isEmpty {
                let firstLine = event.notes.split(whereSeparator: { $0.isNewline }).map { normalizeSpaces(String($0)) }.first { !$0.isEmpty }
                goal = firstLine ?? ""
            }
            activity = goal
            if route.workplaces.isEmpty, let at = parts.settlement { route.workplaces = [at] }
            if route.workplaces.isEmpty { route.workplaces = locationSettlements }
            let homeName = normalizeSpaces(home)
            let dep = route.departure ?? (homeName.isEmpty ? nil : homeName)
            let arr = route.arrival ?? (route.roundTrip ? dep : (homeName.isEmpty ? nil : homeName))
            // Egyetlen nyíl (A → B) esetén az Érkezés megadott, a munkahely hiányzik.
            departure = dep; arrival = arr
            workplace = route.workplaces.joined(separator: ", ")
            if dep == nil || arr == nil { problems.append(.missingDeparture) }
            if workplace.isEmpty { problems.append(.missingWorkplace) }
            if activity.isEmpty { problems.append(.missingActivity) }
        } else if !type.isWholeDay {
            if let at = parts.settlement {
                workplace = at
                // A cím csak akkor tartozik a munkahelyhez, ha ugyanabban a településben van.
                addressList = places.filter { ($0.settlement.map { fold($0) } ?? "") == fold(at) }.compactMap { $0.address }
            } else if let first = locationSettlements.first {
                workplace = first
                if places.count > 1 { problems.append(.multipleAddresses) }
                addressList = places.first?.address.map { [$0] } ?? []
            } else {
                problems.append(.missingWorkplace)
            }
        } else {
            // Egész napos típus: a munkahely nem kötelező, de ha meg van adva, megmarad.
            workplace = parts.settlement ?? locationSettlements.first ?? ""
            addressList = workplace.isEmpty ? [] : addressList
        }
        let addressText: String? = addressList.isEmpty ? nil : addressList.joined(separator: " - ")

        // Napi szeletek.
        var drafts: [CalendarDraft] = []
        func draft(day: Date, start: Date?, end: Date?, secs: Int) -> CalendarDraft {
            let key = Fmt.dayFormatter.string(from: day)
            return CalendarDraft(calendarID: "\(event.id)#\(key)", date: key, start: start, end: end, durationSeconds: secs,
                                 type: type, workplace: workplace, address: addressText,
                                 quantity: type.hasQuantity ? (parts.quantity ?? 1) : nil, activity: activity,
                                 departure: departure, arrival: arrival)
        }

        if event.isAllDay || type.isWholeDay {
            if !type.isWholeDay { problems.append(.wholeDayNotAllowed) }
            let days = event.isAllDay ? wholeDays.filter { $0 < todayStart } : wholeDays
            for d in days { drafts.append(draft(day: d, start: nil, end: nil, secs: 0)) }
        } else {
            let total = Int(event.end.timeIntervalSince(event.start).rounded())
            if total <= 0 && !type.hasQuantity {
                problems.append(.noDuration)
                drafts.append(draft(day: DateUtil.startOfDay(event.start), start: event.start, end: event.end, secs: 0))
            } else if type.hasQuantity {
                // Alkalom és fő: az időtartam csak tájékoztató, ezért nem bontjuk szét (a mennyiség nem duplázódhat).
                drafts.append(draft(day: DateUtil.startOfDay(event.start), start: event.start, end: event.end, secs: max(0, total)))
            } else if wholeDays.count > 32 {
                problems.append(.tooLong)
                drafts.append(draft(day: DateUtil.startOfDay(event.start), start: event.start, end: event.end, secs: total))
            } else {
                // Éjfélenként két (vagy több) részre bontjuk: minden nap a saját óraszámát kapja.
                var day = DateUtil.startOfDay(event.start)
                var n = 0
                while day < event.end, n < 33 {
                    let next = DateUtil.addDays(day, 1)
                    let s = max(event.start, day), e = min(event.end, next)
                    let secs = Int(e.timeIntervalSince(s).rounded())
                    if secs > 0 { drafts.append(draft(day: day, start: s, end: e, secs: secs)) }
                    day = next; n += 1
                }
            }
        }

        if problems.isEmpty && !drafts.isEmpty { return .imported(drafts) }
        return .incomplete(type: type, drafts: drafts, problems: problems)
    }
}
