//
//  ReceiptReviewView.swift
//  PriceRadar
//
//  View for reviewing extracted receipt items before submission
//

import SwiftUI

struct ReceiptReviewView: View {
    @ObservedObject var viewModel: ReceiptScannerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showStoreSelector = false
    @State private var showSuccessAlert = false

    var body: some View {
        Form {
            // Receipt metadata section
            if let receipt = viewModel.receipt {
                receiptDetailsSection(receipt)
            }

            // Store selection section
            storeSelectionSection

            // Line items section
            lineItemsSection

            // Points preview section
            pointsPreviewSection

            // Submit button section
            submitButtonSection
        }
        .navigationTitle("Review Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showStoreSelector) {
            // Reuse StorePickerView from PriceSubmissionView
            StorePickerView(
                stores: [],  // Empty - relies on MapKit search
                selectedStore: $viewModel.selectedStore
            )
        }
        .alert("Success!", isPresented: $showSuccessAlert) {
            Button("Great!") {
                dismiss()
            }
        } message: {
            let submittedCount = viewModel.submittableItemsCount
            let points = viewModel.calculatePoints(itemCount: submittedCount)
            Text("Submitted \(submittedCount) items and earned \(points) points!")
        }
    }

    // MARK: - Receipt Details Section

    private func receiptDetailsSection(_ receipt: Receipt) -> some View {
        Section("Receipt Details") {
            if let merchant = receipt.merchantName {
                HStack {
                    Text("Merchant")
                    Spacer()
                    Text(merchant)
                        .foregroundColor(.secondary)
                }
            }

            if let date = receipt.date {
                HStack {
                    Text("Date")
                    Spacer()
                    Text(date, style: .date)
                        .foregroundColor(.secondary)
                }
            }

            if let total = receipt.totalAmount {
                HStack {
                    Text("Total")
                    Spacer()
                    Text(Constants.formatPrice(total))
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Store Selection Section

    private var storeSelectionSection: some View {
        Section("Store Location") {
            if let store = viewModel.selectedStore {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.name)
                            .font(.body)
                            .fontWeight(.medium)
                        Text(store.address)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let distance = store.distanceInMiles {
                            Text(Constants.formatDistance(distance))
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }

                    Spacer()

                    Button("Change") {
                        showStoreSelector = true
                    }
                    .font(.caption)
                }
            } else {
                Button(action: { showStoreSelector = true }) {
                    HStack {
                        Image(systemName: "building.2")
                            .foregroundColor(.orange)
                        Text("Select Store (Required)")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Line Items Section

    private var lineItemsSection: some View {
        Section {
            ForEach($viewModel.editableLineItems) { $item in
                ReceiptLineItemRow(item: $item)
            }
            .onDelete { indexSet in
                viewModel.editableLineItems.remove(atOffsets: indexSet)
            }
        } header: {
            HStack {
                Text("Items (\(viewModel.editableLineItems.count))")
                Spacer()
                let matchedCount = viewModel.submittableItemsCount
                Text("\(matchedCount) matched")
                    .font(.caption)
                    .foregroundColor(matchedCount > 0 ? .green : .orange)
            }
        } footer: {
            Text("Only items with matched products will be submitted")
                .font(.caption)
        }
    }

    // MARK: - Points Preview Section

    private var pointsPreviewSection: some View {
        Section {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)

                let submittableCount = viewModel.submittableItemsCount
                let points = viewModel.calculatePoints(itemCount: submittableCount)

                if submittableCount > 0 {
                    Text("You'll earn \(points) points")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("No items to submit yet")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    // MARK: - Submit Button Section

    private var submitButtonSection: some View {
        Section {
            Button(action: submitReceipt) {
                HStack {
                    Spacer()
                    if viewModel.isProcessing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Submit Receipt")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.vertical, 8)
            }
            .listRowBackground(viewModel.isFormValid ? Color.green : Color.gray)
            .disabled(!viewModel.isFormValid || viewModel.isProcessing)
        }
    }

    // MARK: - Actions

    private func submitReceipt() {
        Task {
            let success = await viewModel.submitReceipt()
            if success {
                showSuccessAlert = true
            }
        }
    }
}
