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

class PriceComparisonViewModel: ObservableObject {
    @Published var priceComparison: PriceComparison?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var sortBy: SortOption = .price

    private let pricingService = LocalPricingService.shared
    private let locationService = LocationService()

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
        locationService.requestPermission()
    }

    // PERFORMANCE: Ensure location services stop when ViewModel is destroyed
    deinit {
        locationService.stopUpdatingLocation()
    }

    /// Fetch price comparison for a barcode
    func fetchPriceComparison(for barcode: String) {
        // Clear previous results
        priceComparison = nil
        isLoading = true
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
    func refresh() {
        guard let barcode = priceComparison?.product.id else { return }
        fetchPriceComparison(for: barcode)
    }

    /// Clear current comparison
    func clear() {
        priceComparison = nil
        errorMessage = nil
    }
}
