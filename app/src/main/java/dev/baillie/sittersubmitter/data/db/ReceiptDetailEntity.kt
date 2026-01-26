package dev.baillie.sittersubmitter.data.db

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.PrimaryKey

@Entity(
    tableName = "receipt_details",
    foreignKeys = [
        ForeignKey(
            entity = ReceiptEntity::class,
            parentColumns = ["id"],
            childColumns = ["receiptId"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [androidx.room.Index("receiptId")]
)
data class ReceiptDetailEntity(
    @PrimaryKey(autoGenerate = true) val id: Int = 0,
    val receiptId: Int,
    val year: Int,
    val month: Int,
    val day: Int,
    val startTime: String,
    val endTime: String,
    val sitterName: String,
    val amount: Int
)
