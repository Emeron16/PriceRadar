//
//  PriceAggregationService.swift
//  PriceRadar
//
//  Service for aggregating crowd-sourced prices with 4-tier pricing strategy
//

import Foundation
import CoreLocation
import FirebaseFirestore

class PriceAggregationService {
    static let shared = PriceAggregationService()

    private let firebaseService = FirebaseService.shared
    private let offService = OpenFoodFactsService.shared

    private init() {
        print("💰 PriceAggregationService initialized")
    }

    /// Get prices for stores using crowd-sourced data
    func getPrices(
        for barcode: String,
        at stores: [Store],
        userLocation: CLLocationCoordinate2D
    ) async -> [Store] {
        // 1. Fetch product info from Open Food Facts
        let productInfo = try? await offService.getProduct(barcode: barcode)

        // DEBUG: Check if OFF has usable pricing
        if let offProduct = productInfo {
            print("🥫 OFF Product: \(offProduct.displayName)")
            print("🥫 OFF Price string: \(offProduct.price ?? "nil")")
            print("🥫 OFF Stores: \(offProduct.stores ?? "nil")")
            print("🥫 OFF Estimated price: \(offProduct.estimatedPrice?.description ?? "nil")")
        }

        // 2. Fetch crowd-sourced submissions from Firebase
        let submissions = (try? await firebaseService.getPricesForProduct(
            barcode: barcode,
            near: userLocation,
            radius: 50.0
        )) ?? []

        print("📊 Found \(submissions.count) price submissions")

        // DEBUG: Log all submissions
        for submission in submissions {
            print("   📦 Submission: '\(submission.store_name)' at (\(submission.latitude), \(submission.longitude)) price=$\(submission.price)")
        }

        // DEBUG: Log all stores from MapKit
        print("📍 Received \(stores.count) stores from MapKit:")
        for store in stores {
            print("   🏪 '\(store.name)' at (\(store.latitude), \(store.longitude))")
        }

        // 3. Match submissions to stores
        var storesWithPrices = stores

        for (index, store) in storesWithPrices.enumerated() {
            let priceData = calculateBestPrice(
                for: store,
                submissions: submissions,
                offProduct: productInfo
            )

            storesWithPrices[index].price = priceData.price
            storesWithPrices[index].priceSource = priceData.source
            storesWithPrices[index].confidenceScore = priceData.confidence
        }

        // 4. Add stores from Firebase submissions that MapKit didn't find
        let additionalStores = createStoresFromUnmatchedSubmissions(
            submissions: submissions,
            existingStores: storesWithPrices,
            userLocation: userLocation
        )

        storesWithPrices.append(contentsOf: additionalStores)

        print("📍 Final result: \(storesWithPrices.count) stores (\(stores.count) from MapKit + \(additionalStores.count) from Firebase)")

        return storesWithPrices
    }

    /// 4-tier pricing strategy (location-based matching)
    private func calculateBestPrice(
        for store: Store,
        submissions: [PriceSubmission],
        offProduct: OFFProduct?
    ) -> (price: Double?, source: String, confidence: Double) {

        // Calculate all distances once for debugging
        let submissionsWithDistance = submissions.map { submission -> (submission: PriceSubmission, distanceInMiles: Double) in
            let distance = distanceInMiles(
                from: store.coordinate,
                to: CLLocationCoordinate2D(latitude: submission.latitude, longitude: submission.longitude)
            )
            return (submission, distance)
        }

        // TIER 1: Same location (within 100m ~0.062 miles) + recent (< 7 days)
        let exactMatches = submissionsWithDistance.filter { item in
            let ageInDays = Date().timeIntervalSince(item.submission.timestamp.dateValue()) / (24 * 60 * 60)
            let isNearby = item.distanceInMiles < 0.062  // ~100 meters
            let isRecent = ageInDays < 7

            if isNearby && isRecent {
                print("✅ TIER 1: Exact match - '\(item.submission.store_name)' distance=\(String(format: "%.3f", item.distanceInMiles))mi age=\(Int(ageInDays))d price=$\(item.submission.price)")
            }

            return isNearby && isRecent
        }

        if let best = exactMatches.first {
            let daysAgo = Int(Date().timeIntervalSince(best.submission.timestamp.dateValue()) / (24 * 60 * 60))
            return (best.submission.price, daysAgo == 0 ? "Verified today" : "Verified \(daysAgo)d ago", 0.95)
        }

        // TIER 2: Nearby location (within 0.5 miles) + recent (< 30 days)
        let nearbyMatches = submissionsWithDistance.filter { item in
            let ageInDays = Date().timeIntervalSince(item.submission.timestamp.dateValue()) / (24 * 60 * 60)
            let isNearby = item.distanceInMiles < 0.5  // Half mile radius
            let isRecent = ageInDays < 30

            if isNearby && isRecent {
                print("✅ TIER 2: Nearby match - '\(item.submission.store_name)' distance=\(String(format: "%.2f", item.distanceInMiles))mi age=\(Int(ageInDays))d price=$\(item.submission.price)")
            }

            return isNearby && isRecent
        }

        if !nearbyMatches.isEmpty {
            let avgPrice = nearbyMatches.map { $0.submission.price }.reduce(0, +) / Double(nearbyMatches.count)
            print("💰 Using nearby average for \(store.name): $\(String(format: "%.2f", avgPrice))")
            return (avgPrice, "Nearby estimate", 0.70)
        }

        // TIER 3: Open Food Facts MSRP (if available)
        if let estimatedPrice = offProduct?.estimatedPrice {
            print("💰 Using OFF MSRP for \(store.name): $\(estimatedPrice)")
            return (estimatedPrice, "MSRP estimate", 0.40)
        }

        // TIER 4: No price available
        print("❓ No pricing for \(store.name) (chain: '\(store.chain)')")
        print("   Available submissions:")
        for item in submissionsWithDistance.prefix(3) {
            print("   - '\(item.submission.store_name)' distance=\(String(format: "%.2f", item.distanceInMiles))mi")
        }
        return (nil, "Unknown", 0.0)
    }

    // MARK: - Helpers

    /// Create Store objects from Firebase submissions that weren't matched by MapKit
    private func createStoresFromUnmatchedSubmissions(
        submissions: [PriceSubmission],
        existingStores: [Store],
        userLocation: CLLocationCoordinate2D
    ) -> [Store] {
        var unmatchedStores: [Store] = []

        for submission in submissions {
            let submissionLocation = CLLocationCoordinate2D(
                latitude: submission.latitude,
                longitude: submission.longitude
            )

            // Check if this submission is already matched to an existing store (within 100m)
            let isMatched = existingStores.contains { store in
                let distance = distanceInMiles(from: store.coordinate, to: submissionLocation)
                return distance < 0.062  // ~100 meters
            }

            // If not matched, create a new Store from this submission
            if !isMatched {
                let distance = distanceInMiles(from: userLocation, to: submissionLocation)
                let ageInDays = Date().timeIntervalSince(submission.timestamp.dateValue()) / (24 * 60 * 60)

                let newStore = Store(
                    id: "firebase_\(submission.id ?? UUID().uuidString)",
                    name: submission.store_name,
                    chain: submission.chain,
                    address: submission.address,
                    latitude: submission.latitude,
                    longitude: submission.longitude,
                    price: submission.price,
                    distanceInMiles: distance,
                    priceSource: ageInDays == 0 ? "Verified today" : "Verified \(Int(ageInDays))d ago",
                    confidenceScore: 0.95  // High confidence since it's a direct submission
                )

                unmatchedStores.append(newStore)
                print("✅ Added store from Firebase: '\(submission.store_name)' at \(String(format: "%.2f", distance))mi with price $\(submission.price)")
            }
        }

        return unmatchedStores
    }

    private func distanceInMiles(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let fromLoc = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLoc = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLoc.distance(from: toLoc) / 1609.34
    }

    private func chainsMatch(_ chain1: String, _ chain2: String) -> Bool {
        let normalized1 = chain1.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized2 = chain2.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized1.contains(normalized2) || normalized2.contains(normalized1)
    }
}
