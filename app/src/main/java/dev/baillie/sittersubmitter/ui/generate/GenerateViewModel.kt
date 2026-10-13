package dev.baillie.sittersubmitter.ui.generate

import android.content.SharedPreferences
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.baillie.sittersubmitter.data.db.ReceiptDetailEntity
import dev.baillie.sittersubmitter.data.repository.ReceiptRepository
import dev.baillie.sittersubmitter.domain.report.ReportGenerator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

data class ChildData(
    val childName: String,
    val details: List<ReceiptDetailEntity>,
    val totalAmount: Int
)

data class GenerateUiState(
    val isLoading: Boolean = true,
    val children: List<ChildData> = emptyList(),
    val generatedFile: File? = null,
    val generatedChildName: String? = null,
    val error: String? = null
)

class GenerateViewModel(
    savedStateHandle: SavedStateHandle,
    private val receiptRepository: ReceiptRepository,
    private val reportGenerator: ReportGenerator,
    private val sharedPreferences: SharedPreferences
) : ViewModel() {

    companion object {
        private const val KEY_FAMILY_NAME = "family_name"
    }

    private val _uiState = MutableStateFlow(GenerateUiState())
    val uiState: StateFlow<GenerateUiState> = _uiState.asStateFlow()

    init {
        val idsString = savedStateHandle.get<String>("ids")
        if (idsString != null) {
            val ids = idsString.split(",").mapNotNull { it.toIntOrNull() }
            loadDetails(ids)
        } else {
            _uiState.value = _uiState.value.copy(isLoading = false, error = "領収書が選択されていません。")
        }
    }

    private fun loadDetails(ids: List<Int>) {
        viewModelScope.launch {
            try {
                val allDetails = mutableListOf<ReceiptDetailEntity>()
                for (id in ids) {
                    val details = receiptRepository.getDetailsForReceipt(id)
                    allDetails.addAll(details)
                }

                // Group by child name
                val children = allDetails.groupBy { it.childName }
                    .map { (childName, details) ->
                        ChildData(
                            childName = childName.ifEmpty { "不明" },
                            details = details,
                            totalAmount = details.sumOf { it.amount }
                        )
                    }
                    .sortedBy { it.childName }

                _uiState.value = GenerateUiState(
                    isLoading = false,
                    children = children
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    error = listOfNotNull("領収書を読み込めませんでした。", e.message).joinToString("\n")
                )
            }
        }
    }

    fun generateReportForChild(childName: String, outputDir: File) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true)
            try {
                val childData = _uiState.value.children.find { it.childName == childName }
                    ?: throw IllegalArgumentException("お子さまが見つかりません。")

                val file = withContext(Dispatchers.IO) {
                    val familyName = sharedPreferences.getString(KEY_FAMILY_NAME, "") ?: ""
                    val fullName = if (familyName.isNotEmpty()) "$familyName $childName" else childName
                    val safeName = childName.replace(Regex("[^a-zA-Z0-9\\u3040-\\u30FF\\u4E00-\\u9FFF]"), "_")
                    val outputFile = File(outputDir, "利用内容内訳表_${safeName}_${System.currentTimeMillis()}.xlsx")
                    reportGenerator.generate(childData.details, fullName, outputFile)
                    outputFile
                }
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    generatedFile = file,
                    generatedChildName = childName
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    error = listOfNotNull("内訳表を作成できませんでした。", e.message).joinToString("\n")
                )
            }
        }
    }
}
