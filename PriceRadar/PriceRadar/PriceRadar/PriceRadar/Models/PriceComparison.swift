//
//  PriceComparison.swift
//  PriceRadar
//
//  Data model for price comparison results
//

import Foundation
import CoreLocation

struct PriceComparison: Identifiable, Equatable {
    let id = UUID()
    let product: Product
    var stores: [Store]
    let userLocation: CLLocationCoordinate2D?

    // Equatable conformance
    static func == (lhs: PriceComparison, rhs: PriceComparison) -> Bool {
        lhs.id == rhs.id
    }

    // Computed properties
    var cheapestStore: Store? {
        stores.min(by: { ($0.price ?? Double.greatestFiniteMagnitude) < ($1.price ?? Double.greatestFiniteMagnitude) })
    }

    var mostExpensiveStore: Store? {
        stores.max(by: { ($0.price ?? 0) < ($1.price ?? 0) })
    }

    var maxPriceDifference: Double? {
        guard let cheapest = cheapestStore?.price,
              let mostExpensive = mostExpensiveStore?.price else {
            return nil
        }
        return mostExpensive - cheapest
    }

    var averagePrice: Double? {
        let prices = stores.compactMap { $0.price }
        guard !prices.isEmpty else { return nil }
        return prices.reduce(0, +) / Double(prices.count)
    }

    // Sort stores by price (lowest first)
    mutating func sortByPrice() {
        stores.sort {
            ($0.price ?? Double.greatestFiniteMagnitude) < ($1.price ?? Double.greatestFiniteMagnitude)
        }
    }

    // Sort stores by distance (closest first)
    mutating func sortByDistance() {
        stores.sort {
            ($0.distanceInMiles ?? Double.greatestFiniteMagnitude) < ($1.distanceInMiles ?? Double.greatestFiniteMagnitude)
        }
    }

    // Get price difference from cheapest for a given store
    func priceDifference(for store: Store) -> Double? {
        guard let cheapestPrice = cheapestStore?.price,
              let storePrice = store.price else {
            return nil
        }
        return storePrice - cheapestPrice
    }
}

// MARK: - Sample Data for Previews
extension PriceComparison {
    static let sample = PriceComparison(
        product: .sample,
        stores: Store.samples,
        userLocation: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    )
}
