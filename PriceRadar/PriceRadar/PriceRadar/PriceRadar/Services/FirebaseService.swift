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
