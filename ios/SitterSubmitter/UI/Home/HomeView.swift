import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    let viewModel: HomeViewModel
    let onGenerateClick: ([Int64]) -> Void

    @State private var isPickingPdf = false

    var body: some View {
        VStack(spacing: 0) {
            TextField("姓", text: Binding(get: { viewModel.familyName }, set: { viewModel.setFamilyName($0) }))
                .textFieldStyle(.roundedBorder)
                .textContentType(.familyName)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            if viewModel.years.isEmpty {
                Text("領収書がありません。\n＋をタップしてPDFを追加してください。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                receiptList
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !viewModel.selectedReceiptIds.isEmpty {
                // Android clears the selection with the back button.
                ToolbarItem(placement: .topBarLeading) {
                    Button("選択を解除", systemImage: "xmark") {
                        viewModel.clearSelection()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("選択した領収書を削除", systemImage: "trash", role: .destructive) {
                        Task { await viewModel.deleteSelected() }
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            floatingActionButton
                .padding(16)
        }
        .overlay {
            if viewModel.isGenerating {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }
            }
        }
        .alert("エラー", isPresented: isShowingError) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(verbatim: viewModel.error ?? "")
        }
        .fileImporter(isPresented: $isPickingPdf, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result {
                Task {
                    await IncomingFile.withBackgroundTime {
                        await viewModel.addReceipt(from: url)
                    }
                }
            }
        }
        .task {
            await viewModel.load()
        }
    }

    private var title: String {
        viewModel.selectedReceiptIds.isEmpty ? "シッター申請" : "\(viewModel.selectedReceiptIds.count)件選択中"
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { viewModel.error != nil }, set: { if !$0 { viewModel.dismissError() } })
    }

    private var receiptList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(viewModel.years) { yearData in
                    Section {
                        ForEach(yearData.months) { monthData in
                            Text(verbatim: "\(monthData.month)月")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.leading, 16)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                            ForEach(monthData.receipts) { receipt in
                                ReceiptItem(receipt: receipt, isSelected: viewModel.isSelected(receipt.id)) {
                                    viewModel.toggleSelection(receipt.id)
                                }
                            }
                        }
                    } header: {
                        Text(verbatim: "\(yearData.year)年")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(.bar)
                    }
                }
            }
            .padding(.bottom, 80) // Keep the last receipt clear of the floating button
        }
    }

    @ViewBuilder
    private var floatingActionButton: some View {
        if viewModel.selectedReceiptIds.isEmpty {
            Button {
                isPickingPdf = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.accentColor, in: Circle())
                    .shadow(radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("領収書を追加")
        } else {
            Button {
                onGenerateClick(viewModel.selectedReceiptIds)
            } label: {
                Label("内訳表を作成（\(viewModel.selectedReceiptIds.count)）", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 56)
                    .background(Color.accentColor, in: Capsule())
                    .shadow(radius: 4, y: 2)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ReceiptItem: View {
    let receipt: ReceiptDisplayItem
    let isSelected: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: receipt.childNames.isEmpty ? "不明" : receipt.childNames)
                        .font(.body)
                    Text(verbatim: "\(receipt.amount.formatted(.yen)) • \(receipt.sitterNames)")
                        .font(.subheadline)
                    Text(verbatim: receipt.originalFileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("選択済み")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
