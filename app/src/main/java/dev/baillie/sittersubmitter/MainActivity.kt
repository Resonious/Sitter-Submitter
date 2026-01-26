package dev.baillie.sittersubmitter

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import dev.baillie.sittersubmitter.ui.AppViewModelProvider
import dev.baillie.sittersubmitter.ui.generate.GenerateScreen
import dev.baillie.sittersubmitter.ui.home.HomeScreen
import dev.baillie.sittersubmitter.ui.home.HomeViewModel

import dev.baillie.sittersubmitter.ui.theme.SitterSubmitterTheme

class MainActivity : ComponentActivity() {
    private var pendingPdfUri: Uri? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Only capture URI on fresh launch, not on recreation
        if (savedInstanceState == null) {
            pendingPdfUri = extractPdfUri(intent)
        }

        enableEdgeToEdge()
        setContent {
            SitterSubmitterTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    SitterApp(
                        pendingPdfUri = pendingPdfUri,
                        onPdfConsumed = { pendingPdfUri = null }
                    )
                }
            }
        }
    }

    private fun extractPdfUri(intent: Intent?): Uri? {
        if (intent == null) return null

        return when (intent.action) {
            Intent.ACTION_VIEW -> {
                if (intent.type == "application/pdf") intent.data else null
            }
            Intent.ACTION_SEND -> {
                if (intent.type == "application/pdf") {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                } else null
            }
            else -> null
        }
    }
}

@Composable
fun SitterApp(
    pendingPdfUri: Uri?,
    onPdfConsumed: () -> Unit
) {
    val navController = rememberNavController()

    NavHost(navController = navController, startDestination = "home") {
        composable("home") {
            val homeViewModel: HomeViewModel = viewModel(factory = AppViewModelProvider.Factory)

            // Handle pending PDF URI once
            LaunchedEffect(pendingPdfUri) {
                if (pendingPdfUri != null) {
                    homeViewModel.addReceipt(pendingPdfUri)
                    onPdfConsumed()
                }
            }

            HomeScreen(
                onGenerateClick = {
                    val selectedIds = homeViewModel.uiState.value.selectedReceiptIds.joinToString(",")
                    navController.navigate("generate/$selectedIds")
                }
            )
        }

        composable(
            "generate/{ids}",
            arguments = listOf(navArgument("ids") { type = NavType.StringType })
        ) {
            GenerateScreen(
                onBack = { navController.popBackStack() }
            )
        }
    }
}
