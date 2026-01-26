# Sitter Submitter

This project is meant to be an Android app to generate government support forms for babysitter reimbursement. In essence, it takes in multiple receipt PDFs from babysitter services and produces an output PDF in the government submission format, which can then be printed and submitted by hand.

## Screens

Here we will outline the 3 screens this app needs. The generated boilerplate app has a navigator which might not be necessary, so feel free to delete it. There may be interstitial screens necessary that were not outlined here; don't take this guide too literally.

### Main Screen

See docs/sitter-submitter-mockup.png for a mockup of the main screen. Textual explanation: an infinite scrolling view of every month of every year. Each year is a header followed by a row for each month. Inside each month row is any number of receipts added during that month and a button to add another.

If the user taps a receipt, it "selects" it. This is multi-select; the user can select as many as they'd like from any month.

When receipts are selected, a button appears for generating a submission, leading to the "Generate Submission" screen.

### Generate Submission

Should show a breakdown of all the numbers that were parsed out of the input PDFs as well as the output numbers that will appear in the output PDF.

Include a button for generating the output. This will take the official xlsx file, input the right numbers into the right fields, then save it as a new XLSX and "open" it.

An image file with a hand-filled output file can be found at docs/example.jpg. The numbers in this example can be found at docs/example-output-data.csv (sorry it's not using the official xlsx format).

The official XLSX template is docs/official-output-template.xlsx - copy this to a more appropriate location to embed it into the app.

### Open PDF

The app will have 2 flows for adding PDFs:

1. The "add" button on the main screen, and
2. The ability to "open with" this app when tapping on a PDF file elsewhere in the OS (this page).

When the user opens a PDF with this app, the app will try to parse out which year and month the PDF should be added to. Present that info to the user, then provide a button to add it. Once added navigate to the home screen.

## Technical guidance

* Use Jetpack Compose.
* Write ViewModels and unit tests for them. Especially the PDF parsing logic should be thoroughly unit tested.
* Use SQLite to store data.
* For each added PDF, store both the original PDF and the parsed out data from it.

### Adding PDFs: parsing

Examples of the PDFs that will be uploaded can be found at `docs/「はじめて」を応援する _ ポピンズシッター(5).pdf` and `docs/「はじめて」を応援する _ ポピンズシッター.pdf`. These come from the "poppins" babysitter service. In the future, we *might* want to support other services, so build this part of the code with that in mind. For now, it's just poppins.

If there are any problems parsing the PDF, tell the user what went wrong.
