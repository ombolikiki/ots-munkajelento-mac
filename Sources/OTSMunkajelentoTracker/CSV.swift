import Foundation

/// Az adatfájl formátuma: pontosvesszővel tagolt, UTF-8 (BOM-mal) CSV, amit az Excel, a Numbers és a LibreOffice is megnyit.
/// Szerkesztés után az app a következő megnyitáskor újra beolvassa.
enum CSV {
    static let columns = [
        "Azonosító", "Dátum", "Kezdés", "Vége", "Időtartam (mp)", "Időtartam (óó:pp)",
        "Indulás", "Munkahely", "Érkezés",
        "Típus kód", "Típus", "Egység", "Mennyiség", "Tevékenység", "Forrás",
        "Cím", "Naptár azonosító", "Indulás cím", "Érkezés cím", "Munkahely helye"
    ]

    struct DecodeResult {
        var entries: [Entry]
        var warnings: [String]
    }

    struct CSVError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: Írás

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static func quote(_ s: String) -> String {
        if s.contains(";") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    static func encode(_ entries: [Entry]) -> Data {
        var lines = [columns.map(quote).joined(separator: ";")]
        for e in entries {
            let fields: [String] = [
                e.id.uuidString,
                e.date,
                e.start.map { timeFormatter.string(from: $0) } ?? "",
                e.end.map { timeFormatter.string(from: $0) } ?? "",
                String(e.durationSeconds),
                e.unit == Unit.hours.rawValue ? Fmt.hm(e.durationSeconds) : "",
                e.departure ?? "",
                e.workplace,
                e.arrival ?? "",
                e.type,
                e.typeLabel,
                e.unit,
                e.quantity.map(String.init) ?? "",
                e.activity,
                e.source,
                e.address ?? "",
                e.calendarID ?? "",
                e.departureAddress ?? "",
                e.arrivalAddress ?? "",
                e.workplaceIsDeparture ? "indulás" : ""
            ]
            lines.append(fields.map(quote).joined(separator: ";"))
        }
        let text = lines.joined(separator: "\r\n") + "\r\n"
        return Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
    }

    // MARK: Olvasás

    static func decode(_ data: Data) throws -> DecodeResult {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        guard let text = String(data: bytes, encoding: .utf8) else {
            throw CSVError(message: "A fájl nem UTF-8 kódolású.")
        }
        let delimiter = detectDelimiter(text)
        var records = parseRecords(text, delimiter: delimiter)
        guard !records.isEmpty else { return DecodeResult(entries: [], warnings: []) }

        let header = records.removeFirst().map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping.lowercased()
        }
        func idx(_ name: String) -> Int? { header.firstIndex(of: name.precomposedStringWithCanonicalMapping.lowercased()) }
        guard let iDate = idx("Dátum") else {
            throw CSVError(message: "Hiányzik a „Dátum” oszlop az adatfájlból.")
        }
        let iType = idx("Típus kód"), iTypeLabel = idx("Típus")
        guard iType != nil || iTypeLabel != nil else {
            throw CSVError(message: "Hiányzik a „Típus kód” (vagy „Típus”) oszlop az adatfájlból.")
        }
        let iId = idx("Azonosító"), iStart = idx("Kezdés"), iEnd = idx("Vége"), iSecs = idx("Időtartam (mp)")
        let iUnit = idx("Egység"), iDep = idx("Indulás"), iArr = idx("Érkezés"), iWork = idx("Munkahely"), iQty = idx("Mennyiség"), iAct = idx("Tevékenység"), iSrc = idx("Forrás")
        let iAddr = idx("Cím"), iCalID = idx("Naptár azonosító"), iDepAddr = idx("Indulás cím"), iArrAddr = idx("Érkezés cím"), iWpl = idx("Munkahely helye")

        var entries: [Entry] = []
        var warnings: [String] = []
        let cal = Calendar.current

        for (n, row) in records.enumerated() {
            let line = n + 2
            func cell(_ i: Int?) -> String {
                guard let i = i, i < row.count else { return "" }
                return row[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }

            guard let dateKey = parseDate(cell(iDate)) else {
                warnings.append("\(line). sor: hibás dátum („\(cell(iDate))”)")
                continue
            }
            let codeText = cell(iType)
            let labelText = cell(iTypeLabel)
            var type = ActivityType.lookup(code: codeText) ?? ActivityType.lookup(label: labelText.isEmpty ? codeText : labelText)
            if type == nil {
                // Ismeretlen (pl. már törölt egyéni) kategória: az adat nem veszhet el, ezért egyéni típusként olvassuk be.
                let name = labelText.isEmpty ? codeText : labelText
                guard !name.isEmpty else {
                    warnings.append("\(line). sor: nincs megadva típus")
                    continue
                }
                let unitRaw = cell(iUnit)
                let unit: Unit = Unit(rawValue: unitRaw) ?? .hours
                let code = codeText.isEmpty ? ActivityType.customPrefix + name.uppercased() : codeText.uppercased()
                type = ActivityType(code: code, group: ActivityType.customGroup, shortLabel: name, label: name, unit: unit, isCustom: true)
            }
            let t = type!

            let day = Fmt.dayFormatter.date(from: dateKey) ?? Date()
            var start: Date?, end: Date?
            if let st = parseTime(cell(iStart)), let en = parseTime(cell(iEnd)) {
                start = cal.date(bySettingHour: st.h, minute: st.m, second: st.s, of: day)
                end = cal.date(bySettingHour: en.h, minute: en.m, second: en.s, of: day)
                if let s = start, let e = end, e < s { end = cal.date(byAdding: .day, value: 1, to: e) }
            }
            var duration = 0
            if let s = start, let e = end {
                duration = max(0, Int(e.timeIntervalSince(s).rounded()))
            } else if let d = number(cell(iSecs)) {
                duration = max(0, d)
            }
            if t.unit != .hours && t.unit != .occasions && t.unit != .people { duration = 0 }

            var quantity: Int?
            if t.hasQuantity {
                quantity = min(999, max(1, number(cell(iQty)) ?? 1))
            }
            let src = cell(iSrc)
            entries.append(Entry(
                id: UUID(uuidString: cell(iId)) ?? UUID(),
                date: dateKey,
                start: start, end: end,
                durationSeconds: duration,
                workplace: cell(iWork),
                type: t.rawValue,
                typeLabel: t.label,
                unit: t.unit.rawValue,
                quantity: quantity,
                activity: cell(iAct),
                source: src.isEmpty ? "manual" : src,
                departure: cell(iDep).isEmpty ? nil : cell(iDep),
                arrival: cell(iArr).isEmpty ? nil : cell(iArr),
                address: cell(iAddr).isEmpty ? nil : cell(iAddr),
                calendarID: cell(iCalID).isEmpty ? nil : cell(iCalID),
                departureAddress: cell(iDepAddr).isEmpty ? nil : cell(iDepAddr),
                arrivalAddress: cell(iArrAddr).isEmpty ? nil : cell(iArrAddr),
                workplaceIsDeparture: cell(iWpl).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) == "indulas"
            ))
        }
        return DecodeResult(entries: entries, warnings: warnings)
    }

    /// Szöveg -> egész szám; a hibás vagy extrém érték (pl. „inf”, „1e99”) nem okozhat összeomlást.
    static func number(_ s: String) -> Int? {
        guard let d = Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")),
              d.isFinite, abs(d) < 1_000_000_000 else { return nil }
        return Int(d.rounded())
    }

    static func detectDelimiter(_ text: String) -> Character {
        let firstLine = text.prefix { $0 != "\n" && $0 != "\r" }
        let counts: [(Character, Int)] = [";", ",", "\t"].map { c in (c, firstLine.filter { $0 == c }.count) }
        let best = counts.max { $0.1 < $1.1 }
        return (best?.1 ?? 0) > 0 ? best!.0 : ";"
    }

    static func parseRecords(_ text: String, delimiter: Character) -> [[String]] {
        var records: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text)
        chars.append("\n")  // záró sortörés biztosítása
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { inQuotes = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == delimiter {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(field); field = ""
                if !(row.count == 1 && row[0].isEmpty) { records.append(row) }
                row = []
            } else {
                field.append(c)
            }
            i += 1
        }
        return records
    }

    /// Elfogadja: 2026-10-03, 2026. 10. 03., 2026.10.03, 03/10/2026 (táblázatkezelő átírhatja).
    static func parseDate(_ s: String) -> String? {
        let nums = s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard nums.count >= 3 else { return nil }
        var y = 0, m = 0, d = 0
        if nums[0] > 31 { (y, m, d) = (nums[0], nums[1], nums[2]) }
        else if nums[2] > 31 { (d, m, y) = (nums[0], nums[1], nums[2]) }
        else { return nil }
        guard (1...12).contains(m), (1...31).contains(d), (1900...2200).contains(y) else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func parseTime(_ s: String) -> (h: Int, m: Int, s: Int)? {
        let nums = s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard nums.count >= 2, (0...23).contains(nums[0]), (0...59).contains(nums[1]) else { return nil }
        let sec = nums.count >= 3 ? nums[2] : 0
        guard (0...59).contains(sec) else { return nil }
        return (nums[0], nums[1], sec)
    }
}
