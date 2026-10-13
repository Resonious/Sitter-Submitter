import QuickLook
import SwiftUI

struct GenerateView: View {
    @State private var viewModel: GenerateViewModel

    init(viewModel: GenerateViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.children.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(Array(viewModel.children.enumerated()), id: \.offset) { _, childData in
                            ChildCard(childData: childData, isLoading: viewModel.isLoading) {
                                Task { await viewModel.generateReport(forChild: childData.childName) }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Generate Submission")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
        // "Open" the spreadsheet, as Android does with ACTION_VIEW. The preview can share, print or
        // open it in Numbers/Excel.
        .quickLookPreview($viewModel.generatedFileURL)
        .alert("Error", isPresented: isShowingError) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(verbatim: viewModel.error ?? "")
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { viewModel.error != nil }, set: { if !$0 { viewModel.dismissError() } })
    }
}

private struct ChildCard: View {
    let childData: ChildData
    let isLoading: Bool
    let onGenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: childData.childName)
                .font(.title2)
            Text(verbatim: "\(childData.details.count) sessions • ¥\(childData.totalAmount)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(childData.details.prefix(3))) { detail in
                    Text(verbatim: "\(detail.year)/\(detail.month)/\(detail.day) \(detail.startTime)-\(detail.endTime)")
                        .font(.footnote)
                }
                if childData.details.count > 3 {
                    Text(verbatim: "... and \(childData.details.count - 3) more")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)

            Button(action: onGenerate) {
                Text(verbatim: isLoading ? "Generating..." : "Generate XLSX for \(childData.childName)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLoading)
            .padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
