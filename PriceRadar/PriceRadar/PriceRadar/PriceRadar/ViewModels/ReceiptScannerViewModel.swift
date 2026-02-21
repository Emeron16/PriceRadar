//
//  ReceiptScannerViewModel.swift
//  PriceRadar
//
//  ViewModel for receipt scanning flow (camera → OCR → matching → submission)
//

import Foundation
import SwiftUI
import Combine
import CoreLocation
import FirebaseAuth

@MainActor
class ReceiptScannerViewModel: ObservableObject {
    @Published var selectedImage: UIImage?
    @Published var isProcessing = false
    @Published var ocrResult: ReceiptPrediction?
    @Published var receipt: Receipt?
    @Published var errorMessage: String?

    // Review state
    @Published var editableLineItems: [ReceiptLineItem] = []
    @Published var selectedStore: Store?
    @Published var showStoreSelector = false

    private let ocrService = VisionReceiptService.shared
    private let matchingService = ReceiptProductMatchingService.shared
    private let locationService = LocationService()

    // MARK: - Public API

    /// Process selected receipt image with OCR and product matching
    func processReceipt() async {
        guard let image = selectedImage else {
            errorMessage = "No image selected"
            return
        }

        isProcessing = true
        errorMessage = nil

        let startTime = Date()

        do {
            // Step 1: OCR extraction
            print("📸 Processing receipt image...")
            let prediction = try await ocrService.processReceipt(image: image)
            ocrResult = prediction

            // Step 2: Convert to ReceiptLineItem models (empty is allowed — store match may still succeed)
            let ocrLineItems = prediction.line_items ?? []
            var lineItems: [ReceiptLineItem] = []

            for (index, item) in ocrLineItems.enumerated() {
                lineItems.append(ReceiptLineItem(from: item, index: index))
            }

            print("📝 Extracted \(lineItems.count) items from receipt")

            // Step 3: Match products in parallel using TaskGroup
            print("🔍 Matching \(lineItems.count) items to products...")
            await withTaskGroup(of: (Int, String?, Product?, ReceiptLineItem.MatchingConfidence).self) { group in
                for (index, item) in lineItems.enumerated() {
                    group.addTask {
                        let (barcode, product, confidence) = await self.matchingService.matchLineItem(item.description)
                        return (index, barcode, product, confidence)
                    }
                }

                for await (index, barcode, product, confidence) in group {
                    lineItems[index].matchedBarcode = barcode
                    lineItems[index].matchedProduct = product
                    lineItems[index].matchingConfidence = confidence
                }
            }

            let matchedCount = lineItems.filter { $0.matchedBarcode != nil }.count
            print("✅ Matched \(matchedCount)/\(lineItems.count) items to products")

            // Step 4: Match store using MapKit
            let merchantName = prediction.supplier_name?.value
            let userLocation = locationService.currentLocation?.coordinate

            var matchedStore: Store?
            var storeConfidence: Receipt.StoreMatchConfidence = .none

            if let merchant = merchantName {
                print("🏪 Matching store: \(merchant)")
                (matchedStore, storeConfidence) = await matchingService.matchStore(
                    merchantName: merchant,
                    userLocation: userLocation
                )
            }

            selectedStore = matchedStore

            // Step 5: Create receipt object
            let processingTime = Date().timeIntervalSince(startTime)
            let userId = Auth.auth().currentUser?.uid ?? "anonymous"

            let receipt = Receipt(
                prediction: prediction,
                userId: userId,
                lineItems: lineItems,
                matchedStore: matchedStore,
                storeConfidence: storeConfidence,
                processingTime: processingTime
            )

            self.receipt = receipt
            self.editableLineItems = lineItems

            print("✅ Receipt processing complete in \(String(format: "%.1f", processingTime))s")
            print("   Merchant: \(merchantName ?? "Unknown")")
            print("   Items: \(lineItems.count) (\(matchedCount) matched)")
            print("   Store: \(matchedStore?.name ?? "Not matched")")

            isProcessing = false

        } catch let error as ReceiptOCRError {
            isProcessing = false
            errorMessage = error.localizedDescription
            print("❌ Receipt processing error: \(error.localizedDescription)")
        } catch {
            isProcessing = false
            errorMessage = "Failed to process receipt. Please try again."
            print("❌ Unexpected error: \(error.localizedDescription)")
        }
    }

    /// Submit receipt to Firebase
    func submitReceipt() async -> Bool {
        guard var receipt = receipt,
              let store = selectedStore else {
            errorMessage = "Missing receipt or store information"
            return false
        }

        isProcessing = true

        do {
            // Update receipt with edited line items and selected store
            receipt.lineItems = editableLineItems
            receipt.matchedStore = store

            let submittedCount = try await FirebaseService.shared.submitReceipt(
                receipt: receipt,
                store: store
            )

            let points = calculatePoints(itemCount: submittedCount)
            print("✅ Receipt submitted: \(submittedCount) items, earned \(points) points")

            isProcessing = false
            return true

        } catch {
            errorMessage = error.localizedDescription
            isProcessing = false
            print("❌ Error submitting receipt: \(error)")
            return false
        }
    }

    /// Reset state for new receipt
    func reset() {
        selectedImage = nil
        isProcessing = false
        ocrResult = nil
        receipt = nil
        errorMessage = nil
        editableLineItems = []
        selectedStore = nil
    }

    // MARK: - Helpers

    /// Calculate points for display (matches FirebaseService calculation)
    func calculatePoints(itemCount: Int) -> Int {
        switch itemCount {
        case 0...4: return itemCount * 10
        case 5...9: return 50
        case 10...19: return 100
        case 20...: return 200
        default: return 0
        }
    }

    /// Count of submittable items (those with matched barcodes)
    var submittableItemsCount: Int {
        editableLineItems.filter { $0.matchedBarcode != nil }.count
    }

    /// Whether the form is valid for submission
    var isFormValid: Bool {
        selectedStore != nil && submittableItemsCount > 0
    }

    deinit {
        print("🧾 ReceiptScannerViewModel deinitialized")
    }
}
