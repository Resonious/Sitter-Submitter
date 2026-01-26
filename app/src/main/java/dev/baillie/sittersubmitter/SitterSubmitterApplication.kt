package dev.baillie.sittersubmitter

import android.app.Application
import androidx.room.Room
import dev.baillie.sittersubmitter.data.db.AppDatabase
import dev.baillie.sittersubmitter.data.repository.ReceiptRepository
import dev.baillie.sittersubmitter.domain.pdf.PdfParser
import dev.baillie.sittersubmitter.domain.report.ReportGenerator

class SitterSubmitterApplication : Application() {
    
    lateinit var container: AppContainer

    override fun onCreate() {
        super.onCreate()
        System.setProperty("org.apache.poi.javax.xml.stream.XMLInputFactory", "com.fasterxml.aalto.stax.InputFactoryImpl")
        System.setProperty("org.apache.poi.javax.xml.stream.XMLOutputFactory", "com.fasterxml.aalto.stax.OutputFactoryImpl")
        System.setProperty("org.apache.poi.javax.xml.stream.XMLEventFactory", "com.fasterxml.aalto.stax.EventFactoryImpl")
        
        container = AppContainer(this)
    }
}

class AppContainer(context: android.content.Context) {
    val database = Room.databaseBuilder(
        context,
        AppDatabase::class.java, "sitter-submitter-db"
    ).fallbackToDestructiveMigration().build()
    
    val receiptRepository = ReceiptRepository(database.receiptDao(), context)
    val pdfParser = PdfParser()
    val reportGenerator = ReportGenerator(context)
}
