package dev.baillie.sittersubmitter.ui

import android.content.Context
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.CreationExtras
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import dev.baillie.sittersubmitter.SitterSubmitterApplication
import androidx.lifecycle.createSavedStateHandle
import dev.baillie.sittersubmitter.ui.generate.GenerateViewModel
import dev.baillie.sittersubmitter.ui.home.HomeViewModel

object AppViewModelProvider {
    val Factory = viewModelFactory {
        initializer {
            val app = sitterSubmitterApplication()
            HomeViewModel(
                app.container.receiptRepository,
                app.container.pdfParser,
                app.applicationContext.contentResolver,
                app.getSharedPreferences("sitter_submitter_prefs", Context.MODE_PRIVATE)
            )
        }
        initializer {
            val app = sitterSubmitterApplication()
            GenerateViewModel(
                this.createSavedStateHandle(),
                app.container.receiptRepository,
                app.container.reportGenerator,
                app.getSharedPreferences("sitter_submitter_prefs", Context.MODE_PRIVATE)
            )
        }
    }
}

fun CreationExtras.sitterSubmitterApplication(): SitterSubmitterApplication =
    (this[ViewModelProvider.AndroidViewModelFactory.APPLICATION_KEY] as SitterSubmitterApplication)
