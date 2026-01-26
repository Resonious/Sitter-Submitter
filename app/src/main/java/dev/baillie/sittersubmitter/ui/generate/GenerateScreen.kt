package dev.baillie.sittersubmitter.ui.generate

import android.content.Intent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import dev.baillie.sittersubmitter.ui.AppViewModelProvider

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GenerateScreen(
    viewModel: GenerateViewModel = viewModel(factory = AppViewModelProvider.Factory),
    onBack: () -> Unit
) {
    val uiState by viewModel.uiState.collectAsState()
    val context = LocalContext.current

    LaunchedEffect(uiState.generatedFile) {
        uiState.generatedFile?.let { file ->
            // Open file intent
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            context.startActivity(intent)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Generate Submission") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        },
        bottomBar = {
            Button(
                onClick = { 
                    viewModel.generateReport(context.externalCacheDir ?: context.cacheDir) 
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                enabled = !uiState.isLoading && uiState.details.isNotEmpty()
            ) {
                Text(if (uiState.isLoading) "Generating..." else "Generate XLSX")
            }
        }
    ) { innerPadding ->
        if (uiState.isLoading && uiState.details.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            Column(modifier = Modifier.padding(innerPadding)) {
                Text(
                    text = "Total Amount: ¥${uiState.totalAmount}",
                    style = MaterialTheme.typography.headlineSmall,
                    modifier = Modifier.padding(16.dp)
                )
                
                Text(
                    text = "Details included:",
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.padding(horizontal = 16.dp)
                )

                LazyColumn(
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(16.dp)
                ) {
                    items(uiState.details) { detail ->
                        ListItem(
                            headlineContent = { Text("${detail.year}/${detail.month}/${detail.day}") },
                            supportingContent = { Text("${detail.startTime} - ${detail.endTime}") },
                            trailingContent = { Text("¥${detail.amount}") }
                        )
                        HorizontalDivider()
                    }
                }
            }
        }
    }
}
