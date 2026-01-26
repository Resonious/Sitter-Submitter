package dev.baillie.sittersubmitter.data.repository

import android.content.Context
import android.net.Uri
import dev.baillie.sittersubmitter.data.db.ReceiptDao
import dev.baillie.sittersubmitter.data.db.ReceiptEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

import dev.baillie.sittersubmitter.data.db.ReceiptDetailEntity

class ReceiptRepository(
    private val receiptDao: ReceiptDao,
    private val context: Context
) {
    fun getAllReceipts(): Flow<List<ReceiptEntity>> = receiptDao.getAllReceipts()

    suspend fun addReceiptWithDetails(
        uri: Uri,
        originalFileName: String,
        year: Int,
        month: Int,
        amount: Int,
        sitterName: String,
        details: List<ReceiptDetailEntity>
    ) {
        withContext(Dispatchers.IO) {
            val fileName = "receipt_${UUID.randomUUID()}.pdf"
            val file = File(context.filesDir, fileName)
            
            context.contentResolver.openInputStream(uri)?.use { input ->
                file.outputStream().use { output ->
                    input.copyTo(output)
                }
            }

            val entity = ReceiptEntity(
                localPath = file.absolutePath,
                year = year,
                month = month,
                day = 1, // Default day
                amount = amount,
                sitterName = sitterName,
                originalFileName = originalFileName
            )
            
            val receiptId = receiptDao.insertReceipt(entity).toInt()
            
            val detailsWithId = details.map { it.copy(receiptId = receiptId) }
            receiptDao.insertReceiptDetails(detailsWithId)
        }
    }

    suspend fun deleteReceipt(receipt: ReceiptEntity) {
        withContext(Dispatchers.IO) {
            val file = File(receipt.localPath)
            if (file.exists()) {
                file.delete()
            }
            receiptDao.deleteReceipt(receipt)
        }
    }

    suspend fun getReceiptsByIds(ids: List<Int>): List<ReceiptEntity> {
        return receiptDao.getReceiptsByIds(ids)
    }

    suspend fun getDetailsForReceipt(receiptId: Int): List<ReceiptDetailEntity> {
        return receiptDao.getDetailsForReceipt(receiptId)
    }
}
