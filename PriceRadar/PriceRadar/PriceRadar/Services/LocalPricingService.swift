//
//  LocalPricingService.swift
//  PriceRadar
//
//  Service for loading and querying local JSON pricing database
//

import Foundation
import CoreLocation

class LocalPricingService {
    static let shared = LocalPricingService()

    private var products: [Product] = []
    private var stores: [Store] = []
    private var prices: [PriceEntry] = []

    private init() {
        loadData()
    }

    // Load all JSON data
    private func loadData() {
        loadProducts()
        loadStores()
        loadPrices()
    }

    // MARK: - JSON Loading

    private func loadProducts() {
        guard let url = Bundle.main.url(forResource: "products", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("❌ Failed to load products.json")
            return
        }

        do {
            let response = try JSONDecoder().decode(ProductsResponse.self, from: data)
            products = response.products
            print("✅ Loaded \(products.count) products")
        } catch {
            print("❌ Failed to decode products.json: \(error)")
        }
    }

    private func loadStores() {
        guard let url = Bundle.main.url(forResource: "stores", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("❌ Failed to load stores.json")
            return
        }

        do {
            let response = try JSONDecoder().decode(StoresResponse.self, from: data)
            stores = response.stores
            print("✅ Loaded \(stores.count) stores")
        } catch {
            print("❌ Failed to decode stores.json: \(error)")
        }
    }

    private func loadPrices() {
        guard let url = Bundle.main.url(forResource: "prices", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("❌ Failed to load prices.json")
            return
        }

        do {
            let response = try JSONDecoder().decode(PricesResponse.self, from: data)
            prices = response.prices
            print("✅ Loaded \(prices.count) price entries")
        } catch {
            print("❌ Failed to decode prices.json: \(error)")
        }
    }

    // MARK: - Public API

    /// Find product by barcode
    func findProduct(barcode: String) -> Product? {
        return products.first { $0.id == barcode }
    }

    /// Search products by name (case-insensitive)
    func searchProducts(query: String) -> [Product] {
        guard !query.isEmpty else { return [] }
        return products.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            ($0.brand?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    /// Get stores near a location with prices for a specific product
    func getStoresWithPrices(for barcode: String, near location: CLLocationCoordinate2D, radiusMiles: Double = 10.0) -> [Store] {
        // PERFORMANCE: Build price map first (O(n) instead of O(n²))
        let productPrices = prices.filter { $0.barcode == barcode }
        let priceMap = Dictionary(uniqueKeysWithValues: productPrices.map { ($0.storeId, $0.price) })

        // PERFORMANCE: Single-pass filter with distance calculation (not twice!)
        var storesWithPrices: [Store] = stores.compactMap { store in
            // Only consider stores that have prices for this product
            guard let price = priceMap[store.id] else { return nil }

            // Calculate distance once and cache it
            let distance = calculateDistance(from: location, to: store.coordinate)

            // Filter by radius
            guard distance <= radiusMiles else { return nil }

            // Build store with all data in one pass
            var storeWithData = store
            storeWithData.price = price
            storeWithData.distanceInMiles = distance
            return storeWithData
        }

        // Sort by price (lowest first)
        storesWithPrices.sort { ($0.price ?? 0) < ($1.price ?? 0) }

        return storesWithPrices
    }

    /// Get all stores (for testing/debugging)
    func getAllStores() -> [Store] {
        return stores
    }

    /// Get all products (for testing/debugging)
    func getAllProducts() -> [Product] {
        return products
    }

    // MARK: - Helper Methods

    private func calculateDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        let distanceInMeters = fromLocation.distance(from: toLocation)
        return distanceInMeters / 1609.34 // Convert to miles
    }
}

// MARK: - Supporting Types

private struct ProductsResponse: Codable {
    let products: [Product]
}

private struct StoresResponse: Codable {
    let stores: [Store]
}

private struct PricesResponse: Codable {
    let prices: [PriceEntry]
}

private struct PriceEntry: Codable {
    let barcode: String
    let storeId: String
    let price: Double

    enum CodingKeys: String, CodingKey {
        case barcode
        case storeId = "store_id"
        case price
    }
}
