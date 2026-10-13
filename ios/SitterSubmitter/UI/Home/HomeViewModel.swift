import Foundation
import Observation

struct YearData: Identifiable, Equatable {
    let year: Int
    let months: [MonthData]

    var id: Int { year }
}

struct MonthData: Identifiable, Equatable {
    let year: Int
    let month: Int
    let receipts: [ReceiptDisplayItem]

    /// Unique across years: the home screen lists every year's months in one lazy stack.
    var id: Int { year * 100 + month }
}

struct ReceiptDisplayItem: Identifiable, Equatable {
    let id: Int64
    let amount: Int
    let sitterNames: String
    let childNames: String
    let originalFileName: String
}

@MainActor
@Observable
final class HomeViewModel {
    static let familyNameKey = "family_name"

    private(set) var years: [YearData] = []
    /// In the order they were selected, like the Android app's set.
    private(set) var selectedReceiptIds: [Int64] = []
    private(set) var familyName: String
    private(set) var isGenerating = false
    private(set) var error: String?

    private let receiptRepository: ReceiptRepository
    private let pdfParser: any PdfParsing
    private let userDefaults: UserDefaults
    private var latestReload = 0

    init(receiptRepository: ReceiptRepository, pdfParser: any PdfParsing, userDefaults: UserDefaults) {
        self.receiptRepository = receiptRepository
        self.pdfParser = pdfParser
        self.userDefaults = userDefaults
        familyName = userDefaults.string(forKey: Self.familyNameKey) ?? ""
    }

    func load() async {
        await reload()
    }

    func isSelected(_ receiptId: Int64) -> Bool {
        selectedReceiptIds.contains(receiptId)
    }

    func toggleSelection(_ receiptId: Int64) {
        if let index = selectedReceiptIds.firstIndex(of: receiptId) {
            selectedReceiptIds.remove(at: index)
        } else {
            selectedReceiptIds.append(receiptId)
        }
    }

    func clearSelection() {
        selectedReceiptIds = []
    }

    func setFamilyName(_ name: String) {
        familyName = name
        userDefaults.set(name, forKey: Self.familyNameKey)
    }

    func dismissError() {
        error = nil
    }

    /// Adds a receipt PDF picked in the app or opened with it from elsewhere.
    func addReceipt(from url: URL) async {
        isGenerating = true // Reusing loading state
        do {
            // 1. Parse PDF
            let pdfData = try await Self.readFile(at: url)
            let parsed = try await pdfParser.parse(pdfData)

            // 2. Get filename
            let fileName = url.lastPathComponent.isEmpty ? "名称未設定.pdf" : url.lastPathComponent

            // 3. Add to repository (which stores a copy of the PDF)
            let totalAmount = parsed.details.reduce(0) { $0 + $1.amount }
            let sitterName = parsed.details.first?.sitterName ?? "Unknown"
            try await receiptRepository.addReceiptWithDetails(
                pdfData: pdfData,
                originalFileName: fileName,
                year: parsed.year,
                month: parsed.month,
                amount: totalAmount,
                sitterName: sitterName,
                details: parsed.details.map {
                    ReceiptDetailEntity(
                        receiptId: 0, // Set by the repository
                        year: $0.year,
                        month: $0.month,
                        day: $0.day,
                        startTime: $0.startTime,
                        endTime: $0.endTime,
                        sitterName: $0.sitterName,
                        childName: $0.childName,
                        amount: $0.amount
                    )
                }
            )
            error = nil
            await reload()
        } catch {
            self.error = "領収書を追加できませんでした。\n\(error.localizedDescription)"
        }
        isGenerating = false
    }

    func deleteSelected() async {
        let idsToDelete = selectedReceiptIds
        guard !idsToDelete.isEmpty else { return }
        do {
            try await receiptRepository.deleteReceiptsByIds(idsToDelete)
            selectedReceiptIds = []
            await reload()
        } catch {
            self.error = "領収書を削除できませんでした。\n\(error.localizedDescription)"
        }
    }

    // The Android app observes the database; here every change goes through this view model, which reloads.
    private func reload() async {
        latestReload += 1
        let reload = latestReload
        do {
            let receipts = try await receiptRepository.getAllReceipts()
            guard reload == latestReload else { return } // Superseded by a newer reload
            years = Self.groupByYearAndMonth(receipts)
        } catch {
            self.error = "領収書を読み込めませんでした。\n\(error.localizedDescription)"
        }
    }

    /// Newest year first, then newest month first; receipts keep the repository's order.
    static func groupByYearAndMonth(_ receipts: [ReceiptWithDetails]) -> [YearData] {
        receipts
            .groupedInOrder { $0.receipt.year }
            .map { year, yearReceipts in
                YearData(
                    year: year,
                    months: yearReceipts
                        .groupedInOrder { $0.receipt.month }
                        .map { month, monthReceipts in
                            MonthData(year: year, month: month, receipts: monthReceipts.map(displayItem))
                        }
                        .stableSorted { $0.month > $1.month }
                )
            }
            .stableSorted { $0.year > $1.year }
    }

    private static func displayItem(_ receipt: ReceiptWithDetails) -> ReceiptDisplayItem {
        ReceiptDisplayItem(
            id: receipt.receipt.id,
            amount: receipt.receipt.amount,
            sitterNames: receipt.details.map(\.sitterName).distinct().joined(separator: "、"),
            childNames: receipt.details.map(\.childName).distinct().joined(separator: "、"),
            originalFileName: receipt.receipt.originalFileName
        )
    }

    @concurrent
    private nonisolated static func readFile(at url: URL) async throws -> Data {
        // Files from the document picker or another app are outside the sandbox until access is granted.
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing { url.stopAccessingSecurityScopedResource() }
        }
        return try Data(contentsOf: url)
    }
}
