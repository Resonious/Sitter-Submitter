package dev.baillie.sittersubmitter.data.db

import androidx.room.Database
import androidx.room.RoomDatabase

@Database(entities = [ReceiptEntity::class, ReceiptDetailEntity::class], version = 2)
abstract class AppDatabase : RoomDatabase() {
    abstract fun receiptDao(): ReceiptDao
}
