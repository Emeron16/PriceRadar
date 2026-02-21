//
//  Receipt.swift
//  PriceRadar
//
//  Complete receipt model with OCR metadata and store matching
//

import Foundation
import FirebaseFirestore

struct Receipt: Identifiable, Codable {
    let id: String  // UUID for grouping price submissions
    let userId: String
    let merchantName: String?     // From OCR (e.g., "Walmart Supercenter")
    let merchantAddress: String?  // From OCR
    let date: Date?               // Purchase date from OCR
    let totalAmount: Double?      // Total from receipt
    let totalTax: Double?         // Tax amount from receipt
    var lineItems: [ReceiptLineItem]

    // Store matching
    var matchedStore: Store?      // MapKit matched store
    var storeMatchingConfidence: StoreMatchConfidence

    // Upload metadata
    let uploadDate: Date
    let ocrProcessingTime: TimeInterval  // Performance tracking

    enum StoreMatchConfidence: String, Codable {
        case exact        // Name + location match within 1km
        case nameOnly     // Name matches, location uncertain
        case userSelected // User manually selected store
        case none         // No match found
    }

    // CodingKeys to handle Store's special encoding
    enum CodingKeys: String, CodingKey {
        case id, userId, merchantName, merchantAddress, date
        case totalAmount, totalTax, lineItems
        case storeMatchingConfidence, uploadDate, ocrProcessingTime
        // matchedStore is excluded (transient, not persisted)
    }
}

// MARK: - Convenience Initializers

extension Receipt {
    /// Create from OCR prediction
    init(
        prediction: ReceiptPrediction,
        userId: String,
        lineItems: [ReceiptLineItem],
        matchedStore: Store?,
        storeConfidence: StoreMatchConfidence,
        processingTime: TimeInterval
    ) {
        self.id = UUID().uuidString
        self.userId = userId
        self.merchantName = prediction.supplier_name?.value
        self.merchantAddress = prediction.supplier_address?.value
        self.date = Self.parseDate(prediction.date?.value)
        self.totalAmount = prediction.total_amount?.value
        self.totalTax = prediction.total_tax?.value
        self.lineItems = lineItems
        self.matchedStore = matchedStore
        self.storeMatchingConfidence = storeConfidence
        self.uploadDate = Date()
        self.ocrProcessingTime = processingTime
    }

    /// Parse date from OCR string (supports multiple formats)
    private static func parseDate(_ dateString: String?) -> Date? {
        guard let dateStr = dateString else { return nil }

        let formatters: [(String, DateFormatter)] = [
            ("yyyy-MM-dd", {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                return f
            }()),
            ("MM/dd/yyyy", {
                let f = DateFormatter()
                f.dateFormat = "MM/dd/yyyy"
                return f
            }()),
            ("dd/MM/yyyy", {
                let f = DateFormatter()
                f.dateFormat = "dd/MM/yyyy"
                return f
            }()),
            ("yyyy/MM/dd", {
                let f = DateFormatter()
                f.dateFormat = "yyyy/MM/dd"
                return f
            }())
        ]

        for (_, formatter) in formatters {
            if let date = formatter.date(from: dateStr) {
                return date
            }
        }

        return nil
    }
}

// MARK: - Helpers

extension Receipt {
    /// Count of items with successfully matched barcodes
    var matchedItemsCount: Int {
        lineItems.filter { $0.matchedBarcode != nil }.count
    }

    /// Count of total items extracted from OCR
    var totalItemsCount: Int {
        lineItems.count
    }

    /// Matching success rate (0.0 to 1.0)
    var matchingSuccessRate: Double {
        guard totalItemsCount > 0 else { return 0.0 }
        return Double(matchedItemsCount) / Double(totalItemsCount)
    }
}
