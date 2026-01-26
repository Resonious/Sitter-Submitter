package dev.baillie.sittersubmitter.data.db

import androidx.room.Embedded
import androidx.room.Relation

data class ReceiptWithDetails(
    @Embedded val receipt: ReceiptEntity,
    @Relation(
        parentColumn = "id",
        entityColumn = "receiptId"
    )
    val details: List<ReceiptDetailEntity>
)
