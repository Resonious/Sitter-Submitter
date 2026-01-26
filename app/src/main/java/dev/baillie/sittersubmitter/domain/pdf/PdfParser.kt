package dev.baillie.sittersubmitter.domain.pdf

import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import java.io.File
import java.io.InputStream
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.regex.Pattern

data class ParsedReceipt(
    val year: Int,
    val month: Int,
    val details: List<ParsedReceiptDetail>
)

data class ParsedReceiptDetail(
    val year: Int,
    val month: Int,
    val day: Int,
    val startTime: String,
    val endTime: String,
    val sitterName: String,
    val amount: Int
)

class PdfParser {

    fun parse(inputStream: InputStream): ParsedReceipt {
        val document = PDDocument.load(inputStream)
        return try {
            val stripper = PDFTextStripper()
            stripper.sortByPosition = true
            val text = stripper.getText(document)
            parseText(text)
        } finally {
            document.close()
        }
    }
    
    fun parse(file: File): ParsedReceipt {
        val document = PDDocument.load(file)
        return try {
            val stripper = PDFTextStripper()
            stripper.sortByPosition = true
            val text = stripper.getText(document)
            parseText(text)
        } finally {
            document.close()
        }
    }

    private fun parseText(text: String): ParsedReceipt {
        val details = mutableListOf<ParsedReceiptDetail>()
        val lines = text.split("\n")
        
        // Regex for date: YYYY/MM/DD
        // Example: 2024/12/06 18:45 19:45 SitterName ... Amount
        // Adjust regex to capture components
        // Note: Sitter name might contain spaces (Japanese names often have space between surname and name).
        // The columns seem to be: Date, Start, End, Sitter, Child, Fee, ... Total
        
        // Simple strategy: Find line starting with date. Split by whitespace.
        // Assuming dates are YYYY/MM/DD
        val datePattern = Pattern.compile("^(\\d{4})/(\\d{1,2})/(\\d{1,2})")
        
        for (line in lines) {
            val trimmedLine = line.trim()
            val matcher = datePattern.matcher(trimmedLine)
            if (matcher.find()) {
                try {
                    val parts = trimmedLine.split("\\s+".toRegex())
                    if (parts.size >= 4) { // Date, Start, End, Sitter...
                        val dateStr = parts[0]
                        val start = parts[1]
                        val end = parts[2]
                        // Sitter name might be parts[3] or parts[3]+parts[4]
                        // Let's assume sitter name is the next token(s) until we hit a number or known structure?
                        // Or just take parts[3].
                        // In the image: "蜜本 沙希" (2 parts) or "蜜本沙希" (1 part)?
                        // "蜜本 沙希 穂 杏" -> Sitter name, Child name...
                        // The last column is the amount? "3,620"
                        // Amount is usually at the end.
                        
                        // Let's look for the amount at the end.
                        val amountStr = parts.last().replace(",", "").replace("円", "")
                        val amount = amountStr.toIntOrNull() ?: 0
                        
                        val year = matcher.group(1)!!.toInt()
                        val month = matcher.group(2)!!.toInt()
                        val day = matcher.group(3)!!.toInt()
                        
                        // Heuristic for sitter name: parts between EndTime and next Number?
                        // Actually, looking at image: 
                        // Col 4: Sitter Name.
                        // Col 5: Child Name.
                        // Col 6: Fee (number).
                        // So Sitter Name is likely just one or two tokens after EndTime.
                        // Let's take parts[3]. If parts[4] is not a number, maybe append?
                        // For now, take parts[3].
                        
                        val sitterName = parts[3]

                        details.add(
                            ParsedReceiptDetail(
                                year = year,
                                month = month,
                                day = day,
                                startTime = start,
                                endTime = end,
                                sitterName = sitterName,
                                amount = amount
                            )
                        )
                    }
                } catch (e: Exception) {
                    // Log error or ignore line
                    e.printStackTrace()
                }
            }
        }
        
        // Determine overall year/month from details (use the first one or majority)
        if (details.isEmpty()) {
            throw IllegalArgumentException("No valid receipt entries found in PDF.")
        }
        
        // Use the first entry's month/year as the receipt's "Month"
        val first = details[0]
        
        return ParsedReceipt(
            year = first.year,
            month = first.month,
            details = details
        )
    }
}
