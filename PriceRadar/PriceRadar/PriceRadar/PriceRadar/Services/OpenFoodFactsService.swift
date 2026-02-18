//
//  OpenFoodFactsService.swift
//  PriceRadar
//
//  Service for fetching product information from Open Food Facts API
//

import Foundation

class OpenFoodFactsService {
    static let shared = OpenFoodFactsService()

    private let baseURL = "https://world.openfoodfacts.org/api/v2/product/"
    private var cache: [String: OFFProduct] = [:]

    private init() {
        print("🥫 OpenFoodFactsService initialized")
    }

    func getProduct(barcode: String) async throws -> OFFProduct? {
        // Check cache first
        if let cached = cache[barcode] {
            print("📦 Using cached OFF product: \(barcode)")
            return cached
        }

        guard let url = URL(string: "\(baseURL)\(barcode).json") else {
            throw OFFError.invalidBarcode
        }

        print("🌐 Fetching from Open Food Facts: \(barcode)")

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OFFError.networkError
        }

        let decoder = JSONDecoder()
        let result = try decoder.decode(OFFResponse.self, from: data)

        if result.status == 1, let product = result.product {
            cache[barcode] = product
            print("✅ OFF Product found: \(product.displayName) | Has pricing: \(product.hasPricing)")
            return product
        } else {
            print("❌ Product not in OFF database")
            return nil
        }
    }
}

// MARK: - Models

struct OFFResponse: Codable {
    let status: Int
    let product: OFFProduct?
}

public struct OFFProduct: Codable {
    public let product_name: String?
    public let brands: String?
    public let categories: String?
    public let image_url: String?
    public let image_small_url: String?
    public let quantity: String?
    public let stores: String?      // Sometimes has store data
    public let price: String?       // Sometimes has pricing

    public var displayName: String {
        product_name?.isEmpty == false ? product_name! : "Unknown Product"
    }

    public var displayBrand: String {
        brands ?? "Generic"
    }

    // Note: OFF rarely has actual pricing data, so we always need crowdsourcing
    // This property kept for potential future use if OFF adds pricing APIs
    public var hasPricing: Bool {
        let hasPrice = price != nil && !(price?.isEmpty ?? true)
        let hasStores = stores != nil && !(stores?.isEmpty ?? true)
        return hasPrice || hasStores
    }

    // Parse price if available (rarely populated)
    public var estimatedPrice: Double? {
        guard let priceStr = price else { return nil }
        // Parse price string (e.g., "$1.99", "1,99€")
        let cleaned = priceStr.replacingOccurrences(of: "[^0-9.,]", with: "", options: .regularExpression)
        return Double(cleaned.replacingOccurrences(of: ",", with: "."))
    }
}

public enum OFFError: LocalizedError {
    case invalidBarcode
    case networkError
    case productNotFound

    public var errorDescription: String? {
        switch self {
        case .invalidBarcode: return "Invalid barcode format"
        case .networkError: return "Network connection failed"
        case .productNotFound: return "Product not found"
        }
    }
}
