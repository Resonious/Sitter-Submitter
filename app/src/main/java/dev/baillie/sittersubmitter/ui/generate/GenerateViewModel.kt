package dev.baillie.sittersubmitter.ui.generate

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

data class GenerateUiState(
    val isLoading: Boolean = true,
    val details: List<ReceiptDetailEntity> = emptyList(),
    val totalAmount: Int = 0,
    val generatedFile: File? = null,
    val error: String? = null
)

class GenerateViewModel(
    savedStateHandle: SavedStateHandle,
    private val receiptRepository: ReceiptRepository,
    private val reportGenerator: ReportGenerator
) : ViewModel() {

    private val _uiState = MutableStateFlow(GenerateUiState())
    val uiState: StateFlow<GenerateUiState> = _uiState.asStateFlow()

    init {
        val idsString = savedStateHandle.get<String>("ids")
        if (idsString != null) {
            val ids = idsString.split(",").mapNotNull { it.toIntOrNull() }
            loadDetails(ids)
        } else {
            _uiState.value = _uiState.value.copy(isLoading = false, error = "No receipts selected")
        }
    }

    private fun loadDetails(ids: List<Int>) {
        viewModelScope.launch {
            try {
                // Get receipts, then details.
                // Repo method getReceiptsByIds gets entities.
                // I need details.
                // I should add getDetailsForReceipts to Repo or just iterate.
                // Iterate for now.
                
                val allDetails = mutableListOf<ReceiptDetailEntity>()
                for (id in ids) {
                    val details = receiptRepository.getDetailsForReceipt(id) // Need to expose this in Repo
                    allDetails.addAll(details)
                }
                
                _uiState.value = GenerateUiState(
                    isLoading = false,
                    details = allDetails,
                    totalAmount = allDetails.sumOf { it.amount }
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isLoading = false, error = e.message)
            }
        }
    }

    fun generateReport(outputDir: File) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true)
            try {
                val file = withContext(Dispatchers.IO) {
                    val outputFile = File(outputDir, "submission_${System.currentTimeMillis()}.xlsx")
                    reportGenerator.generate(_uiState.value.details, outputFile)
                    outputFile
                }
                _uiState.value = _uiState.value.copy(isLoading = false, generatedFile = file)
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isLoading = false, error = "Generation failed: ${e.message}")
            }
        }
    }
}
