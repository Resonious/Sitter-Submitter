package dev.baillie.sittersubmitter.domain.report

import android.content.Context
import dev.baillie.sittersubmitter.data.db.ReceiptDetailEntity
import org.apache.poi.xssf.usermodel.XSSFWorkbook
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream

class ReportGenerator(private val context: Context) {

    fun generate(details: List<ReceiptDetailEntity>, outputFile: File) {
        val inputStream: InputStream = context.assets.open("template.xlsx")
        val workbook = XSSFWorkbook(inputStream)
        val sheet = workbook.getSheetAt(0)

        // Sort details by date
        val sortedDetails = details.sortedWith(compareBy({ it.year }, { it.month }, { it.day }, { it.startTime }))

        if (sortedDetails.isNotEmpty()) {
            val first = sortedDetails[0]
            // Set Header Year/Month (Row 11, Index 11)
            // Assuming Year in Col 2 (Index 2) and Month in Col 6 (Index 6) based on gap
            // Row 11: < (0) ... Year (5) ... Month (8) >
            // Try Col 2 for Year, Col 6 for Month.
            val headerRow = sheet.getRow(11) ?: sheet.createRow(11)
            headerRow.createCell(2).setCellValue(first.year.toDouble())
            headerRow.createCell(6).setCellValue(first.month.toDouble())
        }

        // Fill data rows starting at Row 15
        var rowIndex = 15
        val startRow = 15
        val maxRow = 42 // Based on formulas ending around there?
        
        for (detail in sortedDetails) {
            val row = sheet.getRow(rowIndex) ?: break // Don't overflow template rows
            
            // Col 1: Month
            row.getCell(1)?.setCellValue(detail.month.toDouble())
            // Col 3: Day
            row.getCell(3)?.setCellValue(detail.day.toDouble())
            
            // Col 4: Start Time (String or Date?)
            // Excel expects time as number usually, but template might be string?
            // "18:45"
            row.getCell(4)?.setCellValue(detail.startTime)
            
            // Col 5: End Time
            row.getCell(5)?.setCellValue(detail.endTime)
            
            // Col 9: Fee
            row.getCell(9)?.setCellValue(detail.amount.toDouble())
            
            // Col 10: Option (0)
            row.getCell(10)?.setCellValue(0.0)
            
            // Col 11: Discount (0)
            row.getCell(11)?.setCellValue(0.0)
            
            rowIndex++
        }

        val fileOut = FileOutputStream(outputFile)
        workbook.write(fileOut)
        fileOut.close()
        workbook.close()
    }
}
