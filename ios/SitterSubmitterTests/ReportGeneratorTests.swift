import Foundation
import Testing
@testable import SitterSubmitter

struct ReportGeneratorTests {
    private let generator = ReportGenerator(templateURL: TestPaths.template)

    private func generate(_ details: [ReceiptDetailEntity], childName: String = "ベイリー 杏") throws -> Data {
        let output = try makeTemporaryDirectory().appendingPathComponent("submission.xlsx")
        try generator.generate(details: details, childName: childName, outputURL: output)
        return try Data(contentsOf: output)
    }

    private func generateWorkbook(_ details: [ReceiptDetailEntity]) throws -> XlsxTemplate {
        try XlsxTemplate(data: generate(details))
    }

    @Test func fillsInTheChildNameAndPeriod() throws {
        let workbook = try generateWorkbook(Fixtures.exampleSessions.reversed())

        #expect(workbook.value(at: "F4") == .string("ベイリー 杏"))
        #expect(workbook.value(at: "C12") == .number(2025))
        #expect(workbook.value(at: "G12") == .number(10)) // Month of the earliest session
    }

    @Test func fillsOneRowPerSessionInDateOrder() throws {
        let workbook = try generateWorkbook(Fixtures.exampleSessions.reversed())

        for (row, session) in zip(16..., Fixtures.exampleSessions) {
            #expect(workbook.value(at: "B\(row)") == .string("\(session.month)月"))
            #expect(workbook.value(at: "D\(row)") == .string("\(session.day)日"))
            #expect(workbook.value(at: "E\(row)") == .string(session.startTime))
            #expect(workbook.value(at: "F\(row)") == .string(session.endTime))
            #expect(workbook.value(at: "J\(row)") == .number(Double(session.amount)))
            #expect(workbook.value(at: "K\(row)") == .number(0))
            #expect(workbook.value(at: "L\(row)") == .number(0))
        }
        // The rest of the table is left as in the template.
        #expect(workbook.value(at: "B27") == .string("月"))
        #expect(workbook.value(at: "D27") == .string("日"))
        #expect(workbook.value(at: "E27") == .blank)
        #expect(workbook.value(at: "J27") == .blank)
    }

    @Test func sortsSessionsOnTheSameDayByStartTime() throws {
        let workbook = try generateWorkbook([
            Fixtures.detail(month: 11, day: 7, startTime: "18:00", endTime: "21:00"),
            Fixtures.detail(month: 11, day: 7, startTime: "07:30", endTime: "09:00"),
        ])

        #expect(workbook.value(at: "E16") == .string("07:30"))
        #expect(workbook.value(at: "E17") == .string("18:00"))
    }

    @Test func calculatesTheAutomaticColumnsForPreviewing() throws {
        let workbook = try generateWorkbook(Fixtures.exampleSessions)

        // 9:30–14:00 for ¥11,700: 4.5 hours, capped at 4.5 × ¥2,500.
        #expect(workbook.value(at: "G16") == .formula("F16-E16", cachedResult: .number(0.1875)))
        #expect(workbook.value(at: "H16") == .formula("G16*24", cachedResult: .number(4.5)))
        #expect(workbook.value(at: "N16") == .formula("J16+K16-L16", cachedResult: .number(11700)))
        #expect(workbook.value(at: "O16") == .formula(#"IF(I16="○",H16*3500,H16*2500)"#, cachedResult: .number(11250)))
        #expect(workbook.value(at: "P16") == .formula("MIN(N16:O16)", cachedResult: .number(11250)))
        // Rows using shared formulas: 10:00–13:45 for ¥9,750.
        #expect(workbook.value(at: "H20")?.cachedResult == .number(3.75))
        #expect(workbook.value(at: "P20")?.cachedResult == .number(9375))
        // Empty rows.
        #expect(workbook.value(at: "G27")?.cachedResult == .number(0))
        #expect(workbook.value(at: "P43")?.cachedResult == .number(0))
        // The totals on the hand-filled example: 51時間15分 and ¥128,125.
        #expect(workbook.value(at: "N45") == .formula("SUM(利用時間)", cachedResult: .text("51時間15分")))
        #expect(workbook.value(at: "N46") == .formula("SUM(交付申請額)", cachedResult: .number(128_125)))
        // Excel recalculates anyway.
        #expect(workbook.isFullCalculationOnLoadEnabled)
    }

    @Test func unreadableTimesBecomeExcelErrors() throws {
        let workbook = try generateWorkbook([Fixtures.detail(month: 11, day: 7, startTime: "morning", amount: 5000)])

        #expect(workbook.value(at: "G16")?.cachedResult == .error("#VALUE!"))
        #expect(workbook.value(at: "N16")?.cachedResult == .number(5000))
        #expect(workbook.value(at: "P16")?.cachedResult == .error("#VALUE!"))
        #expect(workbook.value(at: "N45")?.cachedResult == .error("#VALUE!"))
        #expect(workbook.value(at: "N46")?.cachedResult == .error("#VALUE!"))
    }

    @Test func dropsSessionsThatDoNotFitWithoutTouchingTheTotals() throws {
        let sessions = (1...30).map { Fixtures.detail(month: 10, day: $0, amount: 1000) }

        let workbook = try generateWorkbook(sessions)

        #expect(workbook.value(at: "D43") == .string("28日")) // The 28th session, on the last row
        #expect(workbook.value(at: "K45") == .string("当期利用時間合計"))
        #expect(workbook.value(at: "L45") == .blank)
        #expect(workbook.value(at: "K46") == .string("当期交付申請額合計"))
        #expect(workbook.value(at: "N46")?.cachedResult == .number(28 * 1000))
    }

    @Test func keepsTheTemplateFormatting() throws {
        let workbook = try generateWorkbook(Fixtures.exampleSessions)
        let template = try XlsxTemplate(data: Data(contentsOf: TestPaths.template))

        for reference in ["F4", "C12", "G12", "B16", "D16", "E16", "F16", "G16", "J16", "K16", "L16", "N45", "N46"] {
            #expect(workbook.styleIndex(at: reference) == template.styleIndex(at: reference), "\(reference)")
        }
        #expect(workbook.columnWidth(forColumn: "B") == 6)
        #expect(workbook.columnWidth(forColumn: "D") == 6)
        #expect(workbook.columnWidth(forColumn: "E") == 10)
        #expect(workbook.columnWidth(forColumn: "F") == 10)
        #expect(workbook.columnWidth(forColumn: "C") == template.columnWidth(forColumn: "C"))
        #expect(workbook.columnWidth(forColumn: "G") == template.columnWidth(forColumn: "G"))
    }

    @Test func onlyRewritesTheSheetItsStringsAndTheWorkbook() throws {
        let output = try ZipArchive(data: generate(Fixtures.exampleSessions))
        let template = try ZipArchive(data: Data(contentsOf: TestPaths.template))
        let edited: Set = [XlsxTemplate.workbookPath, XlsxTemplate.worksheetPath, XlsxTemplate.sharedStringsPath]

        #expect(output.entries.map(\.path) == template.entries.map(\.path))
        for entry in template.entries where !edited.contains(entry.path) {
            #expect(output[entry.path] == entry.data, "\(entry.path)")
        }
    }

    @Test(arguments: [
        ("09:30", 34200), ("9:05", 32700), ("9:5", 32700), ("14:00:30", 50430), (" 10:00 ", 36000), ("24:00", 86400),
    ])
    func readsTimesLikeExcel(text: String, seconds: Int) {
        #expect(ReportGenerator.excelTimeSeconds(text) == seconds)
    }

    @Test(arguments: ["", "9", "9:", "9:5:", "9:60", "9:00:60", "ten:00", "９:３０", "-1:00", "9:00 AM"])
    func rejectsTimesExcelCannotRead(text: String) {
        #expect(ReportGenerator.excelTimeSeconds(text) == nil)
    }
}

struct XlsxTemplateTests {
    private func template() throws -> XlsxTemplate {
        try XlsxTemplate(data: Data(contentsOf: TestPaths.template))
    }

    @Test func readsTheTemplate() throws {
        let workbook = try template()

        #expect(workbook.value(at: "A4") == .string("児童氏名")) // Without the furigana hint
        #expect(workbook.value(at: "F4") == .blank)
        #expect(workbook.value(at: "G16") == .formula("F16-E16", cachedResult: .number(0)))
        #expect(workbook.value(at: "Z99") == nil)
        #expect(!workbook.isFullCalculationOnLoadEnabled)
    }

    @Test func sharesRepeatedStringsAndKeepsTheCountsRight() throws {
        var workbook = try template()
        try workbook.setString("10月", at: "B16") // Replaces a "月" label
        try workbook.setString("10月", at: "B17")
        try workbook.setString("09:30", at: "E16") // A new string cell

        let data = try workbook.makeData()
        let sharedStrings = String(decoding: try #require(ZipArchive(data: data)[XlsxTemplate.sharedStringsPath]), as: UTF8.self)

        #expect(sharedStrings.contains(#"count="86" uniqueCount="33""#)) // Template: 85 references, 31 strings
        let reread = try XlsxTemplate(data: data)
        #expect(reread.value(at: "B17") == .string("10月"))
        #expect(reread.value(at: "E16") == .string("09:30"))
    }

    @Test func escapesText() throws {
        var workbook = try template()
        let name = " <Anne & \"Bo\"> \u{1}\r\n杏 "
        try workbook.setString(name, at: "F4")

        let reread = try XlsxTemplate(data: workbook.makeData())

        #expect(reread.value(at: "F4") == .string(name))
    }

    @Test func splitsColumnRangesToSetOneWidth() throws {
        var workbook = try template()
        try workbook.setColumnWidth(12.5, forColumn: "H") // The template styles G:H as one range

        let reread = try XlsxTemplate(data: workbook.makeData())

        #expect(reread.columnWidth(forColumn: "G") == 9.1640625)
        #expect(reread.columnWidth(forColumn: "H") == 12.5)
        #expect(reread.columnWidth(forColumn: "I") == 7)
    }

    @Test func refusesCellsTheTemplateDoesNotHave() throws {
        var workbook = try template()

        #expect(throws: TemplateError.missingCell("Z99")) {
            try workbook.setString("x", at: "Z99")
        }
        #expect(throws: TemplateError.notAFormula("B16")) {
            try workbook.setFormulaResult(.number(1), at: "B16")
        }
    }
}
