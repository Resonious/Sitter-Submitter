package dev.baillie.sittersubmitter.data.db

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Transaction
import kotlinx.coroutines.flow.Flow

@Dao
interface ReceiptDao {
    @Query("SELECT * FROM receipts ORDER BY year DESC, month DESC, day DESC")
    fun getAllReceipts(): Flow<List<ReceiptEntity>>

    @Query("SELECT * FROM receipts WHERE year = :year AND month = :month ORDER BY day DESC")
    fun getReceiptsForMonth(year: Int, month: Int): Flow<List<ReceiptEntity>>

    @Insert
    suspend fun insertReceipt(receipt: ReceiptEntity): Long

    @Delete
    suspend fun deleteReceipt(receipt: ReceiptEntity)
    
    @Query("SELECT * FROM receipts WHERE id IN (:ids)")
    suspend fun getReceiptsByIds(ids: List<Int>): List<ReceiptEntity>

    @Insert
    suspend fun insertReceiptDetails(details: List<ReceiptDetailEntity>)

    @Query("SELECT * FROM receipt_details WHERE receiptId = :receiptId")
    suspend fun getDetailsForReceipt(receiptId: Int): List<ReceiptDetailEntity>

    @Transaction
    @Query("SELECT * FROM receipts WHERE id = :receiptId")
    suspend fun getReceiptWithDetails(receiptId: Int): ReceiptWithDetails?
}
