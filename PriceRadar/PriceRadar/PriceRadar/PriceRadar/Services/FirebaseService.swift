//
//  FirebaseService.swift
//  PriceRadar
//
//  Service for Firebase Firestore integration and crowd-sourced pricing
//

import Foundation
import CoreLocation
import Combine
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth

@MainActor
class FirebaseService: ObservableObject {
    static let shared = FirebaseService()

    private let db = Firestore.firestore()
    @Published var currentUserId: String?

    private init() {
        print("🔥 FirebaseService initialized")
    }

    // MARK: - Authentication

    func signInAnonymously() async throws {
        let result = try await Auth.auth().signInAnonymously()
        currentUserId = result.user.uid
        await createUserProfileIfNeeded(uid: result.user.uid)
        print("✅ Anonymous auth: \(result.user.uid)")
    }

    private func createUserProfileIfNeeded(uid: String) async {
        let userRef = db.collection("users").document(uid)
        let snapshot = try? await userRef.getDocument()

        if snapshot?.exists != true {
            let userData: [String: Any] = [
                "user_id": uid,
                "points": 0,
                "submissions_count": 0,
                "verified_submissions": 0,
                "badges": [],
                "join_date": Timestamp(date: Date()),
                "last_active": Timestamp(date: Date())
            ]
            try? await userRef.setData(userData)
            print("✅ Created new user profile: \(uid)")
        }
    }

    // MARK: - Price Submissions

    func submitPrice(
        barcode: String,
        productName: String,
        storeId: String,
        storeName: String,
        chain: String,
        price: Double,
        latitude: Double,
        longitude: Double,
        address: String
    ) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw FirebaseError.notAuthenticated
        }

        let submission: [String: Any] = [
            "barcode": barcode,
            "product_name": productName,
            "store_id": storeId,
            "store_name": storeName,
            "chain": chain,
            "price": price,
            "latitude": latitude,
            "longitude": longitude,
            "address": address,
            "user_id": userId,
            "timestamp": Timestamp(date: Date()),
            "verified": false,
            "upvotes": 0,
            "downvotes": 0,
            "confidence_score": 1.0,
            "source": "user_submission"
        ]

        try await db.collection("price_submissions").addDocument(data: submission)
        print("✅ Price submitted: $\(price) at \(storeName)")

        // Award points
        try await awardPoints(userId: userId, points: 10)
    }

    // MARK: - Bulk Receipt Submissions

    /// Submit entire receipt with batch writes
    /// - Parameters:
    ///   - receipt: Receipt with line items to submit
    ///   - store: Store where receipt was from
    /// - Returns: Number of items successfully submitted
    func submitReceipt(
        receipt: Receipt,
        store: Store
    ) async throws -> Int {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw FirebaseError.notAuthenticated
        }

        var submittedCount = 0
        var failedCount = 0

        // Use batch writes for atomicity (up to 500 operations per batch)
        let batch = db.batch()

        for lineItem in receipt.lineItems {
            // Only submit items with matched products
            guard let barcode = lineItem.matchedBarcode else {
                print("⚠️ Skipping item without barcode: \(lineItem.description)")
                failedCount += 1
                continue
            }

            let unitPrice = lineItem.unitPrice ?? (lineItem.totalPrice / lineItem.quantity)

            let submission: [String: Any] = [
                "barcode": barcode,
                "product_name": bestProductName(for: lineItem),
                "store_id": store.id,
                "store_name": store.name,
                "chain": store.chain,
                "price": unitPrice,
                "latitude": store.latitude,
                "longitude": store.longitude,
                "address": store.address,
                "user_id": userId,
                "timestamp": Timestamp(date: Date()),
                "verified": false,
                "upvotes": 0,
                "downvotes": 0,
                "confidence_score": confidenceToScore(lineItem.matchingConfidence),
                "source": "receipt_ocr",
                "receipt_id": receipt.id  // NEW FIELD - group related submissions
            ]

            let docRef = db.collection("price_submissions").document()
            batch.setData(submission, forDocument: docRef)
            submittedCount += 1
        }

        // Commit batch
        try await batch.commit()
        print("✅ Bulk receipt submission: \(submittedCount) items submitted, \(failedCount) skipped")

        // Award points based on tiered system
        let points = calculateReceiptPoints(itemCount: submittedCount)
        try await awardPoints(userId: userId, points: points)

        // Store receipt metadata for user history (non-fatal — don't block submission on this)
        do {
            try await saveReceiptRecord(receipt: receipt, itemsSubmitted: submittedCount)
        } catch {
            print("⚠️ Receipt record save failed (non-fatal): \(error.localizedDescription)")
        }

        return submittedCount
    }

    /// Build the best available product name for a receipt line item.
    /// Prefers brand + product name when the raw OFF name is too generic (single word),
    /// and falls back to the cleaned receipt description if the matched name is still poor.
    private func bestProductName(for item: ReceiptLineItem) -> String {
        // Generic single-word names that add no value
        let genericNames: Set<String> = ["original", "unknown", "unknown product", "product", "item"]

        if let product = item.matchedProduct {
            let rawName = product.name.trimmingCharacters(in: .whitespaces)
            let isGeneric = genericNames.contains(rawName.lowercased()) || rawName.split(separator: " ").count <= 1

            if isGeneric, let brand = product.brand, brand != "Generic", brand != "Unknown" {
                // Combine brand + name (e.g., "SunChips Original")
                return "\(brand) \(rawName)"
            } else if !isGeneric {
                return rawName
            }
        }

        // Fall back to the receipt description (e.g., "071050315 SUNCHIPS" → strip leading barcode)
        let desc = item.description
        let barcodePrefix = try? NSRegularExpression(pattern: #"^\d{8,14}\s+"#)
        let range = NSRange(desc.startIndex..., in: desc)
        let cleaned = barcodePrefix?.stringByReplacingMatches(in: desc, range: range, withTemplate: "") ?? desc
        return cleaned.trimmingCharacters(in: .whitespaces).capitalized
    }

    /// Calculate points awarded for receipt based on item count (tiered system)
    private func calculateReceiptPoints(itemCount: Int) -> Int {
        switch itemCount {
        case 0...4:
            return itemCount * 10  // Same as manual (10 per item)
        case 5...9:
            return 50  // Bonus for small receipts
        case 10...19:
            return 100  // Bonus for medium receipts
        case 20...:
            return 200  // Bonus for large receipts
        default:
            return 0
        }
    }

    /// Convert matching confidence to numerical score
    private func confidenceToScore(_ confidence: ReceiptLineItem.MatchingConfidence) -> Double {
        switch confidence {
        case .high: return 0.9
        case .medium: return 0.7
        case .low: return 0.5
        case .none: return 0.3
        }
    }

    /// Save receipt metadata to receipt_uploads collection
    private func saveReceiptRecord(receipt: Receipt, itemsSubmitted: Int) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let receiptData: [String: Any] = [
            "receipt_id": receipt.id,
            "user_id": userId,
            "merchant_name": receipt.merchantName ?? "Unknown",
            "upload_date": Timestamp(date: receipt.uploadDate),
            "total_items": receipt.lineItems.count,
            "submitted_items": itemsSubmitted,
            "total_amount": receipt.totalAmount ?? 0.0,
            "processing_time_seconds": receipt.ocrProcessingTime
        ]

        try await db.collection("receipt_uploads").document(receipt.id).setData(receiptData)
        print("✅ Receipt record saved: \(receipt.id)")
    }

    // MARK: - Price Queries

    func getPricesForProduct(
        barcode: String,
        near location: CLLocationCoordinate2D,
        radius: Double = 50.0
    ) async throws -> [PriceSubmission] {
        let submissions = try await db.collection("price_submissions")
            .whereField("barcode", isEqualTo: barcode)
            .order(by: "timestamp", descending: true)
            .limit(to: 100)
            .getDocuments()

        return submissions.documents.compactMap { doc in
            try? doc.data(as: PriceSubmission.self)
        }.filter { submission in
            // Filter by distance
            let submissionLoc = CLLocation(latitude: submission.latitude, longitude: submission.longitude)
            let userLoc = CLLocation(latitude: location.latitude, longitude: location.longitude)
            let distanceInMiles = submissionLoc.distance(from: userLoc) / 1609.34
            return distanceInMiles <= radius
        }
    }

    // MARK: - Gamification

    private func awardPoints(userId: String, points: Int) async throws {
        let userRef = db.collection("users").document(userId)
        try await userRef.updateData([
            "points": FieldValue.increment(Int64(points)),
            "submissions_count": FieldValue.increment(Int64(1))
        ])
        print("✅ Awarded \(points) points to user")
    }

    func getUserStats(userId: String) async throws -> UserStats? {
        let snapshot = try await db.collection("users").document(userId).getDocument()
        return try? snapshot.data(as: UserStats.self)
    }
}

// MARK: - Models

public struct PriceSubmission: Codable, Identifiable {
    @DocumentID public var id: String?
    public let barcode: String
    public let product_name: String
    public let store_id: String
    public let store_name: String
    public let chain: String
    public let price: Double
    public let latitude: Double
    public let longitude: Double
    public let address: String
    public let user_id: String
    public let timestamp: Timestamp
    public let verified: Bool
    public let upvotes: Int
    public let downvotes: Int
    public let confidence_score: Double
    public let source: String
}

public struct UserStats: Codable {
    public let user_id: String
    public let points: Int
    public let submissions_count: Int
    public let verified_submissions: Int
    public let badges: [String]
    public let join_date: Timestamp
    public let last_active: Timestamp
}

public enum FirebaseError: LocalizedError {
    case notAuthenticated
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "User not authenticated"
        case .invalidData: return "Invalid data format"
        }
    }
}
