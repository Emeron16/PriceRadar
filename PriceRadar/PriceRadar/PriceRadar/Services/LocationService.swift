//
//  LocationService.swift
//  PriceRadar
//
//  Service for managing user location and permissions
//

import Foundation
import CoreLocation
import Combine

class LocationService: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()

    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var error: LocationError?

    // PERFORMANCE: Track if we've gotten first location to stop updates
    private var hasGottenFirstLocation = false

    override init() {
        super.init()
        locationManager.delegate = self
        // PERFORMANCE: Use lower accuracy (100m) instead of Best - saves battery and reduces heat
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // PERFORMANCE: Only update when moved 50 meters - prevents continuous updates
        locationManager.distanceFilter = 50
        authorizationStatus = locationManager.authorizationStatus
    }

    // Request location permission
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    // Start updating location
    func startUpdatingLocation() {
        #if !os(macOS)
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            error = .permissionDenied
            return
        }
        #endif
        locationManager.startUpdatingLocation()
    }

    // Stop updating location
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }

    // Calculate distance between two coordinates in miles
    func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        let distanceInMeters = fromLocation.distance(from: toLocation)
        return distanceInMeters / 1609.34 // Convert to miles
    }

    // Get current coordinate (if available)
    var currentCoordinate: CLLocationCoordinate2D? {
        location?.coordinate
    }

    // Get current location (for compatibility)
    var currentLocation: CLLocation? {
        location
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.location = location

        // PERFORMANCE: Stop GPS after getting first good location to save battery
        if !hasGottenFirstLocation {
            hasGottenFirstLocation = true
            // Stop updates after 1 second to allow for accuracy improvements
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.stopUpdatingLocation()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        self.error = .locationUnavailable
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        #if !os(macOS)
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdatingLocation()
        case .denied, .restricted:
            error = .permissionDenied
            stopUpdatingLocation()
        case .notDetermined:
            break
        @unknown default:
            break
        }
        #else
        // macOS location authorization
        if authorizationStatus == .authorizedAlways {
            startUpdatingLocation()
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            error = .permissionDenied
            stopUpdatingLocation()
        }
        #endif
    }
}

// MARK: - Location Errors
enum LocationError: LocalizedError {
    case permissionDenied
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location access denied. Please enable location services in Settings."
        case .locationUnavailable:
            return "Unable to determine your location. Please try again."
        }
    }
}
