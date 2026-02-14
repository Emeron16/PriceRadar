//
//  Store.swift
//  PriceRadar
//
//  Data model representing a retail store with location and pricing information
//

import Foundation
import CoreLocation
import MapKit

struct Store: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let chain: String
    let address: String
    let latitude: Double
    let longitude: Double
    var price: Double? // Price for a specific product
    var distanceInMiles: Double? // Distance from user location

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case chain
        case address
        case latitude
        case longitude
    }

    // Calculate distance from a given location
    mutating func calculateDistance(from userLocation: CLLocationCoordinate2D) {
        let storeLocation = CLLocation(latitude: latitude, longitude: longitude)
        let userCLLocation = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        let distanceInMeters = storeLocation.distance(from: userCLLocation)
        self.distanceInMiles = distanceInMeters / 1609.34 // Convert meters to miles
    }
}

// MARK: - Map Annotation
extension Store {
    var mapAnnotation: StoreAnnotation {
        StoreAnnotation(store: self)
    }
}

struct StoreAnnotation: Identifiable {
    let id: String
    let store: Store

    init(store: Store) {
        self.id = store.id
        self.store = store
    }

    var coordinate: CLLocationCoordinate2D {
        store.coordinate
    }
}

// MARK: - Sample Data for Previews
extension Store {
    static let sample = Store(
        id: "walmart_001",
        name: "Walmart Supercenter",
        chain: "Walmart",
        address: "123 Main St, San Francisco, CA 94102",
        latitude: 37.7749,
        longitude: -122.4194,
        price: 5.99,
        distanceInMiles: 0.5
    )

    static let samples = [
        Store(
            id: "walmart_001",
            name: "Walmart Supercenter",
            chain: "Walmart",
            address: "123 Main St, San Francisco, CA 94102",
            latitude: 37.7749,
            longitude: -122.4194,
            price: 5.99,
            distanceInMiles: 0.5
        ),
        Store(
            id: "target_001",
            name: "Target",
            chain: "Target",
            address: "456 Market St, San Francisco, CA 94103",
            latitude: 37.7849,
            longitude: -122.4094,
            price: 6.49,
            distanceInMiles: 1.2
        ),
        Store(
            id: "safeway_001",
            name: "Safeway",
            chain: "Safeway",
            address: "789 Valencia St, San Francisco, CA 94110",
            latitude: 37.7599,
            longitude: -122.4214,
            price: 5.79,
            distanceInMiles: 0.8
        )
    ]
}
