import Foundation

/// Fills the official submission spreadsheet (ベビーシッター利用内容内訳表) with one child's sessions.
/// Cell-for-cell port of the Android `ReportGenerator`.
struct ReportGenerator: Sendable {
    /// The template's session rows: 16–43, i.e. 28 sessions per form.
    static let dataRows = 16...43

    let templateURL: URL

    init(templateURL: URL) {
        self.templateURL = templateURL
    }

    /// The template bundled with the app (`Resources/template.xlsx`).
    static func bundled() -> ReportGenerator {
        guard let url = Bundle.main.url(forResource: "template", withExtension: "xlsx") else {
            fatalError("template.xlsx is missing from the app bundle")
        }
        return ReportGenerator(templateURL: url)
    }

    func generate(details: [ReceiptDetailEntity], childName: String, outputURL: URL) throws {
        var workbook = try XlsxTemplate(data: Data(contentsOf: templateURL))

        // Sort details by date
        let sortedDetails = details.stableSorted { l, r in
            if (l.year, l.month, l.day) != (r.year, r.month, r.day) {
                return (l.year, l.month, l.day) < (r.year, r.month, r.day)
            }
            return l.startTime.precedesInKotlinOrder(r.startTime)
        }

        if let first = sortedDetails.first {
            // Header year and month (row 12). Unlike Android's `createCell`, this keeps the template's styling.
            try workbook.setNumber(Double(first.year), at: "C12")
            try workbook.setNumber(Double(first.month), at: "G12")
            // Child name (row 4).
            try workbook.setString(childName, at: "F4")
        }

        // Fill the session rows. Anything past the template's last row is dropped, as on Android
        // (which additionally overwrote the totals' labels below the table).
        let rows = Array(sortedDetails.prefix(Self.dataRows.count))
        for (row, detail) in zip(Self.dataRows, rows) {
            try workbook.setString("\(detail.month)月", at: "B\(row)")
            try workbook.setString("\(detail.day)日", at: "D\(row)")
            try workbook.setString(detail.startTime, at: "E\(row)")
            try workbook.setString(detail.endTime, at: "F\(row)")
            try workbook.setNumber(Double(detail.amount), at: "J\(row)") // Fee
            try workbook.setNumber(0, at: "K\(row)") // Option
            try workbook.setNumber(0, at: "L\(row)") // Discount
        }

        // Set column widths so the data is visible.
        try workbook.setColumnWidth(6, forColumn: "B") // Month
        try workbook.setColumnWidth(6, forColumn: "D") // Day
        try workbook.setColumnWidth(10, forColumn: "E") // Start time
        try workbook.setColumnWidth(10, forColumn: "F") // End time

        try Self.storeCalculatedResults(in: &workbook, rows: rows)

        try workbook.makeData().write(to: outputURL, options: .atomic)
    }

    /// QuickLook, which the app uses to open the result, shows the formula results cached in the file instead of
    /// recalculating them, and the template's cached results are all 0. So compute the template's automatic
    /// columns the way Excel would, and also ask Excel to recalculate on open.
    private static func storeCalculatedResults(in workbook: inout XlsxTemplate, rows: [ReceiptDetailEntity]) throws {
        typealias Result = XlsxTemplate.FormulaResult
        var totalSeconds: Int? = 0 // N45 = SUM(利用時間) = SUM(G16:G43)
        var totalClaim: Double? = 0 // N46 = SUM(交付申請額) = SUM(P16:P43)

        for (offset, row) in dataRows.enumerated() {
            let detail = rows.indices.contains(offset) ? rows[offset] : nil

            // G = F-E: Excel coerces the "HH:MM" text to fractions of a day; empty cells count as 0.
            let seconds: Int? = if let detail {
                excelTimeSeconds(detail.endTime).flatMap { end in excelTimeSeconds(detail.startTime).map { end - $0 } }
            } else {
                0
            }
            // N = J+K-L (fee + option - discount).
            let actualPaid = Double(detail?.amount ?? 0)
            // O = IF(I="○", H*3500, H*2500) with H = G*24. The app never marks night use (column I), as on Android.
            let subsidyStandard = seconds.map { Double($0) / 3600 * 2500 }
            // P = MIN(N:O).
            let claim = subsidyStandard.map { min(actualPaid, $0) }

            try workbook.setFormulaResult(seconds.map { .number(Double($0) / 86400) } ?? .error("#VALUE!"), at: "G\(row)")
            try workbook.setFormulaResult(seconds.map { .number(Double($0) / 3600) } ?? .error("#VALUE!"), at: "H\(row)")
            try workbook.setFormulaResult(.number(actualPaid), at: "N\(row)")
            try workbook.setFormulaResult(subsidyStandard.map(Result.number) ?? .error("#VALUE!"), at: "O\(row)")
            try workbook.setFormulaResult(claim.map(Result.number) ?? .error("#VALUE!"), at: "P\(row)")

            totalSeconds = totalSeconds.flatMap { total in seconds.map { total + $0 } }
            totalClaim = totalClaim.flatMap { total in claim.map { total + $0 } }
        }

        try workbook.setFormulaResult(totalSeconds.map(totalTimeResult) ?? .error("#VALUE!"), at: "N45")
        try workbook.setFormulaResult(totalClaim.map(Result.number) ?? .error("#VALUE!"), at: "N46")
        try workbook.forceFullCalculationOnLoad()
    }

    /// The total is formatted `[h]"時間"mm"分"`, and QuickLook ignores the `[h]` (elapsed hours) part, showing 51:15 as
    /// "3時間15分". So cache what Excel would display instead of the number; apps that calculate replace it on open.
    private static func totalTimeResult(seconds: Int) -> XlsxTemplate.FormulaResult {
        guard seconds >= 0 else { return .number(Double(seconds) / 86400) }
        let minutes = seconds / 60
        return .text("\(minutes / 60)時間" + String(format: "%02d", minutes % 60) + "分")
    }

    /// Seconds since midnight for "H:MM" or "H:MM:SS" text, which is how Excel reads time strings in arithmetic.
    /// Anything else makes Excel's formula fail with #VALUE!, signalled here by nil.
    static func excelTimeSeconds(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              parts.dropFirst().allSatisfy({ $0.count <= 2 }),
              let hours = Int(parts[0]), let minutes = Int(parts[1]), minutes < 60
        else { return nil }
        let seconds = parts.count == 3 ? Int(parts[2]) ?? 60 : 0
        guard seconds < 60 else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }
}
