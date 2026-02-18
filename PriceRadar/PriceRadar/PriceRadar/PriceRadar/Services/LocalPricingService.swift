//
//  LocalPricingService.swift
//  PriceRadar
//
//  Service for loading and querying local JSON pricing database
//

import Foundation
import CoreLocation
import MapKit

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

    // MARK: - MapKit Local Search

    /// Search for stores of a specific chain using MapKit Local Search
    func searchMapKitStores(
        for chainName: String,
        near location: CLLocationCoordinate2D,
        radius: Double = 10.0
    ) async throws -> [Store] {
        print("🔍 Searching '\(chainName)' near: \(location.latitude), \(location.longitude) within \(radius) miles")

        // Create search region (diameter = radius * 2)
        let regionRadius: CLLocationDistance = radius * 1609.34 * 2  // Convert miles to meters
        let region = MKCoordinateRegion(
            center: location,
            latitudinalMeters: regionRadius,
            longitudinalMeters: regionRadius
        )

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = chainName
        request.region = region

        let search = MKLocalSearch(request: request)

        return try await withCheckedThrowingContinuation { continuation in
            search.start { [weak self] response, error in
                guard let self = self else {
                    continuation.resume(returning: [])
                    return
                }

                if let error = error {
                    print("❌ MapKit search error for '\(chainName)': \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }

                guard let response = response, !response.mapItems.isEmpty else {
                    print("ℹ️ No MapKit results for '\(chainName)'")
                    continuation.resume(returning: [])
                    return
                }

                print("✅ Found \(response.mapItems.count) MapKit results for '\(chainName)'")

                // Convert MKMapItems to Store objects
                let stores = response.mapItems.compactMap { mapItem in
                    Store(from: mapItem, userLocation: location)
                }

                continuation.resume(returning: stores)
            }
        }
    }

    /// Search ALL stores within radius (radius-based, not chain-based)
    func searchStoresWithinRadius(
        near location: CLLocationCoordinate2D,
        radius: Double = 5.0,  // Default 5 miles as requested
        productCategory: String? = nil  // NEW: Product category for filtering
    ) async -> [Store] {
        print("🔍 Searching stores within \(radius) miles for category: '\(productCategory ?? "general")'")

        // Create search region (diameter = radius * 2)
        let regionRadius: CLLocationDistance = radius * 1609.34 * 2  // Convert miles to meters
        let region = MKCoordinateRegion(
            center: location,
            latitudinalMeters: regionRadius,
            longitudinalMeters: regionRadius
        )

        // NEW: Use category-specific search terms
        let searchTerms = StoreRelevanceService.shared.getSearchTerms(for: productCategory)
        print("📋 Using search terms: \(searchTerms)")
        var allStores: [Store] = []

        await withTaskGroup(of: [Store].self) { group in
            for term in searchTerms {
                group.addTask {
                    let request = MKLocalSearch.Request()
                    request.naturalLanguageQuery = term
                    request.region = region
                    request.resultTypes = .pointOfInterest

                    let search = MKLocalSearch(request: request)

                    do {
                        let response = try await search.start()
                        print("✅ Found \(response.mapItems.count) results for '\(term)'")

                        // Convert to Store objects
                        return response.mapItems.compactMap { mapItem in
                            Store(from: mapItem, userLocation: location)
                        }
                    } catch {
                        print("⚠️ Search failed for '\(term)': \(error.localizedDescription)")
                        return []
                    }
                }
            }

            for await stores in group {
                allStores.append(contentsOf: stores)
            }
        }

        print("📍 Found \(allStores.count) total stores before deduplication")

        // Remove duplicates based on coordinates
        let uniqueStores = deduplicateStores(allStores)

        // Filter by exact radius (remove anything outside the radius)
        let storesInRadius = uniqueStores.filter { store in
            guard let distance = store.distanceInMiles else { return false }
            return distance <= radius
        }

        print("📍 \(storesInRadius.count) unique stores within \(radius) miles")

        // Sort by distance (closest first)
        let sorted = storesInRadius.sorted { a, b in
            (a.distanceInMiles ?? Double.infinity) < (b.distanceInMiles ?? Double.infinity)
        }

        print("✅ Returning \(sorted.count) stores within radius")

        return sorted
    }

    /// DEPRECATED: Search multiple chains in parallel and merge with pricing data
    /// Use searchStoresWithinRadius instead for radius-based search
    func searchMultipleChains(
        chains: [String],
        for barcode: String,
        near location: CLLocationCoordinate2D,
        radius: Double = 10.0,
        productCategory: String? = nil  // NEW: Product category for filtering
    ) async -> [Store] {
        print("🔍 Searching \(chains.count) chains via MapKit for category: '\(productCategory ?? "general")'")

        // Search all chains in parallel using async let
        var allStores: [Store] = []

        await withTaskGroup(of: [Store].self) { group in
            for chain in chains {
                group.addTask {
                    do {
                        return try await self.searchMapKitStores(
                            for: chain,
                            near: location,
                            radius: radius
                        )
                    } catch {
                        print("⚠️ Failed to search \(chain): \(error.localizedDescription)")
                        return []
                    }
                }
            }

            for await stores in group {
                allStores.append(contentsOf: stores)
            }
        }

        print("📍 Found \(allStores.count) total stores before deduplication")

        // Remove duplicates
        let uniqueStores = deduplicateStores(allStores)
        print("📍 \(uniqueStores.count) unique stores after deduplication")

        // Match with pricing data
        let storesWithPrices = uniqueStores.map { store in
            matchPriceToStore(store, barcode: barcode)
        }

        // ONLY return stores that have pricing data
        let storesWithValidPrices = storesWithPrices.filter { $0.price != nil }

        print("📍 Filtered: \(storesWithPrices.count) total → \(storesWithValidPrices.count) with prices")

        // Sort by price (lowest first)
        let sorted = storesWithValidPrices.sorted { a, b in
            if let priceA = a.price, let priceB = b.price {
                return priceA < priceB
            }
            return (a.distanceInMiles ?? Double.infinity) < (b.distanceInMiles ?? Double.infinity)
        }

        print("✅ Returning \(sorted.count) stores with pricing")

        return sorted
    }

    // MARK: - MapKit Helper Methods

    /// Match pricing data to a MapKit-discovered store
    private func matchPriceToStore(_ store: Store, barcode: String) -> Store {
        var storeWithPrice = store

        // Strategy 1: Try exact location match (within 100 meters)
        if let exactMatch = findNearbyStore(store, threshold: 0.062) { // ~100m in miles
            if let price = getPriceForStore(exactMatch.id, barcode: barcode) {
                storeWithPrice.price = price
                storeWithPrice.priceSource = "exact"
                print("💰 Exact price match for \(store.name): $\(price)")
                return storeWithPrice
            }
        }

        // Strategy 2: Try chain-level average with improved matching
        let chainPrices = stores
            .filter { localStore in
                chainsMatch(store.chain, localStore.chain) ||
                chainsMatch(store.name, localStore.chain) ||
                chainsMatch(store.chain, localStore.name)
            }
            .compactMap { getPriceForStore($0.id, barcode: barcode) }

        if !chainPrices.isEmpty {
            let avgPrice = chainPrices.reduce(0.0, +) / Double(chainPrices.count)
            storeWithPrice.price = avgPrice
            storeWithPrice.priceSource = "chain_estimate"
            print("📊 Chain estimate for \(store.name): $\(String(format: "%.2f", avgPrice)) (avg of \(chainPrices.count) stores)")
            return storeWithPrice
        }

        // Strategy 3: No match - show store without price
        storeWithPrice.priceSource = "unavailable"
        print("❓ No pricing for \(store.name) (chain: '\(store.chain)')")
        return storeWithPrice
    }

    /// Find a store in the local database near the given store
    private func findNearbyStore(_ store: Store, threshold: Double) -> Store? {
        return stores.first { localStore in
            let distance = calculateDistance(from: store.coordinate, to: localStore.coordinate)
            return distance <= threshold
        }
    }

    /// Get price for a specific store and barcode
    private func getPriceForStore(_ storeId: String, barcode: String) -> Double? {
        return prices.first { $0.storeId == storeId && $0.barcode == barcode }?.price
    }

    /// Remove duplicate stores based on coordinates
    private func deduplicateStores(_ stores: [Store]) -> [Store] {
        var seen = Set<String>()
        return stores.filter { store in
            let key = String(format: "%.4f,%.4f", store.latitude, store.longitude)
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    /// Improved chain matching logic
    private func chainsMatch(_ chain1: String, _ chain2: String) -> Bool {
        // Normalize both chains: lowercase, remove extra words
        let normalized1 = normalizeChainName(chain1)
        let normalized2 = normalizeChainName(chain2)

        // Check if either contains the other
        if normalized1.contains(normalized2) || normalized2.contains(normalized1) {
            return true
        }

        // Check for common chain variations
        let chainVariations: [String: [String]] = [
            "walmart": ["walmart", "wal-mart", "walmart supercenter", "walmart neighborhood market"],
            "target": ["target", "target store", "target corporation", "supertarget"],
            "cvs": ["cvs", "cvs pharmacy", "cvs/pharmacy"],
            "walgreens": ["walgreens", "walgreens pharmacy"],
            "safeway": ["safeway", "safeway food & drug"],
            "kroger": ["kroger", "kroger food & drug", "kroger marketplace"],
            "albertsons": ["albertsons", "albertsons market"],
            "whole foods": ["whole foods", "whole foods market", "wholefoods"],
            "trader joe's": ["trader joe's", "trader joes", "traderjoes"],
            "costco": ["costco", "costco wholesale"],
            "sam's club": ["sam's club", "sams club", "sam's"],
            "ralphs": ["ralphs", "ralphs grocery"],
            "jewel-osco": ["jewel-osco", "jewel osco", "jewel"],
            "h-e-b": ["h-e-b", "heb", "h e b"],
            "sprouts": ["sprouts", "sprouts farmers market"]
        ]

        // Check if both belong to same variation group
        for (_, variations) in chainVariations {
            let matches1 = variations.contains { normalized1.contains($0) }
            let matches2 = variations.contains { normalized2.contains($0) }
            if matches1 && matches2 {
                return true
            }
        }

        return false
    }

    /// Normalize chain name for matching
    private func normalizeChainName(_ name: String) -> String {
        var normalized = name.lowercased()

        // Remove common suffixes and patterns
        let removePatterns = [
            "#\\d+",              // Store numbers like "#1234"
            "store \\d+",         // "Store 1234"
            "supercenter",
            "neighborhood market",
            "pharmacy",
            "grocery",
            "food & drug",
            "market",
            "corporation",
            "inc\\.",
            "llc",
            "\\([^)]*\\)",        // Anything in parentheses
        ]

        for pattern in removePatterns {
            normalized = normalized.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        // Remove extra whitespace
        normalized = normalized.trimmingCharacters(in: .whitespaces)
        normalized = normalized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return normalized
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
