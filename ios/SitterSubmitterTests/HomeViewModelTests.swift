import Foundation
import Testing
@testable import SitterSubmitter

@MainActor
struct HomeViewModelTests {
    private let directory: URL
    private let repository: ReceiptRepository
    private let userDefaults = makeUserDefaults()

    init() throws {
        directory = try makeTemporaryDirectory()
        repository = try makeRepository(in: directory)
    }

    private func makeViewModel(parse: @escaping @Sendable (Data) throws -> ParsedReceipt = { _ in
        throw PdfParserError.noEntries
    }) -> HomeViewModel {
        HomeViewModel(receiptRepository: repository, pdfParser: StubPdfParser(handler: parse), userDefaults: userDefaults)
    }

    private func makePdf(named name: String, contents: String = "%PDF-1.4") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    @Test func groupsReceiptsByYearAndMonthNewestFirst() async throws {
        let october = try await Fixtures.addReceipt(to: repository, details: [Fixtures.detail(month: 10, day: 1)])
        let november = try await Fixtures.addReceipt(
            to: repository,
            details: [
                Fixtures.detail(month: 11, day: 7, sitterName: "高野 あみい", amount: 14300),
                Fixtures.detail(month: 11, day: 12, sitterName: "早川明日香", amount: 7800),
                Fixtures.detail(month: 11, day: 21, sitterName: "高野 あみい", amount: 14300),
            ],
            fileName: "november.pdf"
        )
        let december2024 = try await Fixtures.addReceipt(
            to: repository,
            details: [Fixtures.detail(year: 2024, month: 12, day: 6, childName: "")]
        )
        let viewModel = makeViewModel()

        await viewModel.load()

        #expect(viewModel.years.map(\.year) == [2025, 2024])
        #expect(viewModel.years[0].months.map(\.month) == [11, 10])
        #expect(viewModel.years[0].months.map { $0.receipts.map(\.id) } == [[november], [october]])
        #expect(viewModel.years[1].months.map { $0.receipts.map(\.id) } == [[december2024]])
        #expect(viewModel.years[0].months[0].receipts[0] == ReceiptDisplayItem(
            id: november,
            amount: 36400,
            sitterNames: "高野 あみい、早川明日香",
            childNames: "杏",
            originalFileName: "november.pdf"
        ))
        #expect(viewModel.years[1].months[0].receipts[0].childNames == "")
    }

    @Test func identifiesTheSameMonthInDifferentYearsSeparately() async throws {
        try await Fixtures.addReceipt(to: repository, details: [Fixtures.detail(year: 2025, month: 12, day: 5)])
        try await Fixtures.addReceipt(to: repository, details: [Fixtures.detail(year: 2024, month: 12, day: 6)])
        let viewModel = makeViewModel()

        await viewModel.load()

        let months = viewModel.years.flatMap(\.months)
        #expect(months.map(\.month) == [12, 12])
        #expect(Set(months.map(\.id)).count == 2)
    }

    @Test func addsAPdfAndShowsIt() async throws {
        let pdf = try makePdf(named: "「はじめて」を応援する _ ポピンズシッター(5).pdf", contents: "%PDF-1.4 November")
        let viewModel = makeViewModel { data in
            #expect(data == Data("%PDF-1.4 November".utf8))
            return ParsedReceipt(year: 2025, month: 11, details: [
                Fixtures.parsed(Fixtures.detail(month: 11, day: 7, sitterName: "高野 あみい", amount: 14300)),
                Fixtures.parsed(Fixtures.detail(month: 11, day: 12, sitterName: "早川明日香", amount: 7800)),
            ])
        }

        await viewModel.addReceipt(from: pdf)

        #expect(viewModel.error == nil)
        #expect(!viewModel.isGenerating)
        let item = try #require(viewModel.years.first?.months.first?.receipts.first)
        #expect(viewModel.years.map(\.year) == [2025])
        #expect(viewModel.years[0].months.map(\.month) == [11])
        #expect(item.amount == 22100)
        #expect(item.sitterNames == "高野 あみい、早川明日香")
        #expect(item.originalFileName == "「はじめて」を応援する _ ポピンズシッター(5).pdf")

        let stored = try #require(await repository.getAllReceipts().first)
        #expect(stored.receipt.sitterName == "高野 あみい")
        #expect(stored.details.map(\.day) == [7, 12])
        #expect(try Data(contentsOf: repository.fileURL(for: stored.receipt)) == Data("%PDF-1.4 November".utf8))
    }

    @Test func showsWhatWentWrongWhenParsingFails() async throws {
        let viewModel = makeViewModel { _ in throw PdfParserError.noEntries }

        await viewModel.addReceipt(from: try makePdf(named: "empty.pdf"))

        #expect(viewModel.error == "領収書を追加できませんでした。\nPDFに有効な利用明細が見つかりませんでした。")
        #expect(!viewModel.isGenerating)
        #expect(viewModel.years.isEmpty)
        #expect(try await repository.getAllReceipts().isEmpty)

        viewModel.dismissError()

        #expect(viewModel.error == nil)
    }

    @Test func showsWhatWentWrongWhenTheFileCannotBeRead() async {
        let viewModel = makeViewModel { _ in
            Issue.record("Nothing to parse")
            throw PdfParserError.noEntries
        }

        await viewModel.addReceipt(from: directory.appendingPathComponent("missing.pdf"))

        #expect(viewModel.error?.hasPrefix("領収書を追加できませんでした。\n") == true)
        #expect(!viewModel.isGenerating)
    }

    @Test func selectsReceiptsInTheOrderTheyAreTapped() {
        let viewModel = makeViewModel()

        viewModel.toggleSelection(3)
        viewModel.toggleSelection(1)
        viewModel.toggleSelection(2)
        viewModel.toggleSelection(1)

        #expect(viewModel.selectedReceiptIds == [3, 2])
        #expect(viewModel.isSelected(3))
        #expect(!viewModel.isSelected(1))

        viewModel.clearSelection()

        #expect(viewModel.selectedReceiptIds.isEmpty)
    }

    @Test func deletesTheSelectedReceipts() async throws {
        let kept = try await Fixtures.addReceipt(to: repository, details: [Fixtures.detail(month: 10, day: 1)])
        let deleted = try await Fixtures.addReceipt(to: repository, details: [Fixtures.detail(month: 11, day: 7)])
        let viewModel = makeViewModel()
        await viewModel.load()
        viewModel.toggleSelection(deleted)

        await viewModel.deleteSelected()

        #expect(viewModel.selectedReceiptIds.isEmpty)
        #expect(viewModel.years.flatMap(\.months).flatMap(\.receipts).map(\.id) == [kept])
        #expect(try await repository.getAllReceipts().map(\.receipt.id) == [kept])
    }

    @Test func remembersTheFamilyName() {
        let viewModel = makeViewModel()
        #expect(viewModel.familyName == "")

        viewModel.setFamilyName("ベイリー")

        #expect(viewModel.familyName == "ベイリー")
        #expect(userDefaults.string(forKey: "family_name") == "ベイリー")
        #expect(makeViewModel().familyName == "ベイリー")
    }
}
