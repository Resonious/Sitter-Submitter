package dev.baillie.sittersubmitter.domain.pdf

import androidx.test.core.app.ApplicationProvider
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File

@RunWith(RobolectricTestRunner::class)
class PdfParserTest {

    @Before
    fun setup() {
        PDFBoxResourceLoader.init(ApplicationProvider.getApplicationContext())
    }

    @Test
    fun parse_examplePdf5() {
        val parser = PdfParser()
        val file = File("docs/「はじめて」を応援する _ ポピンズシッター(5).pdf")
        
        if (!file.exists()) {
             val file2 = File("../docs/「はじめて」を応援する _ ポピンズシッター(5).pdf")
             if (file2.exists()) {
                 val result = parser.parse(file2)
                 assertNotNull(result)
                 println("Parsed ${result.details.size} entries from ${file2.name}")
                 result.details.forEach { println(it) }
                 return
             }
             println("File not found at ${file.absolutePath} or ../docs/...")
             return
        }

        val result = parser.parse(file)
        
        assertNotNull(result)
        assertFalse(result.details.isEmpty())
        
        println("Parsed ${result.details.size} entries from ${file.name}")
        result.details.forEach {
            println(it)
        }
    }
    
    @Test
    fun parse_examplePdf() {
        val parser = PdfParser()
        val file = File("docs/「はじめて」を応援する _ ポピンズシッター.pdf")
        
        if (!file.exists()) {
             val file2 = File("../docs/「はじめて」を応援する _ ポピンズシッター.pdf")
             if (file2.exists()) {
                 val result = parser.parse(file2)
                 assertNotNull(result)
                 println("Parsed ${result.details.size} entries from ${file2.name}")
                 result.details.forEach { println(it) }
                 return
             }
            return
        }

        val result = parser.parse(file)
        
        assertNotNull(result)
        assertFalse(result.details.isEmpty())
        
        println("Parsed ${result.details.size} entries from ${file.name}")
        result.details.forEach {
            println(it)
        }
    }
}