package dev.baillie.sittersubmitter.domain.pdf

import android.util.Base64
import android.util.Log
import com.google.gson.Gson
import dev.baillie.sittersubmitter.BuildConfig
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.io.InputStream
import java.util.concurrent.TimeUnit

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
    val childName: String,
    val amount: Int
)

class PdfParser {

    companion object {
        private const val TAG = "PdfParser"
        private const val OPENAI_API_URL = "https://api.openai.com/v1/responses"
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(120, TimeUnit.SECONDS)
        .readTimeout(120, TimeUnit.SECONDS)
        .writeTimeout(120, TimeUnit.SECONDS)
        .build()

    private val gson = Gson()

    fun parse(inputStream: InputStream): ParsedReceipt {
        val pdfBytes = inputStream.readBytes()
        return parseWithOpenAI(pdfBytes)
    }

    fun parse(file: File): ParsedReceipt {
        val pdfBytes = file.readBytes()
        return parseWithOpenAI(pdfBytes)
    }

    private fun parseWithOpenAI(pdfBytes: ByteArray): ParsedReceipt {
        val base64Pdf = Base64.encodeToString(pdfBytes, Base64.NO_WRAP)

        val prompt = """
Analyze this Japanese babysitter receipt PDF table. Each row represents one babysitting session.

The table columns are: ご利用日 | 開始時刻 | 終了時刻 | シッター名 | お子さま | 保育料... | お支払い額

For each data row, extract:
- date: from ご利用日 column (YYYY/MM/DD format)
- startTime: from 開始時刻 column (HH:MM format)
- endTime: from 終了時刻 column (HH:MM format)
- sitterName: from シッター名 column (full name)
- childName: from お子さま column - this contains the child's name followed by 様 and age in parentheses. Extract ONLY the single character or short name before 様. For example if the cell shows "杏 様 (0歳6ヶ月)" extract just "杏". Do NOT include 様, age, or any text from adjacent columns.
- amount: from お支払い額 column (rightmost, integer, no commas)

Return JSON: {"entries":[{"date":"YYYY/MM/DD","startTime":"HH:MM","endTime":"HH:MM","sitterName":"Name","childName":"Child","amount":1234}]}
        """.trim()

        // Build request JSON for Responses API (supports PDFs natively)
        val requestJson = JsonObject().apply {
            addProperty("model", "gpt-4o")
            add("input", gson.toJsonTree(listOf(
                mapOf(
                    "role" to "user",
                    "content" to listOf(
                        mapOf(
                            "type" to "input_text",
                            "text" to prompt
                        ),
                        mapOf(
                            "type" to "input_file",
                            "filename" to "receipt.pdf",
                            "file_data" to "data:application/pdf;base64,$base64Pdf"
                        )
                    )
                )
            )))
        }

        val jsonBody = gson.toJson(requestJson)
        Log.d(TAG, "Sending request to OpenAI API...")

        val request = Request.Builder()
            .url(OPENAI_API_URL)
            .addHeader("Authorization", "Bearer ${BuildConfig.OPENAI_API_KEY}")
            .addHeader("Content-Type", "application/json")
            .post(jsonBody.toRequestBody("application/json".toMediaType()))
            .build()

        val response = client.newCall(request).execute()

        val responseBody = response.body?.string()
            ?: throw RuntimeException("Empty response from OpenAI API")

        Log.d(TAG, "Response code: ${response.code}")

        if (!response.isSuccessful) {
            Log.e(TAG, "API Error: $responseBody")
            throw RuntimeException("OpenAI API error: ${response.code} - $responseBody")
        }

        Log.d(TAG, "Response body: $responseBody")

        // Parse response JSON manually to extract text content
        val responseJson = JsonParser.parseString(responseBody).asJsonObject
        var content: String? = null

        // Navigate: output[] -> find message type -> content[] -> find output_text -> text
        val output = responseJson.getAsJsonArray("output")
        for (outputItem in output) {
            val item = outputItem.asJsonObject
            if (item.get("type")?.asString == "message") {
                val contentArray = item.getAsJsonArray("content")
                for (contentItem in contentArray) {
                    val cItem = contentItem.asJsonObject
                    if (cItem.get("type")?.asString == "output_text") {
                        content = cItem.get("text")?.asString
                        break
                    }
                }
            }
            if (content != null) break
        }

        if (content == null) {
            throw RuntimeException("No content in OpenAI response: $responseBody")
        }

        Log.d(TAG, "GPT content: $content")

        // Extract JSON from response
        content = extractJson(content)

        Log.d(TAG, "Cleaned content: $content")

        // Parse the JSON response from GPT
        val extractedData = gson.fromJson(content, ExtractedReceiptData::class.java)

        if (extractedData.entries.isEmpty()) {
            throw IllegalArgumentException("No valid receipt entries found in PDF.")
        }

        val details = extractedData.entries.map { entry ->
            val dateParts = entry.date.split("/")
            ParsedReceiptDetail(
                year = dateParts[0].toInt(),
                month = dateParts[1].toInt(),
                day = dateParts[2].toInt(),
                startTime = entry.startTime,
                endTime = entry.endTime,
                sitterName = entry.sitterName,
                childName = entry.childName,
                amount = entry.amount
            )
        }

        val first = details[0]
        return ParsedReceipt(
            year = first.year,
            month = first.month,
            details = details
        )
    }

    private fun extractJson(content: String): String {
        val start = content.indexOf('{')
        val end = content.lastIndexOf('}')
        if (start == -1 || end == -1 || end <= start) {
            throw IllegalArgumentException("No valid JSON object found in response: $content")
        }
        return content.substring(start, end + 1)
    }

    // Response data models

    private data class ExtractedReceiptData(
        val entries: List<ExtractedEntry>
    )

    private data class ExtractedEntry(
        val date: String,
        val startTime: String,
        val endTime: String,
        val sitterName: String,
        val childName: String,
        val amount: Int
    )
}
