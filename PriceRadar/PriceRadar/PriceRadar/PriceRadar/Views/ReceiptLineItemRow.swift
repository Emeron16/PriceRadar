//
//  ReceiptLineItemRow.swift
//  PriceRadar
//
//  Row component for displaying receipt line item with matching status
//

import SwiftUI

struct ReceiptLineItemRow: View {
    @Binding var item: ReceiptLineItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // OCR description
            Text(item.description)
                .font(.body)
                .fontWeight(.medium)

            // Matched product info
            if let product = item.matchedProduct {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(confidenceColor)
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(product.name)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if let brand = product.brand, !brand.isEmpty {
                            Text(brand)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.orange)
                        .font(.caption)

                    Text("No product match found - will be skipped")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Spacer()
                }
            }

            // Price info
            HStack {
                if item.quantity > 1 {
                    Text("\(String(format: "%.0f", item.quantity))x")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let unitPrice = item.unitPrice {
                    Text(Constants.formatPrice(unitPrice))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("each")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(Constants.formatPrice(item.totalPrice))
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private var confidenceColor: Color {
        switch item.matchingConfidence {
        case .high:
            return .green
        case .medium:
            return .blue
        case .low:
            return .orange
        case .none:
            return .gray
        }
    }
}
