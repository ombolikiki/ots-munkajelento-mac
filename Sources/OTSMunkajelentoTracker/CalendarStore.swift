import Foundation
import EventKit
import AppKit

/// A naptár-hozzáférés vékony rétege (EventKit, csak olvasás). Az értelmező és a szinkron a `CalendarSource`
/// protokollon át éri el a naptárat, így valódi naptár nélkül, kitalált eseményekkel tesztelhető.

enum CalendarAccess: Equatable {
    case notDetermined, granted, denied, restricted
    /// Csak írási jog van (macOS 14): az olvasáshoz teljes hozzáférés kell.
    case writeOnly

    var text: String {
        switch self {
        case .notDetermined: return "Még nem kértük az engedélyt."
        case .granted: return "Engedélyezve."
        case .denied: return "Az engedély megtagadva (Rendszerbeállítások › Adatvédelem és biztonság › Naptárak)."
        case .restricted: return "A hozzáférést a rendszer korlátozza."
        case .writeOnly: return "Csak írási jog van megadva; az olvasáshoz teljes hozzáférés kell (Rendszerbeállítások › Adatvédelem és biztonság › Naptárak)."
        }
    }
}

struct CalendarInfo: Identifiable, Equatable {
    let id: String
    let title: String
    /// A fiók neve (pl. iCloud, Google, Exchange).
    let account: String
    let colorHex: String?
}

protocol CalendarSource: AnyObject {
    var access: CalendarAccess { get }
    /// Megkéri a teljes olvasási engedélyt (a rendszer egyszer kérdez rá).
    func requestAccess() async -> Bool
    func calendars() -> [CalendarInfo]
    /// A [from, to] tartományba eső események. `calendarIDs == nil`: minden naptár.
    func events(calendarIDs: Set<String>?, from: Date, to: Date) -> [CalendarEventInput]
    /// A naptáradatok megváltozásakor hívja a kezelőt (a hívó késlelteti és összevonja a jelzéseket). A visszaadott érték a leiratkozáshoz kell.
    func observeChanges(_ handler: @escaping () -> Void) -> NSObjectProtocol?
}

/// A tartomány darabolása és az azonosító-képzés: tiszta függvények (tesztelhetők).
enum CalendarRange {
    /// Az EventKit egy lekérdezésben legfeljebb ~4 évet fogad el; egy évnél nem hosszabb darabokra bontunk.
    /// Fordított vagy üres tartományra üres lista. A darabok szomszédosak, a határon az események ismétlődhetnek (azonosító szerint összevonandók).
    static func chunks(from: Date, to: Date, days: Int = 365, maxChunks: Int = 30) -> [(Date, Date)] {
        guard from < to, days > 0 else { return [] }
        var result: [(Date, Date)] = []
        var cur = from
        while cur < to, result.count < maxChunks {
            let next = min(to, DateUtil.addDays(cur, days))
            guard next > cur else { break }   // védelem: a dátumszámítás hibája nem okozhat végtelen ciklust
            result.append((cur, next))
            cur = next
        }
        return result
    }

    /// Az esemény azonosítója az értelmezőnek: az ismétlődő vagy kivételes (leválasztott) példánynál a példány eredeti kezdetével kiegészítve,
    /// így minden példány külön azonosítót kap.
    static func eventID(identifier: String, occurrence: Date?, isRecurringInstance: Bool) -> String {
        guard isRecurringInstance, let o = occurrence else { return identifier }
        return identifier + "|" + String(Int(o.timeIntervalSince1970.rounded()))
    }
}

final class EventKitCalendarSource: CalendarSource {
    private let store = EKEventStore()

    var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .notDetermined
        case .fullAccess: return .granted
        case .writeOnly: return .writeOnly
        case .restricted: return .restricted
        default: return .denied
        }
    }

    func requestAccess() async -> Bool {
        // A menüsori (LSUIElement) alkalmazásnál az engedélykérő ablak csak előtérbe hozott alkalmazásnál jelenik meg.
        await MainActor.run { NSApp.activate(ignoringOtherApps: true) }
        do { return try await store.requestFullAccessToEvents() } catch { return false }
    }

    func calendars() -> [CalendarInfo] {
        guard access == .granted else { return [] }
        store.refreshSourcesIfNecessary()
        return store.calendars(for: .event)
            .filter { $0.type != .birthday }
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, account: $0.source?.title ?? "", colorHex: Self.hex($0.cgColor)) }
            .sorted { ($0.account, $0.title) < ($1.account, $1.title) }
    }

    func events(calendarIDs: Set<String>?, from: Date, to: Date) -> [CalendarEventInput] {
        guard access == .granted else { return [] }
        let all = store.calendars(for: .event)
        let chosen: [EKCalendar]
        if let ids = calendarIDs {
            chosen = all.filter { ids.contains($0.calendarIdentifier) }
            if chosen.isEmpty { return [] }   // nincs kiválasztott naptár (a nil „mind” helyett üres lista)
        } else {
            chosen = all
        }
        var byID: [String: CalendarEventInput] = [:]
        for (a, b) in CalendarRange.chunks(from: from, to: to) {
            let predicate = store.predicateForEvents(withStart: a, end: b, calendars: chosen)
            for e in store.events(matching: predicate) {
                let input = Self.makeInput(e)
                byID[input.id] = input
            }
        }
        return byID.values.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    func observeChanges(_ handler: @escaping () -> Void) -> NSObjectProtocol? {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in handler() }
    }

    /// Egy EventKit-esemény az értelmező bemenetére. Visszautasított vagy törölt állapotot jelöl, de nem szűr.
    static func makeInput(_ e: EKEvent) -> CalendarEventInput {
        let base = e.eventIdentifier ?? e.calendarItemIdentifier
        let id = CalendarRange.eventID(identifier: base, occurrence: e.occurrenceDate ?? e.startDate, isRecurringInstance: e.hasRecurrenceRules || e.isDetached)
        let declined = e.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
        let start = e.startDate ?? Date(timeIntervalSince1970: 0)
        return CalendarEventInput(id: id, title: e.title ?? "", location: e.location ?? "", notes: e.notes ?? "",
                                  start: start, end: e.endDate ?? start, isAllDay: e.isAllDay,
                                  isDeclined: declined, isCancelled: e.status == .canceled)
    }

    private static func hex(_ c: CGColor?) -> String? {
        guard let c = c, let ns = NSColor(cgColor: c)?.usingColorSpace(.sRGB) else { return nil }
        let r = Int((ns.redComponent * 255).rounded()), g = Int((ns.greenComponent * 255).rounded()), b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", min(255, max(0, r)), min(255, max(0, g)), min(255, max(0, b)))
    }
}
