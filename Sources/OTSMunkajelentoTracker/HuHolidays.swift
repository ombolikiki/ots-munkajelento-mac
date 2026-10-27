import Foundation

/// A magyar munkaszüneti napok (kiszámolhatók: a rögzített napok és a húsvétból számolt mozgó ünnepek). A rendelettel változó
/// pihenőnapok és áthelyezett munkanapok nincsenek benne: azokat a felhasználó a Pihenőnap típussal jelöli.
enum HuHolidays {
    struct Holiday: Equatable {
        let date: Date
        let name: String
    }

    /// A húsvétvasárnap hónapja és napja a Gergely-naptár szerint (névtelen / Meeus–Jones–Butcher algoritmus).
    static func easterSunday(year: Int) -> (month: Int, day: Int) {
        let a = year % 19
        let b = year / 100, c = year % 100
        let d = b / 4, e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return (month, day)
    }

    /// Az év munkaszüneti napjai időrendben (hivatalos nevekkel). Érvénytelen évre üres lista.
    static func holidays(year: Int) -> [Holiday] {
        var list: [Holiday] = []
        func add(_ month: Int, _ day: Int, _ name: String) {
            if let d = DateUtil.date(year: year, month: month, day: day) { list.append(Holiday(date: d, name: name)) }
        }
        add(1, 1, "Újév")
        add(3, 15, "Március 15. (nemzeti ünnep)")
        let easter = easterSunday(year: year)
        if let e = DateUtil.date(year: year, month: easter.month, day: easter.day) {
            list.append(Holiday(date: DateUtil.addDays(e, -2), name: "Nagypéntek"))
            list.append(Holiday(date: e, name: "Húsvétvasárnap"))
            list.append(Holiday(date: DateUtil.addDays(e, 1), name: "Húsvéthétfő"))
            list.append(Holiday(date: DateUtil.addDays(e, 49), name: "Pünkösdvasárnap"))
            list.append(Holiday(date: DateUtil.addDays(e, 50), name: "Pünkösdhétfő"))
        }
        add(5, 1, "Május 1. (a munka ünnepe)")
        add(8, 20, "Augusztus 20. (az államalapítás ünnepe)")
        add(10, 23, "Október 23. (nemzeti ünnep)")
        add(11, 1, "Mindenszentek")
        add(12, 25, "Karácsony")
        add(12, 26, "Karácsony másnapja")
        return list.sorted { $0.date < $1.date }
    }

    /// Az adott nap ünnepének neve (nil, ha nem munkaszüneti nap).
    static func name(on day: Date) -> String? {
        let year = DateUtil.components(day).year
        return holidays(year: year).first { DateUtil.gregorian.isDate($0.date, inSameDayAs: day) }?.name
    }
}
