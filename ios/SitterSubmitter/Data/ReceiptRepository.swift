import Foundation

/// Stores receipts in SQLite and keeps a copy of each original PDF. Port of the Android `ReceiptRepository`
/// together with its Room DAO and schema.
actor ReceiptRepository {
    private let database: SQLiteDatabase
    private let receiptsDirectory: URL

    init(databasePath: String, receiptsDirectory: URL) throws {
        try FileManager.default.createDirectory(at: receiptsDirectory, withIntermediateDirectories: true)
        let database = try SQLiteDatabase(path: databasePath)
        try Self.migrate(database)
        self.database = database
        self.receiptsDirectory = receiptsDirectory
    }

    /// The app's store, under Application Support.
    static func makeDefault() throws -> ReceiptRepository {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return try ReceiptRepository(
            databasePath: directory.appendingPathComponent("sitter-submitter.sqlite").path,
            receiptsDirectory: directory.appendingPathComponent("receipts", isDirectory: true)
        )
    }

    func getAllReceipts() throws -> [ReceiptWithDetails] {
        let receipts = try database.query(
            "SELECT \(Self.receiptColumns) FROM receipts ORDER BY year DESC, month DESC, day DESC, id",
            map: Self.receipt
        )
        let details = try database.query("SELECT \(Self.detailColumns) FROM receipt_details ORDER BY id", map: Self.detail)
        let detailsByReceipt = Dictionary(grouping: details, by: \.receiptId)
        return receipts.map { ReceiptWithDetails(receipt: $0, details: detailsByReceipt[$0.id] ?? []) }
    }

    /// Saves a copy of the PDF, then the receipt and its details. Returns the new receipt's id.
    @discardableResult
    func addReceiptWithDetails(
        pdfData: Data,
        originalFileName: String,
        year: Int,
        month: Int,
        amount: Int,
        sitterName: String,
        details: [ReceiptDetailEntity]
    ) throws -> Int64 {
        let fileName = "receipt_\(UUID().uuidString.lowercased()).pdf"
        let file = receiptsDirectory.appendingPathComponent(fileName)
        try pdfData.write(to: file, options: .atomic)

        let receipt = ReceiptEntity(
            localPath: fileName,
            year: year,
            month: month,
            day: 1, // Default day
            amount: amount,
            sitterName: sitterName,
            originalFileName: originalFileName
        )
        do {
            var receiptId: Int64 = 0
            try database.transaction {
                receiptId = try database.run(
                    """
                    INSERT INTO receipts (localPath, year, month, day, amount, sitterName, originalFileName, createdAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    [
                        .text(receipt.localPath), .integer(Int64(receipt.year)), .integer(Int64(receipt.month)),
                        .integer(Int64(receipt.day)), .integer(Int64(receipt.amount)), .text(receipt.sitterName),
                        .text(receipt.originalFileName), .integer(receipt.createdAt),
                    ]
                )
                for detail in details {
                    try database.run(
                        """
                        INSERT INTO receipt_details
                            (receiptId, year, month, day, startTime, endTime, sitterName, childName, amount)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        [
                            .integer(receiptId), .integer(Int64(detail.year)), .integer(Int64(detail.month)),
                            .integer(Int64(detail.day)), .text(detail.startTime), .text(detail.endTime),
                            .text(detail.sitterName), .text(detail.childName), .integer(Int64(detail.amount)),
                        ]
                    )
                }
            }
            return receiptId
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }

    func getReceiptsByIds(_ ids: [Int64]) throws -> [ReceiptEntity] {
        guard !ids.isEmpty else { return [] }
        return try database.query(
            "SELECT \(Self.receiptColumns) FROM receipts WHERE id IN (\(Self.placeholders(ids.count)))",
            ids.map { .integer($0) },
            map: Self.receipt
        )
    }

    func getDetailsForReceipt(_ receiptId: Int64) throws -> [ReceiptDetailEntity] {
        try database.query(
            "SELECT \(Self.detailColumns) FROM receipt_details WHERE receiptId = ? ORDER BY id",
            [.integer(receiptId)],
            map: Self.detail
        )
    }

    func deleteReceiptsByIds(_ ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        // Get receipts to delete their PDF files
        for receipt in try getReceiptsByIds(ids) {
            try? FileManager.default.removeItem(at: fileURL(for: receipt))
        }
        // Delete from DB (cascade will delete details)
        try database.run("DELETE FROM receipts WHERE id IN (\(Self.placeholders(ids.count)))", ids.map { .integer($0) })
    }

    /// Where the stored copy of a receipt's PDF lives.
    nonisolated func fileURL(for receipt: ReceiptEntity) -> URL {
        receiptsDirectory.appendingPathComponent(receipt.localPath)
    }

    // MARK: - Schema

    /// Same tables as the Android app's Room database.
    private static func migrate(_ database: SQLiteDatabase) throws {
        guard try database.userVersion < 1 else { return }
        try database.transaction {
            try database.execute(
                """
                CREATE TABLE IF NOT EXISTS receipts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                    localPath TEXT NOT NULL,
                    year INTEGER NOT NULL,
                    month INTEGER NOT NULL,
                    day INTEGER NOT NULL,
                    amount INTEGER NOT NULL,
                    sitterName TEXT NOT NULL,
                    originalFileName TEXT NOT NULL,
                    createdAt INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS receipt_details (
                    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                    receiptId INTEGER NOT NULL REFERENCES receipts(id) ON DELETE CASCADE,
                    year INTEGER NOT NULL,
                    month INTEGER NOT NULL,
                    day INTEGER NOT NULL,
                    startTime TEXT NOT NULL,
                    endTime TEXT NOT NULL,
                    sitterName TEXT NOT NULL,
                    childName TEXT NOT NULL,
                    amount INTEGER NOT NULL
                );
                CREATE INDEX IF NOT EXISTS index_receipt_details_receiptId ON receipt_details (receiptId);
                PRAGMA user_version = 1;
                """
            )
        }
    }

    private static let receiptColumns = "id, localPath, year, month, day, amount, sitterName, originalFileName, createdAt"
    private static let detailColumns = "id, receiptId, year, month, day, startTime, endTime, sitterName, childName, amount"

    private static func receipt(from row: SQLiteDatabase.Row) -> ReceiptEntity {
        ReceiptEntity(
            id: row.int64(0),
            localPath: row.text(1),
            year: row.int(2),
            month: row.int(3),
            day: row.int(4),
            amount: row.int(5),
            sitterName: row.text(6),
            originalFileName: row.text(7),
            createdAt: row.int64(8)
        )
    }

    private static func detail(from row: SQLiteDatabase.Row) -> ReceiptDetailEntity {
        ReceiptDetailEntity(
            id: row.int64(0),
            receiptId: row.int64(1),
            year: row.int(2),
            month: row.int(3),
            day: row.int(4),
            startTime: row.text(5),
            endTime: row.text(6),
            sitterName: row.text(7),
            childName: row.text(8),
            amount: row.int(9)
        )
    }

    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }
}
