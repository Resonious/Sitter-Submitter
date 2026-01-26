package dev.baillie.sittersubmitter.data.db

import androidx.room.Database
import androidx.room.RoomDatabase
import dev.baillie.sittersubmitter.data.db.ReceiptEntity
import dev.baillie.sittersubmitter.data.db.ReceiptDetailEntity

@Database(entities = [ReceiptEntity::class, ReceiptDetailEntity::class], version = 1)
abstract class AppDatabase : RoomDatabase() {
    abstract fun receiptDao(): ReceiptDao
}
