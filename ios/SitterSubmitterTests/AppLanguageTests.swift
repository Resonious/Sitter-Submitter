import Foundation
import Testing

/// The UI is Japanese only. iOS shows its own text in the app (Cancel and Close buttons, system error messages)
/// in the app's language rather than the device's, so the app has to declare Japanese for those to match. Run on
/// a simulator set to English, this checks they would be Japanese there too.
struct AppLanguageTests {
    @Test func usesJapaneseWhateverTheDeviceLanguage() {
        #expect(Bundle.main.developmentLocalization == "ja")
        #expect(Bundle.main.preferredLocalizations == ["ja"])
        // For example, errors from iOS that the app shows as they are, like failing to read a picked PDF.
        let systemError = CocoaError(.fileReadNoSuchFile).localizedDescription
        #expect(systemError.unicodeScalars.contains { (0x3040...0x309F).contains($0.value) }, "\(systemError)") // Hiragana
    }
}
