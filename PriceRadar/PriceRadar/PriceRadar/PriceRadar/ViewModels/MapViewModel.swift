//
//  MapViewModel.swift
//  PriceRadar
//
//  ViewModel for map view functionality
//

import Foundation
import SwiftUI
import MapKit
import CoreLocation
import Combine

class MapViewModel: ObservableObject {
    @Published var region: MKCoordinateRegion
    @Published var stores: [Store] = []
    @Published var selectedStore: Store?
    @Published var userLocation: CLLocationCoordinate2D?

    init() {
        // Default region (San Francisco)
        self.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: Constants.defaultMapSpanDelta, longitudeDelta: Constants.defaultMapSpanDelta)
        )
    }

    /// Update map with price comparison data
    func updateWithComparison(_ comparison: PriceComparison, radius: Double = 10.0) {
        // Filter stores by radius
        let filteredStores = comparison.stores.filter { store in
            guard let distance = store.distanceInMiles else { return true }
            return distance <= radius
        }

        self.stores = filteredStores
        self.userLocation = comparison.userLocation

        // Calculate region to fit filtered stores
        if let region = calculateRegion(for: filteredStores, userLocation: comparison.userLocation, radius: radius) {
            self.region = region
        }
    }

    /// Calculate map region to fit all store annotations
    private func calculateRegion(for stores: [Store], userLocation: CLLocationCoordinate2D?, radius: Double = 10.0) -> MKCoordinateRegion? {
        // If we have a user location, center on user with radius-based zoom
        if let userLocation = userLocation {
            // Convert radius from miles to approximate degrees
            // 1 degree latitude ≈ 69 miles
            let radiusInDegrees = (radius / 69.0) * 2.2 // 2.2x for padding

            let span = MKCoordinateSpan(
                latitudeDelta: radiusInDegrees,
                longitudeDelta: radiusInDegrees
            )

            return MKCoordinateRegion(center: userLocation, span: span)
        }

        // Fallback: calculate bounding box if no user location
        guard !stores.isEmpty else { return nil }

        var coordinates = stores.map { $0.coordinate }

        // Calculate bounding box
        let latitudes = coordinates.map { $0.latitude }
        let longitudes = coordinates.map { $0.longitude }

        guard let minLat = latitudes.min(),
              let maxLat = latitudes.max(),
              let minLon = longitudes.min(),
              let maxLon = longitudes.max() else {
            return nil
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        // Add padding (20% extra space)
        let latDelta = (maxLat - minLat) * 1.2
        let lonDelta = (maxLon - minLon) * 1.2

        let span = MKCoordinateSpan(
            latitudeDelta: max(latDelta, 0.01), // Minimum zoom level
            longitudeDelta: max(lonDelta, 0.01)
        )

        return MKCoordinateRegion(center: center, span: span)
    }

    /// Select a store on the map
    func selectStore(_ store: Store) {
        selectedStore = store
        // Center map on selected store
        region.center = store.coordinate
    }

    /// Open store in Apple Maps for directions
    func openInMaps(store: Store) {
        let placemark = MKPlacemark(coordinate: store.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = store.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
}
