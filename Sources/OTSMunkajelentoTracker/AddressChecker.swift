import Foundation
import CoreLocation

/// A pontos címek ellenőrzése az Apple beépített geokódolójával a Google Maps-hivatkozás előtt: ha a cím nem található,
/// a Maps-hivatkozásba a település kerül. Nincs API-kulcs, nincs számlázás; a naptárra és a helyadatokra nincs szükség.
/// Hálózati hiba vagy időtúllépés nem jelent „nem találtat”: ilyenkor a pontos cím marad (a Google dönt), és nem mentjük el az eredményt.
final class AddressChecker {
    static let shared = AddressChecker()

    private let cacheKey = "geo.addressCache"
    private let ud = UserDefaults.standard
    private var cache: [String: Bool]

    init() {
        cache = (UserDefaults.standard.dictionary(forKey: "geo.addressCache") as? [String: Bool]) ?? [:]
    }

    /// A geokódoló találatából szövegek, amelyekben a településnek szerepelnie kell (a hasonló nevű, távoli találat ne fogadódjon el).
    static func matches(_ texts: [String], settlement: String?) -> Bool {
        guard let s = settlement, !CalendarParser.fold(s).isEmpty else { return !texts.isEmpty }
        let want = CalendarParser.fold(s)
        return texts.contains { CalendarParser.fold($0).contains(want) }
    }

    /// A geokódolónak küldött szöveg: Magyarország hozzáadásával, ha az ország nincs benne.
    static func query(_ address: String) -> String {
        let f = CalendarParser.fold(address)
        return (f.contains("magyarorszag") || f.contains("hungary")) ? address : address + ", Magyarország"
    }

    /// Minden címre: igaz = a pontos cím használható (megtalálta, vagy nem tudtuk ellenőrizni), hamis = nem található.
    func verdicts(for addresses: [String]) async -> [String: Bool] {
        var out: [String: Bool] = [:]
        for a in Set(addresses) {
            if let c = cache[a] { out[a] = c; continue }
            switch await geocode(a) {
            case .some(let found):
                out[a] = found
                cache[a] = found
                if cache.count > 500 { cache = cache.filter { $0.value } ; if cache.count > 500 { cache = [:] } }
                ud.set(cache, forKey: cacheKey)
            case .none:
                out[a] = true
            }
        }
        return out
    }

    /// true/false: megtalálta/nem találta; nil: nem eldönthető (hálózat, időtúllépés).
    private func geocode(_ address: String) async -> Bool? {
        let settlement = address.split(separator: ",").map { String($0) }.compactMap { CalendarParser.place($0).settlement }.last
            ?? CalendarParser.place(address).settlement
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool?, Never>) in
            let lock = NSLock()
            var done = false
            func finish(_ v: Bool?) {
                lock.lock(); defer { lock.unlock() }
                guard !done else { return }
                done = true
                cont.resume(returning: v)
            }
            let geocoder = CLGeocoder()
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { geocoder.cancelGeocode(); finish(nil) }
            geocoder.geocodeAddressString(Self.query(address)) { marks, error in
                if let e = error as? CLError {
                    finish(e.code == .geocodeFoundNoResult ? false : nil)
                    return
                }
                if error != nil { finish(nil); return }
                let texts = (marks ?? []).flatMap { [$0.locality, $0.subLocality, $0.administrativeArea, $0.name].compactMap { $0 } }
                finish(Self.matches(texts, settlement: settlement))
            }
        }
    }
}
