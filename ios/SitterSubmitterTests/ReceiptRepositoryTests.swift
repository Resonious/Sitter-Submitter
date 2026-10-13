import Foundation
import Testing
@testable import SitterSubmitter

struct ReceiptRepositoryTests {
    @Test func storesTheOriginalPdfAndTheParsedSessions() async throws {
        let repository = try makeRepository(in: makeTemporaryDirectory())
        let pdf = Data("%PDF-1.4 November".utf8)

        let id = try await repository.addReceiptWithDetails(
            pdfData: pdf,
            originalFileName: "「はじめて」を応援する _ ポピンズシッター(5).pdf",
            year: 2025,
            month: 11,
            amount: 22100,
            sitterName: "高野 あみい",
            details: [
                Fixtures.detail(month: 11, day: 7, amount: 14300),
                Fixtures.detail(month: 11, day: 12, sitterName: "早川明日香", amount: 7800),
            ]
        )

        let receipts = try await repository.getAllReceipts()
        let stored = try #require(receipts.first)
        #expect(receipts.count == 1)
        #expect(stored.receipt.id == id)
        #expect(stored.receipt.year == 2025)
        #expect(stored.receipt.month == 11)
        #expect(stored.receipt.day == 1)
        #expect(stored.receipt.amount == 22100)
        #expect(stored.receipt.sitterName == "高野 あみい")
        #expect(stored.receipt.originalFileName == "「はじめて」を応援する _ ポピンズシッター(5).pdf")
        #expect(stored.details.map(\.receiptId) == [id, id])
        #expect(stored.details.map(\.day) == [7, 12])
        #expect(stored.details.map(\.sitterName) == ["高野 あみい", "早川明日香"])
        #expect(try Data(contentsOf: repository.fileURL(for: stored.receipt)) == pdf)
    }

    @Test func listsTheNewestMonthsFirst() async throws {
        let repository = try makeRepository(in: makeTemporaryDirectory())
        let october = try await Fixtures.addReceipt(to: repository, details: [Fixtures.detail(month: 10, day: 1)])
        let december2024 = try await Fixtures.addReceipt(to: repository, details: [Fixtures.detail(year: 2024, month: 12, day: 6)])
        let november = try await Fixtures.addReceipt(to: repository, details: [Fixtures.detail(month: 11, day: 7)])
        let october2 = try await Fixtures.addReceipt(to: repository, details: [Fixtures.detail(month: 10, day: 24)])

        let ids = try await repository.getAllReceipts().map(\.receipt.id)

        #expect(ids == [november, october, october2, december2024])
    }

    @Test func returnsTheSessionsOfOneReceipt() async throws {
        let repository = try makeRepository(in: makeTemporaryDirectory())
        try await Fixtures.addReceipt(to: repository, details: [Fixtures.detail(month: 10, day: 1)])
        let november = try await Fixtures.addReceipt(
            to: repository,
            details: [Fixtures.detail(month: 11, day: 7), Fixtures.detail(month: 11, day: 12)]
        )

        let details = try await repository.getDetailsForReceipt(november)

        #expect(details.map(\.day) == [7, 12])
        #expect(details.allSatisfy { $0.receiptId == november })
    }

    @Test func deletesReceiptsWithTheirSessionsAndPdfs() async throws {
        let repository = try makeRepository(in: makeTemporaryDirectory())
        let kept = try await Fixtures.addReceipt(to: repository, details: [Fixtures.detail(month: 10, day: 1)])
        let deleted = try await Fixtures.addReceipt(to: repository, details: [Fixtures.detail(month: 11, day: 7)])
        let deletedFile = repository.fileURL(for: try #require(await repository.getReceiptsByIds([deleted]).first))
        let keptFile = repository.fileURL(for: try #require(await repository.getReceiptsByIds([kept]).first))

        try await repository.deleteReceiptsByIds([deleted])

        #expect(try await repository.getAllReceipts().map(\.receipt.id) == [kept])
        #expect(try await repository.getDetailsForReceipt(deleted).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: deletedFile.path))
        #expect(FileManager.default.fileExists(atPath: keptFile.path))
    }

    @Test func keepsDataBetweenLaunches() async throws {
        let directory = try makeTemporaryDirectory()
        let id = try await Fixtures.addReceipt(to: makeRepository(in: directory), details: [Fixtures.detail(month: 11, day: 7)])

        let reopened = try makeRepository(in: directory)

        #expect(try await reopened.getAllReceipts().map(\.receipt.id) == [id])
        #expect(try await reopened.getDetailsForReceipt(id).count == 1)
    }
}
