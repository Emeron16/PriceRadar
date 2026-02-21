//
//  ReceiptLineItem.swift
//  PriceRadar
//
//  Individual receipt item with product matching metadata
//

import Foundation

struct ReceiptLineItem: Identifiable, Codable {
    let id: String
    let description: String       // Raw text from OCR (e.g., "COCA COLA 12OZ")
    var quantity: Double
    var unitPrice: Double?
    var totalPrice: Double

    // Product matching
    var matchedBarcode: String?   // Linked product barcode from OFF
    var matchedProduct: Product?  // Full product details
    var matchingConfidence: MatchingConfidence

    // User editing
    var userEdited: Bool

    enum MatchingConfidence: String, Codable {
        case high      // Exact product match found (90%+ confidence)
        case medium    // Possible match found (60-89% confidence)
        case low       // Generic match (30-59% confidence)
        case none      // No match found
    }
}

// MARK: - Convenience Initializers

extension ReceiptLineItem {
    /// Create from OCR prediction
    init(from prediction: LineItemPrediction, index: Int) {
        let quantity = prediction.quantity ?? 1.0
        let totalAmount = prediction.total_amount ?? 0.0
        let unitPrice = prediction.unit_price ?? (totalAmount / quantity)

        self.init(
            id: "\(UUID().uuidString)_\(index)",
            description: prediction.description ?? "Unknown Item",
            quantity: quantity,
            unitPrice: unitPrice,
            totalPrice: totalAmount,
            matchedBarcode: nil,
            matchedProduct: nil,
            matchingConfidence: .none,
            userEdited: false
        )
    }
}
