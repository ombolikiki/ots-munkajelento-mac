import Foundation

/// Utazás (1.8.0): a napon belüli következő út alapból az előző fordítottja (Győr - Nyúl után Nyúl - Győr).
extension AppModel {
    /// A nap, amelyre az űrlap éppen bejegyzést készít (a kézi bevitelnél a kiválasztott nap, egyébként a mai vagy a naptári rés napja).
    var formReferenceDay: Date { mode == .manual ? selectedDay : (pendingSlot?.day ?? Date()) }

    /// A hely szövege a Kiindulás/Cél mezőbe: `Település` vagy `Település, utca házszám` (a kanonikus cím végéről a település lekerül).
    static func placeText(_ p: RoutePoint) -> String {
        guard let a = p.address, !a.isEmpty else { return p.name }
        let suffix = ", " + p.name
        if a.count > suffix.count, a.lowercased().hasSuffix(suffix.lowercased()) {
            return p.name + ", " + String(a.dropLast(suffix.count))
        }
        return p.name
    }

    /// Az út fordítottja: Kiindulás = az útvonal utolsó pontja, Cél = a többi pont fordított sorrendben (a pontos címek velük együtt).
    /// Oda-vissza útnál (az útvonal ugyanoda tér vissza) nincs fordítás: nil.
    static func reverseTrip(of e: Entry, home: String) -> (departure: String, destination: String)? {
        let points = OTSManual.routeDetail(e, home: home)
        guard points.count >= 2, let first = points.first, let last = points.last,
              first.name.caseInsensitiveCompare(last.name) != .orderedSame else { return nil }
        let reversed = Array(points.reversed())
        return (placeText(reversed[0]), reversed.dropFirst().map(placeText).joined(separator: ", "))
    }

    /// Ha a napon már van Utazás, az új űrlap alapból annak a fordítottja (Kiindulás, Cél, Tevékenység). Csak akkor írja át a mezőket, ha a
    /// felhasználó még nem szerkesztette őket (üresek, a székhely, vagy az előző automatikus kitöltés).
    func prefillReverseTrip() {
        guard selectedType?.isTravel == true else { return }
        let initial = destination.isEmpty && (departure.isEmpty || departure == homePlace)
        let auto = travelAuto.map { $0.dep == departure && $0.dest == destination && $0.act == activity } ?? false
        guard initial || auto else { return }
        let prev = entries(on: formReferenceDay).last(where: { $0.type == ActivityType.travel.code })
        if let prev = prev, let rev = Self.reverseTrip(of: prev, home: homePlace) {
            departure = rev.departure
            destination = rev.destination
            if activity.isEmpty || auto { activity = prev.activity }
            travelAuto = (departure, destination, activity)
        } else if auto {
            departure = homePlace
            destination = ""
            activity = ""
            travelAuto = nil
        }
    }
}
