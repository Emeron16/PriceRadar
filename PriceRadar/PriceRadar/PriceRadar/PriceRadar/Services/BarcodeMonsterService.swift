//
//  BarcodeMonsterService.swift
//  PriceRadar
//
//  Service for fetching product information from Barcode Monster API (RapidAPI)
//

import Foundation

class BarcodeMonsterService {
    static let shared = BarcodeMonsterService()

    // Load API key from environment variables
    private var apiKey: String? {
        return EnvConfig.barcodeMonsterAPIKey
    }
    private let baseURL = "https://barcode-monster.p.rapidapi.com/"
    private var cache: [String: BarcodeMonsterProduct] = [:]

    private init() {
        print("📊 BarcodeMonsterService initialized")
        // Note: API key is checked lazily when getProduct() is called,
        // ensuring .env has been loaded by PriceRadarApp.init()
    }

    func getProduct(barcode: String) async throws -> BarcodeMonsterProduct? {
        // Check if API key is available
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            print("⚠️ Barcode Monster API key not configured - skipping")
            return nil
        }

        // Check cache first
        if let cached = cache[barcode] {
            print("📦 Using cached Barcode Monster data")
            return cached
        }

        guard let url = URL(string: "\(baseURL)\(barcode)") else {
            throw BarcodeMonsterError.invalidBarcode
        }

        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "X-RapidAPI-Key")
        request.addValue("barcode-monster.p.rapidapi.com", forHTTPHeaderField: "X-RapidAPI-Host")

        print("🔍 Fetching from Barcode Monster: \(barcode)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            print("❌ Barcode Monster: Product not found")
            throw BarcodeMonsterError.notFound
        }

        let product = try JSONDecoder().decode(BarcodeMonsterProduct.self, from: data)
        cache[barcode] = product

        print("✅ Barcode Monster found: \(product.name)")
        return product
    }
}

// MARK: - Models

public struct BarcodeMonsterProduct: Codable {
    public let barcode: String
    public let barcode_type: String?
    public let name: String
    public let brand: String?
    public let category: String?
    public let manufacturer: String?
    public let description: String?
    public let status: String?
}

public enum BarcodeMonsterError: LocalizedError {
    case invalidBarcode
    case notFound
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidBarcode: return "Invalid barcode format"
        case .notFound: return "Product not found in database"
        case .invalidResponse: return "Invalid API response"
        }
    }
}
