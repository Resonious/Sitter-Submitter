package dev.baillie.sittersubmitter.data.db

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "receipts")
data class ReceiptEntity(
    @PrimaryKey(autoGenerate = true) val id: Int = 0,
    val localPath: String, // Path to the copied PDF file in internal storage
    val year: Int,
    val month: Int, // 1-12
    val day: Int,
    val amount: Int,
    val sitterName: String,
    val originalFileName: String,
    val createdAt: Long = System.currentTimeMillis()
)
