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
    var priceSource: String? // "exact", "chain_estimate", or "unavailable"

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var hasPricing: Bool {
        price != nil
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

// MARK: - MapKit Integration
extension Store {
    /// Initialize from MKMapItem for real-time store discovery
    init?(from mapItem: MKMapItem, userLocation: CLLocationCoordinate2D) {
        guard let name = mapItem.name else { return nil }

        let placemark = mapItem.placemark

        // Build address from placemark components
        var components: [String] = []
        if let subThoroughfare = placemark.subThoroughfare {
            components.append(subThoroughfare)
        }
        if let thoroughfare = placemark.thoroughfare {
            components.append(thoroughfare)
        }
        if let locality = placemark.locality {
            components.append(locality)
        }
        if let administrativeArea = placemark.administrativeArea {
            components.append(administrativeArea)
        }
        if let postalCode = placemark.postalCode {
            components.append(postalCode)
        }

        let address = components.isEmpty ? "Address unavailable" : components.joined(separator: ", ")

        // Calculate distance
        let storeLocation = CLLocation(latitude: placemark.coordinate.latitude,
                                       longitude: placemark.coordinate.longitude)
        let userCLLocation = CLLocation(latitude: userLocation.latitude,
                                        longitude: userLocation.longitude)
        let distanceInMeters = storeLocation.distance(from: userCLLocation)
        let distanceInMiles = distanceInMeters / 1609.34

        // Extract chain name and generate ID
        let chainName = Self.extractChain(from: name)
        let storeId = Self.generateMapKitStoreId(chain: chainName,
                                                 coordinate: placemark.coordinate)

        self.init(
            id: storeId,
            name: name,
            chain: chainName,
            address: address,
            latitude: placemark.coordinate.latitude,
            longitude: placemark.coordinate.longitude,
            price: nil,
            distanceInMiles: distanceInMiles
        )
    }

    private static func extractChain(from name: String) -> String {
        let chains = ["Walmart", "Target", "Safeway", "CVS", "Walgreens",
                     "Ralphs", "Jewel-Osco", "H-E-B", "Kroger", "Whole Foods",
                     "Albertsons", "Sprouts", "Trader Joe's", "Costco", "Sam's Club"]

        for chain in chains {
            if name.localizedCaseInsensitiveContains(chain) {
                return chain
            }
        }

        // Return first word as chain name if no match
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    private static func generateMapKitStoreId(chain: String, coordinate: CLLocationCoordinate2D) -> String {
        let latInt = Int(coordinate.latitude * 10000)
        let lonInt = Int(coordinate.longitude * 10000)
        return "mapkit_\(chain.lowercased())_\(latInt)_\(lonInt)"
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
