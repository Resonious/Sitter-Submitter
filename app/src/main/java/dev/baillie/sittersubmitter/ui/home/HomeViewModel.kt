package dev.baillie.sittersubmitter.ui.home

import android.content.ContentResolver
import android.content.SharedPreferences
import android.net.Uri
import android.provider.OpenableColumns
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.baillie.sittersubmitter.data.db.ReceiptDetailEntity
import dev.baillie.sittersubmitter.data.db.ReceiptEntity
import dev.baillie.sittersubmitter.data.db.ReceiptWithDetails
import dev.baillie.sittersubmitter.data.repository.ReceiptRepository
import dev.baillie.sittersubmitter.domain.pdf.PdfParser
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class HomeUiState(
    val years: List<YearData> = emptyList(),
    val selectedReceiptIds: Set<Int> = emptySet(),
    val familyName: String = "",
    val isGenerating: Boolean = false,
    val error: String? = null
)

data class YearData(
    val year: Int,
    val months: List<MonthData>
)

data class MonthData(
    val month: Int,
    val receipts: List<ReceiptDisplayItem>
)

data class ReceiptDisplayItem(
    val id: Int,
    val amount: Int,
    val sitterNames: String,
    val childNames: String,
    val originalFileName: String
)

class HomeViewModel(
    private val receiptRepository: ReceiptRepository,
    private val pdfParser: PdfParser,
    private val contentResolver: ContentResolver,
    private val sharedPreferences: SharedPreferences
) : ViewModel() {

    companion object {
        private const val KEY_FAMILY_NAME = "family_name"
    }

    private val _selectedReceiptIds = MutableStateFlow<Set<Int>>(emptySet())
    private val _error = MutableStateFlow<String?>(null)
    private val _isGenerating = MutableStateFlow(false)
    private val _familyName = MutableStateFlow(sharedPreferences.getString(KEY_FAMILY_NAME, "") ?: "")

    val uiState: StateFlow<HomeUiState> = combine(
        receiptRepository.getAllReceipts(),
        _selectedReceiptIds,
        _error,
        _isGenerating,
        _familyName
    ) { receiptsWithDetails, selected, error, isGenerating, familyName ->
        val displayItems = receiptsWithDetails.map { rwd ->
            ReceiptDisplayItem(
                id = rwd.receipt.id,
                amount = rwd.receipt.amount,
                sitterNames = rwd.details.map { it.sitterName }.distinct().joinToString(", "),
                childNames = rwd.details.map { it.childName }.distinct().joinToString(", "),
                originalFileName = rwd.receipt.originalFileName
            ) to rwd.receipt
        }

        val grouped = displayItems.groupBy { it.second.year }
            .map { (year, yearItems) ->
                YearData(
                    year = year,
                    months = yearItems.groupBy { it.second.month }
                        .map { (month, monthItems) ->
                            MonthData(month, monthItems.map { it.first })
                        }
                        .sortedByDescending { it.month }
                )
            }
            .sortedByDescending { it.year }

        HomeUiState(
            years = grouped,
            selectedReceiptIds = selected,
            familyName = familyName,
            error = error,
            isGenerating = isGenerating
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = HomeUiState()
    )

    fun toggleSelection(receiptId: Int) {
        _selectedReceiptIds.value = _selectedReceiptIds.value.toMutableSet().apply {
            if (contains(receiptId)) remove(receiptId) else add(receiptId)
        }
    }
    
    fun clearSelection() {
        _selectedReceiptIds.value = emptySet()
    }

    fun setFamilyName(name: String) {
        _familyName.value = name
        sharedPreferences.edit().putString(KEY_FAMILY_NAME, name).apply()
    }

    fun addReceipt(uri: Uri) {
        viewModelScope.launch {
            try {
                _isGenerating.value = true // Reusing loading state
                // 1. Parse PDF
                val parsed = withContext(Dispatchers.IO) {
                    contentResolver.openInputStream(uri)?.use { 
                        pdfParser.parse(it)
                    }
                }

                if (parsed == null) {
                    _error.value = "Failed to parse PDF"
                    return@launch
                }

                // 2. Get filename
                val fileName = getFileName(uri) ?: "unknown.pdf"

                // 3. Add to Repo (Repo handles file copy)
                // We need to modify repository to accept details
                // But current repo addReceipt takes flat args.
                // We should update repo to take the details too.
                
                // Calculating total amount
                val totalAmount = parsed.details.sumOf { it.amount }
                // Assuming "Sitter Name" is consistent, take first.
                val sitterName = parsed.details.firstOrNull()?.sitterName ?: "Unknown"

                // We need to insert details.
                // Repository update needed.
                // For now, I'll assume I update Repository to return the inserted ID, then insert details?
                // Or update addReceipt to take details.
                
                // Let's call a new method on Repository or update existing.
                // I'll update Repository in next step.
                
                // Placeholder call - will fail until Repo updated
                receiptRepository.addReceiptWithDetails(
                    uri = uri,
                    originalFileName = fileName,
                    year = parsed.year,
                    month = parsed.month,
                    amount = totalAmount,
                    sitterName = sitterName,
                    details = parsed.details.map {
                        ReceiptDetailEntity(
                            receiptId = 0, // Will be set by Repo
                            year = it.year,
                            month = it.month,
                            day = it.day,
                            startTime = it.startTime,
                            endTime = it.endTime,
                            sitterName = it.sitterName,
                            childName = it.childName,
                            amount = it.amount
                        )
                    }
                )
                
                _error.value = null
            } catch (e: Exception) {
                _error.value = "Error adding receipt: ${e.message}"
                e.printStackTrace()
            } finally {
                _isGenerating.value = false
            }
        }
    }
    
    private fun getFileName(uri: Uri): String? {
        var result: String? = null
        if (uri.scheme == "content") {
            val cursor = contentResolver.query(uri, null, null, null, null)
            try {
                if (cursor != null && cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) {
                        result = cursor.getString(index)
                    }
                }
            } finally {
                cursor?.close()
            }
        }
        if (result == null) {
            result = uri.path
            val cut = result?.lastIndexOf('/')
            if (cut != null && cut != -1) {
                result = result?.substring(cut + 1)
            }
        }
        return result
    }

    fun deleteSelected() {
        viewModelScope.launch {
            try {
                val idsToDelete = _selectedReceiptIds.value.toList()
                if (idsToDelete.isNotEmpty()) {
                    receiptRepository.deleteReceiptsByIds(idsToDelete)
                    _selectedReceiptIds.value = emptySet()
                }
            } catch (e: Exception) {
                _error.value = "Error deleting receipts: ${e.message}"
            }
        }
    }
}
