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
    @Published var needsCrowdsourcing = false  // NEW: Show crowdsourcing banner
    @Published var productForCrowdsourcing: Product?  // NEW: Product needing price data
    @Published var searchRadius: Double = 5.0  // NEW: User-configurable search radius (default 5 miles)

    private let pricingService = LocalPricingService.shared
    private let locationService = LocationService()
    private let offService = OpenFoodFactsService.shared
    private let barcodeMonsterService = BarcodeMonsterService.shared
    private let priceAggregationService = PriceAggregationService.shared

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

    /// Fetch price comparison using MapKit Local Search with smart 3-tier product lookup
    private func fetchPriceComparisonWithMapKit(for barcode: String) async {
        // Clear previous results
        priceComparison = nil
        isLoading = true
        isSearchingStores = true
        errorMessage = nil
        needsCrowdsourcing = false
        productForCrowdsourcing = nil

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
        print("🔍 Search radius: \(searchRadius) miles")

        // ═══════════════════════════════════════════════════════════
        // TIER 1: Try Open Food Facts (product info + images for food)
        // ═══════════════════════════════════════════════════════════
        if let offProduct = try? await offService.getProduct(barcode: barcode) {

            print("✅ Product found in Open Food Facts - using for product info")

            // Get ALL stores within radius (radius-based, not chain-based)
            print("🗺️ Calling searchStoresWithinRadius with radius: \(searchRadius) miles, category: \(offProduct.categories ?? "none")")
            let stores = await pricingService.searchStoresWithinRadius(
                near: userLocation,
                radius: searchRadius,
                productCategory: offProduct.categories  // NEW: Pass category for filtering
            )
            print("🗺️ MapKit returned \(stores.count) stores")

            isSearchingStores = false

            // Fall back to local database if MapKit returns nothing
            if stores.isEmpty {
                print("⚠️ No MapKit results, falling back to local database")
                fetchPriceComparisonLocal(for: barcode)
                return
            }

            // Use OFF product data
            let product = Product(barcode: barcode, offProduct: offProduct)

            // Get prices from crowd-sourced Firebase
            let storesWithPrices = await priceAggregationService.getPrices(
                for: barcode,
                at: stores,
                userLocation: userLocation
            )

            var comparison = PriceComparison(
                product: product,
                stores: storesWithPrices,
                userLocation: userLocation
            )

            applySorting(to: &comparison)
            priceComparison = comparison
            productForCrowdsourcing = product

            // Only show crowdsourcing banner if we have NO prices at all
            let hasPrices = storesWithPrices.contains(where: { $0.price != nil })
            needsCrowdsourcing = !hasPrices

            isLoading = false
            return
        }

        print("⚠️ Product not in Open Food Facts - trying Barcode Monster")

        // ═══════════════════════════════════════════════════════════
        // TIER 2: Try Barcode Monster (autofill for crowdsourcing)
        // ═══════════════════════════════════════════════════════════
        if let bmProduct = try? await barcodeMonsterService.getProduct(barcode: barcode) {

            print("📦 Product found in Barcode Monster - NEEDS crowdsourcing (autofilled)")

            // Get ALL stores within radius (radius-based, not chain-based)
            print("🗺️ Calling searchStoresWithinRadius with radius: \(searchRadius) miles, category: \(bmProduct.category ?? "none")")
            let stores = await pricingService.searchStoresWithinRadius(
                near: userLocation,
                radius: searchRadius,
                productCategory: bmProduct.category  // NEW: Pass category for filtering
            )
            print("🗺️ MapKit returned \(stores.count) stores")

            isSearchingStores = false

            // Fall back to local database if MapKit returns nothing
            if stores.isEmpty {
                print("⚠️ No MapKit results, falling back to local database")
                fetchPriceComparisonLocal(for: barcode)
                return
            }

            // Create product from Barcode Monster data
            let product = Product(barcode: barcode, barcodeMonsterProduct: bmProduct)

            // Check Firebase for any crowd-sourced prices
            let storesWithPrices = await priceAggregationService.getPrices(
                for: barcode,
                at: stores,
                userLocation: userLocation
            )

            var comparison = PriceComparison(
                product: product,
                stores: storesWithPrices,
                userLocation: userLocation
            )

            applySorting(to: &comparison)
            priceComparison = comparison
            productForCrowdsourcing = product

            // Only show crowdsourcing banner if we have NO prices at all
            let hasPrices = storesWithPrices.contains(where: { $0.price != nil })
            needsCrowdsourcing = !hasPrices

            isLoading = false
            return
        }

        print("❌ Product not in any API - NEEDS manual crowdsourcing")

        // ═══════════════════════════════════════════════════════════
        // TIER 3: Manual entry (neither API has product)
        // ═══════════════════════════════════════════════════════════

        // Get ALL stores within radius (radius-based, not chain-based)
        print("🗺️ Calling searchStoresWithinRadius with radius: \(searchRadius) miles (no category - manual entry)")
        let stores = await pricingService.searchStoresWithinRadius(
            near: userLocation,
            radius: searchRadius,
            productCategory: nil  // NEW: No category for manual entry - use general stores
        )
        print("🗺️ MapKit returned \(stores.count) stores")

        isSearchingStores = false

        // Fall back to local database if MapKit returns nothing
        if stores.isEmpty {
            print("⚠️ No MapKit results, falling back to local database")
            fetchPriceComparisonLocal(for: barcode)
            return
        }

        // Create placeholder product (user will enter name)
        let product = Product(barcode: barcode, userEnteredName: "Unknown Product")

        // Check Firebase for any crowd-sourced prices
        let storesWithPrices = await priceAggregationService.getPrices(
            for: barcode,
            at: stores,
            userLocation: userLocation
        )

        var comparison = PriceComparison(
            product: product,
            stores: storesWithPrices,
            userLocation: userLocation
        )

        applySorting(to: &comparison)
        priceComparison = comparison
        productForCrowdsourcing = product

        // Only show crowdsourcing banner if we have NO prices at all
        let hasPrices = storesWithPrices.contains(where: { $0.price != nil })
        needsCrowdsourcing = !hasPrices

        isLoading = false
    }

    /// Fetch price comparison using local database (fallback for no location/MapKit disabled)
    func fetchPriceComparisonLocal(for barcode: String) {
        // Clear previous results
        priceComparison = nil
        isLoading = true
        isSearchingStores = false
        errorMessage = nil
        needsCrowdsourcing = false
        productForCrowdsourcing = nil

        // Try to get product from local database first (legacy support)
        let localProduct = pricingService.findProduct(barcode: barcode)

        // Get user location (use default if not available)
        let userLocation = locationService.currentLocation?.coordinate ??
                           CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

        // Run API lookup asynchronously
        Task {
            var productToUse: Product?

            // TIER 1: Try Open Food Facts
            if let offProduct = try? await offService.getProduct(barcode: barcode) {
                print("✅ Product found in Open Food Facts")
                productToUse = Product(barcode: barcode, offProduct: offProduct)
                needsCrowdsourcing = !offProduct.hasPricing

            // TIER 2: Try Barcode Monster
            } else if let bmProduct = try? await barcodeMonsterService.getProduct(barcode: barcode) {
                print("📦 Product found in Barcode Monster - needs crowdsourcing")
                productToUse = Product(barcode: barcode, barcodeMonsterProduct: bmProduct)
                needsCrowdsourcing = true

            // TIER 3: Use local product or create placeholder
            } else if let local = localProduct {
                print("📂 Using local database product")
                productToUse = local
            } else {
                print("❌ Product not found in any source - manual entry needed")
                productToUse = Product(barcode: barcode, userEnteredName: "Unknown Product")
                needsCrowdsourcing = true
            }

            guard let product = productToUse else {
                errorMessage = "Unable to load product information"
                isLoading = false
                return
            }

            // Fetch stores with prices from local database
            let stores = pricingService.getStoresWithPrices(
                for: barcode,
                near: userLocation,
                radiusMiles: Constants.defaultSearchRadiusMiles
            )

            // Get crowd-sourced prices from Firebase
            let storesWithPrices = await priceAggregationService.getPrices(
                for: barcode,
                at: stores.isEmpty ? [] : stores,
                userLocation: userLocation
            )

            // Always create a comparison object, even if stores are empty
            var comparison = PriceComparison(
                product: product,
                stores: storesWithPrices,
                userLocation: userLocation
            )

            // Sort based on current sort option
            applySorting(to: &comparison)

            priceComparison = comparison
            productForCrowdsourcing = product

            // Clear any previous error messages
            errorMessage = nil
            isLoading = false
        }
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
        guard let barcode = priceComparison?.product.id else {
            print("❌ Refresh failed: No barcode available")
            return
        }
        print("🔄 Refresh called with radius: \(searchRadius) miles for barcode: \(barcode)")
        await fetchPriceComparison(for: barcode)
    }

    /// Clear current comparison
    func clear() {
        priceComparison = nil
        errorMessage = nil
    }
}
