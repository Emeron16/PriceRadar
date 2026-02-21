//
//  ReceiptOCRResult.swift
//  PriceRadar
//
//  Shared OCR result models used by VisionReceiptService and the rest of the app.
//

import Foundation

// MARK: - Shared Receipt Prediction (used by ViewModel, Receipt, ReceiptLineItem)

struct ReceiptPrediction: Codable {
    let supplier_name: ReceiptField?
    let supplier_address: ReceiptField?
    let date: ReceiptField?
    let time: ReceiptField?
    let total_amount: ReceiptAmountField?
    let total_tax: ReceiptAmountField?
    let line_items: [LineItemPrediction]?
}

struct LineItemPrediction: Codable {
    let description: String?
    let quantity: Double?
    let total_amount: Double?
    let unit_price: Double?
}

struct ReceiptField: Codable {
    let value: String?
}

struct ReceiptAmountField: Codable {
    let value: Double?
}

// MARK: - OCR Errors

enum ReceiptOCRError: LocalizedError {
    case imageCompressionFailed
    case networkError
    case apiError(statusCode: Int)
    case invalidResponse
    case noItemsDetected

    var errorDescription: String? {
        switch self {
        case .imageCompressionFailed:
            return "Failed to process receipt image. Try a clearer photo."
        case .networkError:
            return "Network connection failed. Check your internet connection."
        case .apiError(let code):
            return "OCR error (HTTP \(code)). Try again later."
        case .invalidResponse:
            return "Could not read the receipt image. Try a clearer, well-lit photo."
        case .noItemsDetected:
            return "No items found on receipt. You can still select a store and submit."
        }
    }
}
