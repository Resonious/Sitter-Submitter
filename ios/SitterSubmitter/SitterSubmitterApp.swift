import SwiftUI

@main
struct SitterSubmitterApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
    }
}

/// One window's navigation: the home screen, with the generate screen pushed on top.
struct RootView: View {
    let container: AppContainer

    @State private var path: [GenerateRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(viewModel: container.homeViewModel) { receiptIds in
                path.append(GenerateRoute(receiptIds: receiptIds))
            }
            .navigationDestination(for: GenerateRoute.self) { route in
                GenerateView(viewModel: container.makeGenerateViewModel(receiptIds: route.receiptIds))
            }
        }
        // A PDF opened with the app (Files, Mail, the share sheet…): add it, on the home screen.
        .onOpenURL { url in
            path.removeAll()
            Task {
                await IncomingFile.withBackgroundTime {
                    await container.homeViewModel.addReceipt(from: url)
                }
                IncomingFile.removeIfInboxCopy(url)
            }
        }
    }
}

struct GenerateRoute: Hashable {
    let receiptIds: [Int64]
}

/// Creates the app's long-lived dependencies, like the Android `AppContainer`.
@MainActor
final class AppContainer {
    let receiptRepository: ReceiptRepository
    let pdfParser = PdfParser.configured()
    let reportGenerator = ReportGenerator.bundled()
    let userDefaults = UserDefaults.standard
    let homeViewModel: HomeViewModel

    init() {
        do {
            receiptRepository = try ReceiptRepository.makeDefault()
        } catch {
            fatalError("Could not open the receipts database: \(error)")
        }
        homeViewModel = HomeViewModel(receiptRepository: receiptRepository, pdfParser: pdfParser, userDefaults: userDefaults)
    }

    func makeGenerateViewModel(receiptIds: [Int64]) -> GenerateViewModel {
        GenerateViewModel(
            receiptIds: receiptIds,
            receiptRepository: receiptRepository,
            reportGenerator: reportGenerator,
            userDefaults: userDefaults,
            outputDirectory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        )
    }
}
