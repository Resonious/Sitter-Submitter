package dev.baillie.sittersubmitter.domain.report

import android.content.Context
import dev.baillie.sittersubmitter.data.db.ReceiptDetailEntity
import org.apache.poi.xssf.usermodel.XSSFWorkbook
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream

class ReportGenerator(private val context: Context) {

    fun generate(details: List<ReceiptDetailEntity>, childName: String, outputFile: File) {
        val inputStream: InputStream = context.assets.open("template.xlsx")
        val workbook = XSSFWorkbook(inputStream)
        val sheet = workbook.getSheetAt(0)

        // Sort details by date
        val sortedDetails = details.sortedWith(compareBy({ it.year }, { it.month }, { it.day }, { it.startTime }))

        if (sortedDetails.isNotEmpty()) {
            val first = sortedDetails[0]
            // Set Header Year/Month (Row 11)
            val headerRow = sheet.getRow(11) ?: sheet.createRow(11)
            headerRow.createCell(2).setCellValue(first.year.toDouble())
            headerRow.createCell(6).setCellValue(first.month.toDouble())

            // Set Child Name (Row 4, Col F = index 3, 5)
            val nameRow = sheet.getRow(3) ?: sheet.createRow(3)
            val nameCell = nameRow.getCell(5) ?: nameRow.createCell(5)
            nameCell.setCellValue(childName)
        }

        // Fill data rows starting at Row 15
        var rowIndex = 15
        val startRow = 15
        val maxRow = 42 // Based on formulas ending around there?
        
        for (detail in sortedDetails) {
            val row = sheet.getRow(rowIndex) ?: break // Don't overflow template rows
            
            // Col 1: Month
            row.getCell(1)?.setCellValue("${detail.month}月")
            // Col 3: Day
            row.getCell(3)?.setCellValue("${detail.day}日")
            
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

        // Set column widths to ensure data is visible
        // Width is in units of 1/256th of a character
        sheet.setColumnWidth(1, 6 * 256)   // Month column
        sheet.setColumnWidth(3, 6 * 256)   // Day column
        sheet.setColumnWidth(4, 10 * 256)  // Start time column
        sheet.setColumnWidth(5, 10 * 256)  // End time column

        val fileOut = FileOutputStream(outputFile)
        workbook.write(fileOut)
        fileOut.close()
        workbook.close()
    }
}
