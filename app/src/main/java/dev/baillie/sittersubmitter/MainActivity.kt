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
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            SitterSubmitterTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    SitterApp(intent = intent)
                }
            }
        }
    }
}

@Composable
fun SitterApp(
    intent: Intent?
) {
    val navController = rememberNavController()
    // We need access to HomeViewModel to add receipt from Intent
    // But HomeViewModel is scoped to HomeScreen usually.
    // However, if we enter via Intent, we want to add it then go to Home.
    // Let's rely on HomeViewModel being the start destination.

    NavHost(navController = navController, startDestination = "home") {
        composable("home") {
            val homeViewModel: HomeViewModel = viewModel(factory = AppViewModelProvider.Factory)
            
            // Handle Intent
            LaunchedEffect(intent) {
                if (intent?.action == Intent.ACTION_VIEW && intent.type == "application/pdf") {
                    val uri = intent.data
                    if (uri != null) {
                        homeViewModel.addReceipt(uri)
                    }
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
