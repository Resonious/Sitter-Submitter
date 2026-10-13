import Foundation

/// A receipt PDF the user added. Mirrors the Android `receipts` table.
struct ReceiptEntity: Identifiable, Equatable, Sendable {
    var id: Int64 = 0
    /// File name of the stored copy of the PDF, relative to the repository's receipts directory.
    /// (Android stores an absolute path; on iOS the app container path changes between installs and updates.)
    var localPath: String
    var year: Int
    var month: Int // 1-12
    var day: Int
    var amount: Int
    var sitterName: String
    var originalFileName: String
    var createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
}

/// One babysitting session parsed out of a receipt. Mirrors the Android `receipt_details` table.
struct ReceiptDetailEntity: Identifiable, Equatable, Sendable {
    var id: Int64 = 0
    var receiptId: Int64
    var year: Int
    var month: Int
    var day: Int
    var startTime: String
    var endTime: String
    var sitterName: String
    var childName: String = ""
    var amount: Int
}

struct ReceiptWithDetails: Equatable, Sendable {
    var receipt: ReceiptEntity
    var details: [ReceiptDetailEntity]
}
