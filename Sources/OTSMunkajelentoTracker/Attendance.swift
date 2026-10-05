import Foundation

/// Egy gyülekezet létszámai egy esedékes szombaton: Szombatiskola és Istentisztelet, mindegyikben három szám.
struct AttendanceCounts: Equatable {
    var children = 0     // gyermek
    var adults = 0       // felnőtt adventista
    var guests = 0       // felnőtt vendég
}

struct AttendanceReport: Identifiable, Equatable {
    var date: String            // YYYY-MM-DD
    var congregation: String
    var sabbathSchool = AttendanceCounts()
    var worship = AttendanceCounts()
    var id: String { date + "|" + congregation }
}

/// A `letszamjelentesek.csv` formátuma (pontosvesszővel tagolt, UTF-8 BOM, táblázatkezelőben szerkeszthető).
enum AttendanceCSV {
    static let columns = [
        "Dátum", "Gyülekezet",
        "Szombatiskola gyermek", "Szombatiskola felnőtt adventista", "Szombatiskola felnőtt vendég",
        "Istentisztelet gyermek", "Istentisztelet felnőtt adventista", "Istentisztelet felnőtt vendég"
    ]

    static func encode(_ reports: [AttendanceReport]) -> Data {
        var lines = [columns.map(CSV.quote).joined(separator: ";")]
        for r in reports.sorted(by: { ($0.date, $0.congregation) < ($1.date, $1.congregation) }) {
            let f: [String] = [
                r.date, r.congregation,
                String(r.sabbathSchool.children), String(r.sabbathSchool.adults), String(r.sabbathSchool.guests),
                String(r.worship.children), String(r.worship.adults), String(r.worship.guests)
            ]
            lines.append(f.map(CSV.quote).joined(separator: ";"))
        }
        let text = lines.joined(separator: "\r\n") + "\r\n"
        return Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
    }

    struct Result {
        var reports: [AttendanceReport]
        var warnings: [String]
    }

    static func decode(_ data: Data) throws -> Result {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        guard let text = String(data: bytes, encoding: .utf8) else {
            throw CSV.CSVError(message: "A létszámjelentő fájl nem UTF-8 kódolású.")
        }
        var records = CSV.parseRecords(text, delimiter: CSV.detectDelimiter(text))
        guard !records.isEmpty else { return Result(reports: [], warnings: []) }
        let header = records.removeFirst().map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping.lowercased()
        }
        func idx(_ name: String) -> Int? { header.firstIndex(of: name.precomposedStringWithCanonicalMapping.lowercased()) }
        guard let iDate = idx("Dátum"), let iCong = idx("Gyülekezet") else {
            throw CSV.CSVError(message: "A létszámjelentő fájlból hiányzik a „Dátum” vagy a „Gyülekezet” oszlop.")
        }
        let cols = columns.dropFirst(2).map { idx($0) }
        var reports: [AttendanceReport] = []
        var warnings: [String] = []
        for (n, row) in records.enumerated() {
            let line = n + 2
            func cell(_ i: Int?) -> String {
                guard let i = i, i < row.count else { return "" }
                return row[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
            guard let date = CSV.parseDate(cell(iDate)) else {
                warnings.append("\(line). sor: hibás dátum („\(cell(iDate))”)"); continue
            }
            let cong = cell(iCong)
            guard !cong.isEmpty else { warnings.append("\(line). sor: nincs gyülekezet"); continue }
            func num(_ k: Int) -> Int { min(99_999, max(0, CSV.number(cell(cols[k])) ?? 0)) }
            var r = AttendanceReport(date: date, congregation: cong)
            r.sabbathSchool = AttendanceCounts(children: num(0), adults: num(1), guests: num(2))
            r.worship = AttendanceCounts(children: num(3), adults: num(4), guests: num(5))
            reports.removeAll { $0.id == r.id }   // ugyanarra a dátumra és gyülekezetre csak egy jelentés
            reports.append(r)
        }
        return Result(reports: reports, warnings: warnings)
    }
}
