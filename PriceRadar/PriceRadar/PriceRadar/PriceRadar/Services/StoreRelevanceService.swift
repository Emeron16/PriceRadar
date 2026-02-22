//
//  StoreRelevanceService.swift
//  PriceRadar
//
//  Category-to-store-type mapping for intelligent store filtering
//

import Foundation

class StoreRelevanceService {
    static let shared = StoreRelevanceService()

    private init() {
        print("🎯 StoreRelevanceService initialized")
    }

    private let categoryMapping: [String: [String]] = [
        // Food & Beverages
        "beverages": ["grocery store", "supermarket", "Walmart", "Target", "Safeway", "Kroger", "Whole Foods", "convenience store", "CVS", "Walgreens"],
        "snacks": ["grocery store", "supermarket", "Walmart", "Target", "convenience store", "CVS", "Walgreens"],
        "dairy": ["grocery store", "supermarket", "Walmart", "Target", "Safeway", "Whole Foods"],
        "meat": ["grocery store", "supermarket", "butcher", "Walmart", "Safeway", "Whole Foods"],
        "produce": ["grocery store", "supermarket", "farmers market", "Whole Foods", "Trader Joe's"],
        "frozen": ["grocery store", "supermarket", "Walmart", "Target", "Costco"],
        "bakery": ["grocery store", "bakery", "Whole Foods", "Trader Joe's"],
        "canned": ["grocery store", "Walmart", "Target", "dollar store"],
        "condiments": ["grocery store", "Walmart", "Target"],
        "breakfast": ["grocery store", "Walmart", "Target", "Costco"],
        "cereal": ["grocery store", "Walmart", "Target", "Costco"],
        "candy": ["grocery store", "Walmart", "Target", "CVS", "Walgreens", "convenience store"],
        "soda": ["grocery store", "supermarket", "Walmart", "Target", "CVS", "Walgreens", "convenience store"],
        "drinks": ["grocery store", "supermarket", "Walmart", "Target", "CVS", "Walgreens", "convenience store"],

        // Health & Personal Care
        "health": ["pharmacy", "drugstore", "CVS", "Walgreens", "Rite Aid", "Target"],
        "beauty": ["pharmacy", "drugstore", "beauty store", "Ulta", "Sephora", "Target"],
        "vitamins": ["pharmacy", "health store", "GNC", "Vitamin Shoppe", "Whole Foods"],
        "supplements": ["pharmacy", "health store", "GNC", "Vitamin Shoppe", "CVS", "Walgreens"],
        "personal care": ["pharmacy", "drugstore", "CVS", "Walgreens", "Target", "Walmart"],
        "cosmetics": ["beauty store", "Ulta", "Sephora", "CVS", "Walgreens", "Target"],

        // Household
        "cleaning": ["grocery store", "Target", "Walmart", "Home Depot", "Lowe's"],
        "paper goods": ["grocery store", "Costco", "Sam's Club", "Target", "Walmart"],
        "household": ["grocery store", "Target", "Walmart", "Home Depot"],
        "laundry": ["grocery store", "Target", "Walmart"],

        // Electronics
        "electronics": ["electronics store", "Best Buy", "Target", "Walmart", "Apple Store"],
        "computers": ["electronics store", "Best Buy", "Apple Store", "Microsoft Store"],
        "video games": ["GameStop", "Best Buy", "Target", "Walmart"],

        // Baby & Kids
        "baby": ["Target", "Walmart", "Buy Buy Baby", "grocery store"],
        "toys": ["toy store", "Target", "Walmart", "Toys R Us"],

        // Pets
        "pet": ["pet store", "Petco", "PetSmart", "Walmart", "Target"],

        // Office
        "office": ["Staples", "Office Depot", "Target", "Walmart"],

        // Sports
        "sports": ["Dick's Sporting Goods", "Target", "Walmart", "REI"],

        // Automotive
        "automotive": ["AutoZone", "O'Reilly", "Walmart", "Target"],

        // Books
        "books": ["Barnes & Noble", "Amazon Books", "bookstore"],

        // Default fallback
        "general": ["store", "supermarket", "Walmart", "Target", "grocery store"]
    ]

    /// Get appropriate search terms for a product category.
    /// OFF returns comma-separated categories like "Snacks,Salty snacks,Appetizers,Crackers (Appetizers)".
    /// We split on commas and test each segment to avoid false partial matches
    /// (e.g. "Appetizers" containing "pet" would wrongly match the pet store category).
    func getSearchTerms(for productCategory: String?) -> [String] {
        guard let productCategory = productCategory else {
            print("📋 No category provided, using general search terms")
            return categoryMapping["general"]!
        }

        // Split OFF's comma-separated category string into individual tokens
        let segments = productCategory
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

        print("🔍 Checking \(segments.count) category segments: \(segments)")

        // Sort mapping keys longest-first so more specific keys win over short ones
        let sortedKeys = categoryMapping.keys.sorted { $0.count > $1.count }

        for segment in segments {
            for key in sortedKeys {
                if segment.contains(key) {
                    let terms = categoryMapping[key]!
                    print("✅ Matched segment '\(segment)' → key '\(key)': \(terms)")
                    return terms
                }
            }
        }

        print("⚠️ No match found, using general search terms")
        return categoryMapping["general"]!
    }

    /// Check if a category is food-related
    func isFoodCategory(_ category: String?) -> Bool {
        guard let category = category?.lowercased() else { return false }

        let foodKeywords = ["food", "beverage", "snack", "dairy", "meat", "produce",
                           "frozen", "bakery", "canned", "condiment", "breakfast",
                           "cereal", "candy", "soda", "drink"]

        return foodKeywords.contains { category.contains($0) }
    }
}
