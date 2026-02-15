//
//  PriceComparisonViewModel.swift
//  PriceRadar
//
//  ViewModel for price comparison functionality
//

import Foundation
import SwiftUI
import CoreLocation
import Combine

@MainActor
class PriceComparisonViewModel: ObservableObject {
    @Published var priceComparison: PriceComparison?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var sortBy: SortOption = .price
    @Published var useMapKit: Bool = true
    @Published var isSearchingStores: Bool = false

    private let pricingService = LocalPricingService.shared
    private let locationService = LocationService()

    // Supported store chains for MapKit search
    private let supportedChains = ["Walmart", "Target", "Safeway", "CVS", "Walgreens",
                                   "Ralphs", "Jewel-Osco", "H-E-B", "Kroger", "Whole Foods"]

    enum SortOption {
        case price
        case distance

        var title: String {
            switch self {
            case .price: return "Price"
            case .distance: return "Distance"
            }
        }
    }

    init() {
        // Request permission first
        locationService.requestPermission()
    }

    // PERFORMANCE: Ensure location services stop when ViewModel is destroyed
    deinit {
        locationService.stopUpdatingLocation()
    }

    /// Fetch price comparison for a barcode (async with MapKit support)
    func fetchPriceComparison(for barcode: String) async {
        if useMapKit {
            await fetchPriceComparisonWithMapKit(for: barcode)
        } else {
            fetchPriceComparisonLocal(for: barcode)
        }
    }

    /// Fetch price comparison using MapKit Local Search
    private func fetchPriceComparisonWithMapKit(for barcode: String) async {
        // Clear previous results
        priceComparison = nil
        isLoading = true
        isSearchingStores = true
        errorMessage = nil

        // Get product info
        guard let product = pricingService.findProduct(barcode: barcode) else {
            errorMessage = "Product not found in database"
            isLoading = false
            isSearchingStores = false
            return
        }

        // Wait for user location (with timeout)
        let userLocation = await waitForLocation(timeout: 5.0)

        guard let userLocation = userLocation else {
            print("⚠️ No location available after timeout - using local database")

            // Check the actual auth status for better error messaging
            let authStatus = locationService.authorizationStatus
            if authStatus == .denied || authStatus == .restricted {
                errorMessage = "Location access denied. Go to Settings > Privacy > Location Services > PriceRadar and select 'While Using the App'. Using nearby stores database instead."
            } else if authStatus == .notDetermined {
                errorMessage = "Location permission needed. Please allow location access when prompted."
            } else {
                errorMessage = "Location unavailable. Using nearby stores database instead."
            }

            // Fall back to local database with user's awareness
            print("🔄 Falling back to local database search")
            fetchPriceComparisonLocal(for: barcode)
            return
        }

        print("📍 Using location: \(userLocation.latitude), \(userLocation.longitude)")
        print("🔍 Searching stores via MapKit for barcode: \(barcode)")

        // Search MapKit for stores
        let stores = await pricingService.searchMultipleChains(
            chains: supportedChains,
            for: barcode,
            near: userLocation,
            radius: Constants.defaultSearchRadiusMiles
        )

        isSearchingStores = false

        // Fall back to local database if MapKit returns nothing
        if stores.isEmpty {
            print("⚠️ No MapKit results, falling back to local database")
            fetchPriceComparisonLocal(for: barcode)
            return
        }

        var comparison = PriceComparison(
            product: product,
            stores: stores,
            userLocation: userLocation
        )

        // Sort based on current sort option
        applySorting(to: &comparison)

        priceComparison = comparison
        isLoading = false

        print("✅ MapKit search complete: \(stores.count) stores found")
    }

    /// Fetch price comparison using local database (original implementation)
    func fetchPriceComparisonLocal(for barcode: String) {
        // Clear previous results
        priceComparison = nil
        isLoading = true
        isSearchingStores = false
        errorMessage = nil

        // Get product info
        guard let product = pricingService.findProduct(barcode: barcode) else {
            errorMessage = "Product not found in database"
            isLoading = false
            return
        }

        // Get user location
        guard let userLocation = locationService.currentLocation?.coordinate else {
            // If no location, still show stores but without distance sorting
            fetchWithoutLocation(product: product, barcode: barcode)
            return
        }

        // Fetch stores with prices
        let stores = pricingService.getStoresWithPrices(
            for: barcode,
            near: userLocation,
            radiusMiles: Constants.defaultSearchRadiusMiles
        )

        if stores.isEmpty {
            errorMessage = "No stores found with pricing for this product nearby"
            isLoading = false
            return
        }

        var comparison = PriceComparison(
            product: product,
            stores: stores,
            userLocation: userLocation
        )

        // Sort based on current sort option
        applySorting(to: &comparison)

        priceComparison = comparison
        isLoading = false
    }

    /// Wait for user location with timeout
    private func waitForLocation(timeout: TimeInterval) async -> CLLocationCoordinate2D? {
        // If we already have location, return it immediately
        if let location = locationService.currentLocation?.coordinate {
            print("✅ Using cached location: \(location.latitude), \(location.longitude)")
            return location
        }

        // Check authorization status
        let authStatus = locationService.authorizationStatus
        print("📍 Location authorization status: \(authStatus.rawValue)")

        switch authStatus {
        case .notDetermined:
            print("⚠️ Location permission not determined - requesting now")
            locationService.requestPermission()
        case .denied, .restricted:
            print("❌ Location permission denied or restricted")
            return nil
        case .authorizedWhenInUse, .authorizedAlways:
            print("✅ Location permission granted")
        @unknown default:
            print("❓ Unknown authorization status")
        }

        // Start location updates if not already started
        locationService.startUpdatingLocation()

        // Wait for location with timeout
        let startTime = Date()
        var attempts = 0
        while Date().timeIntervalSince(startTime) < timeout {
            attempts += 1
            if let location = locationService.currentLocation?.coordinate {
                print("✅ Got location after \(attempts) attempts: \(location.latitude), \(location.longitude)")
                return location
            }
            // Check every 100ms
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }

        print("⏱️ Location timeout after \(timeout) seconds (\(attempts) attempts)")
        print("📍 Final auth status: \(locationService.authorizationStatus.rawValue)")
        return nil
    }

    /// Fetch without location (fallback)
    private func fetchWithoutLocation(product: Product, barcode: String) {
        // Use a default location (San Francisco) for demo purposes
        let defaultLocation = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

        let stores = pricingService.getStoresWithPrices(
            for: barcode,
            near: defaultLocation,
            radiusMiles: Constants.maxSearchRadiusMiles
        )

        if stores.isEmpty {
            errorMessage = "No pricing data available for this product"
            isLoading = false
            return
        }

        let comparison = PriceComparison(
            product: product,
            stores: stores,
            userLocation: nil
        )

        priceComparison = comparison
        isLoading = false
    }

    /// Change sort option and re-sort stores
    func changeSortOption(_ option: SortOption) {
        sortBy = option
        guard var comparison = priceComparison else { return }
        applySorting(to: &comparison)
        priceComparison = comparison
    }

    private func applySorting(to comparison: inout PriceComparison) {
        switch sortBy {
        case .price:
            comparison.sortByPrice()
        case .distance:
            comparison.sortByDistance()
        }
    }

    /// Refresh prices
    func refresh() async {
        guard let barcode = priceComparison?.product.id else { return }
        await fetchPriceComparison(for: barcode)
    }

    /// Clear current comparison
    func clear() {
        priceComparison = nil
        errorMessage = nil
    }
}
