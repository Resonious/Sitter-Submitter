import Foundation
import Testing
@testable import SitterSubmitter

@MainActor
struct GenerateViewModelTests {
    private let directory: URL
    private let outputDirectory: URL
    private let repository: ReceiptRepository
    private let userDefaults = makeUserDefaults()

    init() throws {
        directory = try makeTemporaryDirectory()
        outputDirectory = directory.appendingPathComponent("output", isDirectory: true)
        repository = try makeRepository(in: directory)
    }

    private func makeViewModel(
        receiptIds: [Int64],
        reportGenerator: ReportGenerator = ReportGenerator(templateURL: TestPaths.template)
    ) -> GenerateViewModel {
        GenerateViewModel(
            receiptIds: receiptIds,
            receiptRepository: repository,
            reportGenerator: reportGenerator,
            userDefaults: userDefaults,
            outputDirectory: outputDirectory
        )
    }

    /// Two receipts: one for 杏 and 陽 in November, one for 杏 and an unnamed child in December.
    private func addReceipts() async throws -> (november: Int64, december: Int64) {
        let november = try await Fixtures.addReceipt(to: repository, details: [
            Fixtures.detail(month: 11, day: 7, amount: 14300),
            Fixtures.detail(month: 11, day: 8, childName: "陽", amount: 5000),
            Fixtures.detail(month: 11, day: 12, amount: 7800),
        ])
        let december = try await Fixtures.addReceipt(to: repository, details: [
            Fixtures.detail(month: 12, day: 5, amount: 15600),
            Fixtures.detail(month: 12, day: 6, childName: "", amount: 1000),
        ])
        return (november, december)
    }

    @Test func groupsTheSelectedSessionsByChild() async throws {
        let receipts = try await addReceipts()
        let viewModel = makeViewModel(receiptIds: [receipts.december, receipts.november])
        #expect(viewModel.isLoading)

        await viewModel.load()

        #expect(!viewModel.isLoading)
        #expect(viewModel.error == nil)
        #expect(viewModel.children.map(\.childName) == ["Unknown", "杏", "陽"])
        // In the order the receipts were selected.
        #expect(viewModel.children[1].details.map(\.day) == [5, 7, 12])
        #expect(viewModel.children.map(\.totalAmount) == [1000, 37700, 5000])
    }

    @Test func needsASelection() async {
        let viewModel = makeViewModel(receiptIds: [])

        await viewModel.load()

        #expect(!viewModel.isLoading)
        #expect(viewModel.error == "No receipts selected")
    }

    @Test func generatesOneChildsSubmission() async throws {
        let receipts = try await addReceipts()
        userDefaults.set("ベイリー", forKey: "family_name")
        let viewModel = makeViewModel(receiptIds: [receipts.november, receipts.december])
        await viewModel.load()

        await viewModel.generateReport(forChild: "杏")

        #expect(viewModel.error == nil)
        #expect(!viewModel.isLoading)
        #expect(viewModel.generatedChildName == "杏")
        let file = try #require(viewModel.generatedFileURL)
        #expect(file.deletingLastPathComponent().standardizedFileURL == outputDirectory.standardizedFileURL)
        #expect(file.lastPathComponent.wholeMatch(of: /submission_杏_\d{13}\.xlsx/) != nil)

        let workbook = try XlsxTemplate(data: Data(contentsOf: file))
        #expect(workbook.value(at: "F4") == .string("ベイリー 杏"))
        #expect(workbook.value(at: "C12") == .number(2025))
        #expect(workbook.value(at: "G12") == .number(11))
        #expect(["D16", "D17", "D18", "D19"].map { workbook.value(at: $0) } == [
            .string("7日"), .string("12日"), .string("5日"), .string("日"),
        ])
    }

    @Test func usesJustTheChildsNameWithoutAFamilyName() async throws {
        let receipts = try await addReceipts()
        let viewModel = makeViewModel(receiptIds: [receipts.december])
        await viewModel.load()

        await viewModel.generateReport(forChild: "Unknown")

        let workbook = try XlsxTemplate(data: Data(contentsOf: #require(viewModel.generatedFileURL)))
        #expect(workbook.value(at: "F4") == .string("Unknown"))
        #expect(viewModel.generatedFileURL?.lastPathComponent.hasPrefix("submission_Unknown_") == true)
    }

    @Test func showsWhatWentWrongWhenGenerationFails() async throws {
        let receipts = try await addReceipts()
        let missingTemplate = directory.appendingPathComponent("missing.xlsx")
        let viewModel = makeViewModel(receiptIds: [receipts.november], reportGenerator: ReportGenerator(templateURL: missingTemplate))
        await viewModel.load()

        await viewModel.generateReport(forChild: "杏")

        #expect(viewModel.error?.hasPrefix("Generation failed: ") == true)
        #expect(viewModel.generatedFileURL == nil)
        #expect(!viewModel.isLoading)
    }

    @Test func showsWhatWentWrongForAnUnknownChild() async throws {
        let receipts = try await addReceipts()
        let viewModel = makeViewModel(receiptIds: [receipts.november])
        await viewModel.load()

        await viewModel.generateReport(forChild: "誰")

        #expect(viewModel.error == "Generation failed: Child not found")
    }

    @Test(arguments: [
        ("杏", "杏"), ("Anne-Marie 2", "Anne_Marie_2"), ("あんず・アンズ", "あんず・アンズ"), ("😀x", "_x"), ("Ａ", "_"),
    ])
    func makesFileNamesSafe(name: String, expected: String) {
        #expect(GenerateViewModel.safeFileName(name) == expected)
    }
}
