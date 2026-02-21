//
//  ReceiptProductMatchingService.swift
//  PriceRadar
//
//  Service for matching OCR text to products and stores
//

import Foundation
import CoreLocation
import MapKit

class ReceiptProductMatchingService {
    static let shared = ReceiptProductMatchingService()

    private let offService = OpenFoodFactsService.shared

    private init() {
        print("🔍 ReceiptProductMatchingService initialized")
    }

    // MARK: - Product Matching

    /// Match line item description to product database
    /// - Parameter description: Raw OCR text (e.g., "COCA COLA 12OZ")
    /// - Returns: Tuple of (barcode, product, confidence)
    func matchLineItem(_ description: String) async -> (barcode: String?, product: Product?, confidence: ReceiptLineItem.MatchingConfidence) {
        // Extract leading barcode if present (e.g., "071050315 SUNCHIPS" → barcode: "071050315", name: "SUNCHIPS")
        let (extractedBarcode, nameOnly) = extractBarcodePrefix(from: description)
        let cleaned = cleanDescription(nameOnly)

        print("🔍 Matching: '\(description)' -> barcode: '\(extractedBarcode ?? "none")', name: '\(cleaned)'")

        // Strategy 1: Direct barcode lookup on Open Food Facts (most accurate)
        if let barcode = extractedBarcode,
           let product = await lookupByBarcode(barcode) {
            print("✅ Barcode lookup match: \(product.name)")
            return (barcode, product, .high)
        }

        // Strategy 2: Text search on Open Food Facts by cleaned product name
        if !cleaned.isEmpty, let (barcode, product) = await searchOpenFoodFacts(query: cleaned) {
            print("✅ Name search match: \(product.name)")
            return (barcode, product, .medium)
        }

        print("⚠️ No match found for: \(description)")
        return (nil, nil, .none)
    }

    // MARK: - Store Matching

    /// Match merchant name to nearby stores
    /// - Parameters:
    ///   - merchantName: Merchant name from OCR (e.g., "Walmart Supercenter")
    ///   - userLocation: User's current location
    /// - Returns: Tuple of (store, confidence)
    func matchStore(merchantName: String, userLocation: CLLocationCoordinate2D?) async -> (store: Store?, confidence: Receipt.StoreMatchConfidence) {
        guard let location = userLocation else {
            print("⚠️ No user location for store matching")
            return (nil, .none)
        }

        print("🏪 Matching store: \(merchantName)")

        // Use MapKit search (same pattern as StorePickerView)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = merchantName
        request.region = MKCoordinateRegion(
            center: location,
            latitudinalMeters: 5000,  // 5km = ~3 miles radius
            longitudinalMeters: 5000
        )

        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()

            // Take closest match
            if let firstMatch = response.mapItems.first,
               let store = Store(from: firstMatch, userLocation: location) {
                // Calculate distance to determine confidence
                let distanceKM = (store.distanceInMiles ?? 999) * 1.609

                let confidence: Receipt.StoreMatchConfidence = distanceKM < 1.0 ? .exact : .nameOnly

                print("✅ Store matched: \(store.name) (\(String(format: "%.1f", distanceKM))km away)")
                return (store, confidence)
            }
        } catch {
            print("❌ Store search failed: \(error)")
        }

        return (nil, .none)
    }

    // MARK: - Private Helpers

    /// Extract a leading barcode (8-14 digits) from a description like "071050315 SUNCHIPS"
    /// Returns (barcode, remaining name). If no barcode prefix, returns (nil, original text).
    private func extractBarcodePrefix(from text: String) -> (String?, String) {
        // Match: starts with 8-14 digits optionally followed by a space and product name
        let pattern = #"^(\d{8,14})\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges == 3,
              let barcodeRange = Range(match.range(at: 1), in: text),
              let nameRange = Range(match.range(at: 2), in: text) else {
            return (nil, text)
        }
        return (String(text[barcodeRange]), String(text[nameRange]))
    }

    /// Clean OCR description for better name-based matching
    private func cleanDescription(_ text: String) -> String {
        var cleaned = text.uppercased()

        // Remove common receipt prefixes
        for prefix in ["ITEM", "PRODUCT", "SKU", "CODE"] {
            if cleaned.hasPrefix(prefix + " ") {
                cleaned = String(cleaned.dropFirst(prefix.count + 1))
            }
        }

        // Remove leading asterisk (e.g., "*1255 ..." payment lines — shouldn't reach here but guard anyway)
        cleaned = cleaned.replacingOccurrences(of: #"^\*\d+\s+"#, with: "", options: .regularExpression)

        // Remove trailing tax/status codes common on receipts (e.g., "SUNCHIPS F", "MILK T")
        cleaned = cleaned.replacingOccurrences(of: #"\s+[FTENWB]$"#, with: "", options: .regularExpression)

        // Remove trailing quantities (e.g., "COCA COLA 2X")
        cleaned = cleaned.replacingOccurrences(of: #"\s+\d+X$"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\s+X\d+$"#, with: "", options: .regularExpression)

        // Remove special characters except spaces and hyphens (preserve "COCA-COLA")
        cleaned = cleaned.replacingOccurrences(of: "[^A-Z0-9 \\-]", with: " ", options: .regularExpression)

        // Collapse multiple spaces
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    /// Look up a product directly by barcode on Open Food Facts
    private func lookupByBarcode(_ barcode: String) async -> Product? {
        let urlString = "https://world.openfoodfacts.org/api/v0/product/\(barcode).json"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            // OFF returns {"status": 1, "product": {...}} or {"status": 0}
            struct OFFProductResponse: Codable {
                let status: Int
                let product: OFFProduct?
            }

            let decoded = try JSONDecoder().decode(OFFProductResponse.self, from: data)
            guard decoded.status == 1, let offProduct = decoded.product else { return nil }

            return Product(barcode: barcode, offProduct: offProduct)
        } catch {
            print("❌ Barcode lookup error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Search Open Food Facts by product name
    /// - Parameter query: Cleaned product name
    /// - Returns: Tuple of (barcode, product) if found
    private func searchOpenFoodFacts(query: String) async -> (String, Product)? {
        // OFF Search API: https://world.openfoodfacts.org/cgi/search.pl
        let searchURL = "https://world.openfoodfacts.org/cgi/search.pl"
        var components = URLComponents(string: searchURL)!
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "json", value: "true"),
            URLQueryItem(name: "page_size", value: "5"),
            URLQueryItem(name: "fields", value: "code,product_name,brands,categories,image_small_url")
        ]

        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("❌ OFF search failed: HTTP error")
                return nil
            }

            let searchResponse = try JSONDecoder().decode(OFFSearchResponse.self, from: data)

            // Return first match if any
            if let firstProduct = searchResponse.products.first,
               let barcode = firstProduct.code {
                // Use existing Product initializer for OFFProduct
                let offProduct = OFFProduct(
                    product_name: firstProduct.product_name,
                    brands: firstProduct.brands,
                    categories: firstProduct.categories,
                    image_url: nil,
                    image_small_url: firstProduct.image_small_url,
                    quantity: nil,
                    stores: nil,
                    price: nil
                )
                let product = Product(barcode: barcode, offProduct: offProduct)
                return (barcode, product)
            }
        } catch {
            print("❌ OFF search error: \(error.localizedDescription)")
        }

        return nil
    }
}

// MARK: - Open Food Facts Search Models
// Note: Using simplified models for search API (different from main OFF API)

private struct OFFSearchResponse: Codable {
    let products: [OFFSearchProductResult]
    let count: Int?
}

private struct OFFSearchProductResult: Codable {
    let code: String?
    let product_name: String?
    let brands: String?
    let categories: String?
    let image_small_url: String?
}
