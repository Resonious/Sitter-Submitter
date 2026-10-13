import Foundation
import Observation

struct ChildData: Equatable {
    let childName: String
    let details: [ReceiptDetailEntity]
    let totalAmount: Int
}

@MainActor
@Observable
final class GenerateViewModel {
    private(set) var isLoading = true
    private(set) var children: [ChildData] = []
    /// The latest generated spreadsheet. The screen previews it while set; dismissing the preview clears it.
    var generatedFileURL: URL?
    private(set) var generatedChildName: String?
    private(set) var error: String?

    private let receiptIds: [Int64]
    private let receiptRepository: ReceiptRepository
    private let reportGenerator: ReportGenerator
    private let userDefaults: UserDefaults
    private let outputDirectory: URL
    private var hasLoaded = false

    init(
        receiptIds: [Int64],
        receiptRepository: ReceiptRepository,
        reportGenerator: ReportGenerator,
        userDefaults: UserDefaults,
        outputDirectory: URL
    ) {
        self.receiptIds = receiptIds
        self.receiptRepository = receiptRepository
        self.reportGenerator = reportGenerator
        self.userDefaults = userDefaults
        self.outputDirectory = outputDirectory
    }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        guard !receiptIds.isEmpty else {
            isLoading = false
            error = "No receipts selected"
            return
        }
        do {
            var allDetails: [ReceiptDetailEntity] = []
            for id in receiptIds {
                allDetails += try await receiptRepository.getDetailsForReceipt(id)
            }
            children = Self.groupByChild(allDetails)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func generateReport(forChild childName: String) async {
        isLoading = true
        do {
            guard let childData = children.first(where: { $0.childName == childName }) else {
                throw GenerateError.childNotFound
            }
            let familyName = userDefaults.string(forKey: HomeViewModel.familyNameKey) ?? ""
            let fullName = familyName.isEmpty ? childName : "\(familyName) \(childName)"
            let outputURL = outputDirectory.appendingPathComponent(
                "submission_\(Self.safeFileName(childName))_\(Int64(Date().timeIntervalSince1970 * 1000)).xlsx"
            )
            try await Self.generate(with: reportGenerator, details: childData.details, childName: fullName, outputURL: outputURL)
            generatedFileURL = outputURL
            generatedChildName = childName
        } catch {
            self.error = "Generation failed: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func dismissError() {
        error = nil
    }

    /// One entry per child, sorted by name; details keep the order of the selected receipts.
    static func groupByChild(_ details: [ReceiptDetailEntity]) -> [ChildData] {
        details
            .groupedInOrder { $0.childName }
            .map { childName, details in
                ChildData(
                    childName: childName.isEmpty ? "Unknown" : childName,
                    details: details,
                    totalAmount: details.reduce(0) { $0 + $1.amount }
                )
            }
            .stableSorted { $0.childName.precedesInKotlinOrder($1.childName) }
    }

    /// Replaces everything but ASCII letters and digits, kana and common kanji with "_" (same as Android).
    static func safeFileName(_ name: String) -> String {
        var safe = String.UnicodeScalarView()
        for scalar in name.unicodeScalars {
            switch scalar.value {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x3040...0x30FF, 0x4E00...0x9FFF:
                safe.append(scalar)
            default:
                safe.append("_")
            }
        }
        return String(safe)
    }

    @concurrent
    private nonisolated static func generate(
        with generator: ReportGenerator,
        details: [ReceiptDetailEntity],
        childName: String,
        outputURL: URL
    ) async throws {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try generator.generate(details: details, childName: childName, outputURL: outputURL)
    }
}

enum GenerateError: LocalizedError {
    case childNotFound

    var errorDescription: String? {
        switch self {
        case .childNotFound: "Child not found"
        }
    }
}
