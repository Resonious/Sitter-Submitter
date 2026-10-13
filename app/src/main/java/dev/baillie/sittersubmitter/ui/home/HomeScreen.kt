package dev.baillie.sittersubmitter.ui.home

import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import dev.baillie.sittersubmitter.ui.AppViewModelProvider

@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    modifier: Modifier = Modifier,
    viewModel: HomeViewModel = viewModel(factory = AppViewModelProvider.Factory),
    onGenerateClick: () -> Unit
) {
    val uiState by viewModel.uiState.collectAsState()
    val context = LocalContext.current

    val launcher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument(),
        onResult = { uri: Uri? ->
            uri?.let { viewModel.addReceipt(it) }
        }
    )

    BackHandler(enabled = uiState.selectedReceiptIds.isNotEmpty()) {
        viewModel.clearSelection()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    if (uiState.selectedReceiptIds.isNotEmpty()) {
                        Text("${uiState.selectedReceiptIds.size}件選択中")
                    } else {
                        Text("シッター申請")
                    }
                },
                actions = {
                    if (uiState.selectedReceiptIds.isNotEmpty()) {
                        IconButton(onClick = { viewModel.deleteSelected() }) {
                            Icon(Icons.Default.Delete, contentDescription = "選択した領収書を削除")
                        }
                    }
                }
            )
        },
        floatingActionButton = {
            if (uiState.selectedReceiptIds.isNotEmpty()) {
                ExtendedFloatingActionButton(
                    onClick = onGenerateClick,
                    icon = { Icon(Icons.Default.CheckCircle, contentDescription = null) },
                    text = { Text("内訳表を作成（${uiState.selectedReceiptIds.size}）") }
                )
            } else {
                FloatingActionButton(
                    onClick = { launcher.launch(arrayOf("application/pdf")) }
                ) {
                    Icon(Icons.Default.Add, contentDescription = "領収書を追加")
                }
            }
        }
    ) { innerPadding ->
        Column(modifier = modifier.padding(innerPadding)) {
            OutlinedTextField(
                value = uiState.familyName,
                onValueChange = { viewModel.setFamilyName(it) },
                label = { Text("姓") },
                singleLine = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp)
            )

            if (uiState.years.isEmpty()) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        "領収書がありません。\n＋をタップしてPDFを追加してください。",
                        modifier = Modifier.padding(horizontal = 16.dp),
                        textAlign = TextAlign.Center
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(bottom = 80.dp)
                ) {
                    uiState.years.forEach { yearData ->
                    stickyHeader {
                        Text(
                            text = "${yearData.year}年",
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(MaterialTheme.colorScheme.surfaceVariant)
                                .padding(8.dp),
                            style = MaterialTheme.typography.titleMedium
                        )
                    }
                    
                    yearData.months.forEach { monthData ->
                        item {
                            Text(
                                text = "${monthData.month}月",
                                modifier = Modifier.padding(start = 16.dp, top = 8.dp, bottom = 4.dp),
                                style = MaterialTheme.typography.titleSmall,
                                color = MaterialTheme.colorScheme.primary
                            )
                        }
                        items(monthData.receipts) { receipt ->
                            ReceiptItem(
                                receipt = receipt,
                                isSelected = uiState.selectedReceiptIds.contains(receipt.id),
                                onClick = { viewModel.toggleSelection(receipt.id) }
                            )
                        }
                    }
                }
            }
        }

            if (uiState.isGenerating) {
                Box(
                    modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.3f)),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator()
                }
            }

            if (uiState.error != null) {
                AlertDialog(
                    onDismissRequest = { /* Clear error? */ },
                    confirmButton = { TextButton(onClick = { /* Clear error */ }) { Text("OK") } },
                    title = { Text("エラー") },
                    text = { Text(uiState.error!!) }
                )
            }
        }
    }
}

@Composable
fun ReceiptItem(
    receipt: ReceiptDisplayItem,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .clickable(onClick = onClick),
        colors = CardDefaults.cardColors(
            containerColor = if (isSelected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface
        )
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = receipt.childNames.ifEmpty { "不明" },
                    style = MaterialTheme.typography.bodyLarge
                )
                Text(
                    text = "¥${receipt.amount} • ${receipt.sitterNames}",
                    style = MaterialTheme.typography.bodyMedium
                )
                Text(
                    text = receipt.originalFileName,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            if (isSelected) {
                Icon(Icons.Default.CheckCircle, contentDescription = "選択済み", tint = MaterialTheme.colorScheme.primary)
            }
        }
    }
}
