package dev.baillie.sittersubmitter.domain.report

import org.apache.poi.xssf.usermodel.XSSFWorkbook
import org.junit.Test
import java.io.File
import java.io.FileInputStream

class ReportGeneratorTest {

    @Test
    fun inspectTemplate() {
        val file = File("src/main/assets/template.xlsx")
        if (!file.exists()) {
             // Fallback if running from root
             val file2 = File("app/src/main/assets/template.xlsx")
             if (file2.exists()) {
                 inspect(file2)
                 return
             }
             println("Template not found at ${file.absolutePath}")
             return
        }
        inspect(file)
    }
    
    private fun inspect(file: File) {
        val fis = FileInputStream(file)
        val workbook = XSSFWorkbook(fis)
        val sheet = workbook.getSheetAt(0)

        println("Inspecting Template Sheet 0:")
        for (row in sheet) {
            for (cell in row) {
                println("Row ${row.rowNum} Col ${cell.columnIndex}: ${cell.toString()}")
            }
        }
        workbook.close()
    }
}
