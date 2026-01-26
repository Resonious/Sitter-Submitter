package dev.baillie.sittersubmitter.ui

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
            HomeViewModel(
                sitterSubmitterApplication().container.receiptRepository,
                sitterSubmitterApplication().container.pdfParser,
                sitterSubmitterApplication().applicationContext.contentResolver
            )
        }
        initializer {
            GenerateViewModel(
                this.createSavedStateHandle(),
                sitterSubmitterApplication().container.receiptRepository,
                sitterSubmitterApplication().container.reportGenerator
            )
        }
    }
}

fun CreationExtras.sitterSubmitterApplication(): SitterSubmitterApplication =
    (this[ViewModelProvider.AndroidViewModelFactory.APPLICATION_KEY] as SitterSubmitterApplication)
