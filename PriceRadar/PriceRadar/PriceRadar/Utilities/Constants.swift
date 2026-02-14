//
//  Constants.swift
//  PriceRadar
//
//  App-wide constants and configuration
//

import Foundation

enum Constants {
    // Search radius in miles
    static let defaultSearchRadiusMiles: Double = 10.0
    static let maxSearchRadiusMiles: Double = 50.0

    // UI Constants
    static let cornerRadius: CGFloat = 12
    static let cardPadding: CGFloat = 16
    static let smallPadding: CGFloat = 8

    // Map Constants
    static let defaultMapSpanDelta: Double = 0.05 // About 3.5 miles

    // Animation
    static let standardAnimationDuration: Double = 0.3

    // Color scheme
    enum Colors {
        static let cheapestGreen = "CheapestGreen"
        static let primaryBlue = "PrimaryBlue"
    }

    // Format helpers
    static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter
    }()

    static let distanceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        return formatter
    }()

    // Format price as currency string
    static func formatPrice(_ price: Double) -> String {
        return currencyFormatter.string(from: NSNumber(value: price)) ?? "$\(String(format: "%.2f", price))"
    }

    // Format distance in miles
    static func formatDistance(_ miles: Double) -> String {
        let formatted = distanceFormatter.string(from: NSNumber(value: miles)) ?? String(format: "%.1f", miles)
        return "\(formatted) mi"
    }

    // Format price difference
    static func formatPriceDifference(_ difference: Double) -> String {
        if difference == 0 {
            return "Best price"
        } else {
            return "+\(formatPrice(difference))"
        }
    }
}
