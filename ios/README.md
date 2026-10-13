# Sitter Submitter for iOS

A SwiftUI port of the Android app in this repository, with the same screens and behavior:

- **Home** (シッター申請): receipts grouped by year and month. Tap receipts to select them, then **内訳表を作成** (create the breakdown form). The trash button deletes the selection and ✕ clears it (Android uses the back button for that).
- **Adding receipts**: the **+** button picks a PDF; PDFs can also be opened in or shared to the app from Files, Mail, Safari and so on. OpenAI reads the sessions out of the PDF, and the PDF and the sessions are stored in SQLite.
- **内訳表の作成** (generate submission): one card per child. Generating fills in the official template (`SitterSubmitter/Resources/template.xlsx`) and previews it, from where it can be printed, saved or opened in Numbers or Excel.

Like the Android app, the UI is Japanese only. The project's development language is Japanese as well, so the buttons and messages iOS adds to the app (Cancel, Close, system error descriptions) are Japanese whatever the device language. The document picker's contents are the exception: iOS draws them in another process, in the device's language.

## Setup

1. Copy `Config/Secrets.xcconfig.example` to `Config/Secrets.xcconfig` (it's git-ignored) and set `OPENAI_API_KEY`, the same key the Android app reads from `local.properties`. To run on a device, also set `DEVELOPMENT_TEAM` there or pick a team in Xcode.
2. Open `SitterSubmitter.xcodeproj` in Xcode 26 or later and run the `SitterSubmitter` scheme. The app supports iOS 17 and later.

## Tests

Press ⌘U in Xcode, or run this with the name of any iOS 17+ simulator:

```sh
xcodebuild test -project ios/SitterSubmitter.xcodeproj -scheme SitterSubmitter \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

`PdfParserLiveTests` send the sample receipts in `docs/` to OpenAI, so they only run when an API key is configured. Everything else runs offline. One test also checks that the prompt and model match the Android `PdfParser.kt`.

## Differences from the Android app

- The year and month cells of the generated spreadsheet keep the template's formatting, and sessions beyond the template's 28 rows are left out without touching the totals below the table (Android overwrites the totals' labels in that case).
- The spreadsheet opens in QuickLook, which shows the formula results saved in the file instead of recalculating them. So the app saves the results of the template's automatic columns too, and marks the file for Excel to recalculate when opened.
- The error dialog can be dismissed, and errors while generating a spreadsheet are shown.
- Stored PDFs are referenced relative to the app's container, since iOS changes the container's path between installs.
