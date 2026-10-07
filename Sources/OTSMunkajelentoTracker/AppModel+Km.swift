import Foundation

/// Kilométeróra (1.6.0): az Utazás bejegyzésekhez opcionális induló és érkező km-állás, ellenőrzéssel, javítással és havi összeggel.
extension AppModel {
    /// A mezőbe írt szöveg km-állása: üres szövegnél nincs érték (és ez rendben van); nem szám vagy értelmetlen érték esetén `valid` hamis.
    static func kmValue(_ text: String) -> (value: Int?, valid: Bool) {
        let t = text.filter { !$0.isWhitespace }
        if t.isEmpty { return (nil, true) }
        guard let v = CSV.number(t), v >= 0, v <= 9_999_999 else { return (nil, false) }
        return (v, true)
    }

    /// Az utolsó rögzített érkező km-állás (az új út induló állásának előtöltéséhez).
    var lastEndKm: Int? { entries.last(where: { $0.endKm != nil })?.endKm }

    /// A nap, amelyre az űrlap éppen bejegyzést készít (a kézi bevitelnél a kiválasztott nap, egyébként a mai vagy a naptári rés napja).
    private var kmReferenceKey: String {
        let day: Date = mode == .manual ? selectedDay : (pendingSlot?.day ?? Date())
        return Fmt.dayFormatter.string(from: day)
    }

    /// Az előző út érkező km-állása egy új bejegyzés előtt (a megadott napig bezárólag).
    func previousEndKm(onOrBefore dayKey: String, excluding id: UUID? = nil) -> Int? {
        entries.last(where: { $0.endKm != nil && $0.date <= dayKey && $0.id != id })?.endKm
    }

    /// A km-állások hibája (nil, ha rendben): az érkezőnek nagyobbnak kell lennie az indulónál, az indulónak pedig nem lehet kisebb az előző út végállásánál.
    static func kmProblem(start: Int?, end: Int?, previous: Int?) -> String? {
        if let s = start, let e = end, e <= s {
            return "Az érkező km-állásnak nagyobbnak kell lennie az induló km-nél."
        }
        if let s = start, let p = previous, s < p {
            return "Az induló km-állás (\(s)) kisebb, mint az előző út érkező állása (\(p))."
        }
        if start == nil, let e = end, let p = previous, e <= p {
            return "Az érkező km-állás (\(e)) nem lehet kisebb az előző út érkező állásánál (\(p))."
        }
        return nil
    }

    /// Az Utazás űrlap km-mezőinek hibája (nem kötelező mezők: üresen rendben).
    var kmHint: String? {
        let s = Self.kmValue(startKmText), e = Self.kmValue(endKmText)
        if !s.valid || !e.valid { return "A km-állás egész szám legyen." }
        return Self.kmProblem(start: s.value, end: e.value, previous: previousEndKm(onOrBefore: kmReferenceKey))
    }

    /// Egy már rögzített út km-állásának javítása. Hibás értéknél a hibaüzenetet adja vissza (és nem módosít), siker esetén nil.
    @discardableResult
    func updateKm(_ id: UUID, start: String, end: String) -> String? {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return "A bejegyzés nem található." }
        let s = Self.kmValue(start), e = Self.kmValue(end)
        if !s.valid || !e.valid { return "A km-állás egész szám legyen." }
        // Előző út: a lista e bejegyzés előtti elemei közül az utolsó érkező km-állás.
        let previous = entries[..<i].last(where: { $0.endKm != nil })?.endKm
        if let problem = Self.kmProblem(start: s.value, end: e.value, previous: previous) { return problem }
        setKm(at: i, start: s.value, end: e.value)
        return nil
    }

    /// A hónap (a megadott napé) autós km-ei: az utak összege (csak a mindkét állással rögzítettek), és hány útból hiányzik valamelyik állás.
    func monthKm(containing day: Date) -> (km: Int, incomplete: Int) {
        let c = DateUtil.components(day)
        let prefix = String(format: "%04d-%02d-", c.year, c.month)
        var km = 0, incomplete = 0
        for e in entries where e.type == ActivityType.travel.code && e.date.hasPrefix(prefix) {
            if let d = e.kmDriven { km += d } else { incomplete += 1 }
        }
        return (km, incomplete)
    }
}
