import Foundation
@testable import SitterSubmitter

private final class TestBundle {}

enum TestPaths {
    /// The template bundled with the app (tests run inside the app).
    static let template = Bundle.main.url(forResource: "template", withExtension: "xlsx")!

    // Files from elsewhere in the repository, copied into the test bundle by the build: the simulator
    // isn't necessarily allowed to read the checkout.
    static let november2025Receipt = samplePdfs.first { $0.lastPathComponent.hasSuffix("(5).pdf") }!
    static let december2024Receipt = samplePdfs.first { !$0.lastPathComponent.hasSuffix("(5).pdf") }!
    static let androidPdfParser = Bundle(for: TestBundle.self).url(forResource: "PdfParser", withExtension: "kt")!

    /// docs/「はじめて」を応援する _ ポピンズシッター(5).pdf and docs/「はじめて」を応援する _ ポピンズシッター.pdf
    private static var samplePdfs: [URL] {
        Bundle(for: TestBundle.self).urls(forResourcesWithExtension: "pdf", subdirectory: nil) ?? []
    }
}

func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("SitterSubmitterTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeRepository(in directory: URL) throws -> ReceiptRepository {
    try ReceiptRepository(
        databasePath: directory.appendingPathComponent("receipts.sqlite").path,
        receiptsDirectory: directory.appendingPathComponent("receipts", isDirectory: true)
    )
}

func makeUserDefaults() -> UserDefaults {
    let suiteName = "SitterSubmitterTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

struct StubPdfParser: PdfParsing {
    var handler: @Sendable (Data) throws -> ParsedReceipt

    func parse(_ pdfData: Data) async throws -> ParsedReceipt {
        try handler(pdfData)
    }
}

enum Fixtures {
    static func detail(
        year: Int = 2025,
        month: Int,
        day: Int,
        startTime: String = "09:30",
        endTime: String = "14:00",
        sitterName: String = "高野 あみい",
        childName: String = "杏",
        amount: Int = 11700
    ) -> ReceiptDetailEntity {
        ReceiptDetailEntity(
            receiptId: 0,
            year: year,
            month: month,
            day: day,
            startTime: startTime,
            endTime: endTime,
            sitterName: sitterName,
            childName: childName,
            amount: amount
        )
    }

    static func parsed(_ detail: ReceiptDetailEntity) -> ParsedReceiptDetail {
        ParsedReceiptDetail(
            year: detail.year,
            month: detail.month,
            day: detail.day,
            startTime: detail.startTime,
            endTime: detail.endTime,
            sitterName: detail.sitterName,
            childName: detail.childName,
            amount: detail.amount
        )
    }

    /// The sessions on the hand-filled form in docs/example.jpg (docs/exampe-output-data.csv).
    static let exampleSessions: [ReceiptDetailEntity] = [
        detail(month: 10, day: 1, startTime: "09:30", endTime: "14:00", amount: 11700),
        detail(month: 10, day: 10, startTime: "09:00", endTime: "13:00", amount: 10400),
        detail(month: 10, day: 16, startTime: "09:00", endTime: "14:30", amount: 14300),
        detail(month: 10, day: 24, startTime: "10:00", endTime: "13:00", amount: 7800),
        detail(month: 10, day: 31, startTime: "10:00", endTime: "13:45", amount: 9750),
        detail(month: 11, day: 7, startTime: "09:30", endTime: "15:00", amount: 14300),
        detail(month: 11, day: 12, startTime: "10:00", endTime: "13:00", amount: 7800),
        detail(month: 11, day: 21, startTime: "09:30", endTime: "15:00", amount: 14300),
        detail(month: 11, day: 25, startTime: "10:00", endTime: "15:30", amount: 14300),
        detail(month: 12, day: 5, startTime: "09:30", endTime: "15:30", amount: 15600),
        detail(month: 12, day: 12, startTime: "09:30", endTime: "14:30", amount: 13000),
    ]

    /// Adds a receipt for `details` straight to the repository.
    @discardableResult
    static func addReceipt(
        to repository: ReceiptRepository,
        details: [ReceiptDetailEntity],
        fileName: String = "receipt.pdf"
    ) async throws -> Int64 {
        try await repository.addReceiptWithDetails(
            pdfData: Data("%PDF-1.4 \(fileName)".utf8),
            originalFileName: fileName,
            year: details[0].year,
            month: details[0].month,
            amount: details.reduce(0) { $0 + $1.amount },
            sitterName: details[0].sitterName,
            details: details
        )
    }
}

extension XlsxTemplate.CellValue {
    var cachedResult: XlsxTemplate.FormulaResult? {
        if case .formula(_, let result) = self { result } else { nil }
    }
}
