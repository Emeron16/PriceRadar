//
//  SearchViewModel.swift
//  PriceRadar
//
//  ViewModel for manual product search with Open Food Facts integration
//

import Foundation
import SwiftUI
import Combine

@MainActor
class SearchViewModel: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var searchResults: [Product] = []
    @Published var isSearching: Bool = false
    @Published var selectedProduct: Product?

    private let pricingService = LocalPricingService.shared
    private let offService = OpenFoodFactsService.shared
    private var cancellables = Set<AnyCancellable>()

    // Track search task for cancellation
    private var currentSearchTask: Task<Void, Never>?

    init() {
        setupSearchDebouncing()
    }

    private func setupSearchDebouncing() {
        // Debounce search input — wait 600ms, deduplicate case-insensitively to prevent
        // autocorrect capitalization changes from triggering redundant searches
        $searchQuery
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .removeDuplicates { $0.lowercased() == $1.lowercased() }
            .sink { [weak self] query in
                self?.performSearch(query: query)
            }
            .store(in: &cancellables)
    }

    private func performSearch(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        // Cancel any existing search
        currentSearchTask?.cancel()

        isSearching = true

        // Create new search task
        currentSearchTask = Task {
            await searchProducts(query: query)
        }
    }

    /// Search products using Open Food Facts API + local database
    private func searchProducts(query: String) async {
        print("🔍 Searching for '\(query)' in Open Food Facts...")

        // Search Open Food Facts
        let offResults = await searchOpenFoodFacts(query: query)

        // Check if task was cancelled
        guard !Task.isCancelled else {
            print("⚠️ Search cancelled for '\(query)'")
            isSearching = false
            return
        }

        // Also search local database as fallback
        let localResults = pricingService.searchProducts(query: query)

        // Combine results (OFF first, then local, removing duplicates by barcode)
        var combinedResults: [Product] = []
        var seenBarcodes = Set<String>()

        // Add OFF results first
        for product in offResults {
            if !seenBarcodes.contains(product.id) {
                combinedResults.append(product)
                seenBarcodes.insert(product.id)
            }
        }

        // Add local results (if not already added from OFF)
        for product in localResults {
            if !seenBarcodes.contains(product.id) {
                combinedResults.append(product)
                seenBarcodes.insert(product.id)
            }
        }

        print("✅ Found \(offResults.count) from OFF + \(localResults.count) local = \(combinedResults.count) total results")

        // Only update if not cancelled
        guard !Task.isCancelled else {
            print("⚠️ Search cancelled before updating results for '\(query)'")
            isSearching = false
            return
        }

        searchResults = combinedResults
        isSearching = false
    }

    /// Search Open Food Facts API using v2 search endpoint (faster than cgi/search.pl)
    private func searchOpenFoodFacts(query: String) async -> [Product] {
        var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/search")!
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "page_size", value: "10"),
            URLQueryItem(name: "fields", value: "code,product_name,brands,categories,image_small_url,image_url")
        ]

        guard let url = components.url else {
            print("❌ Invalid search URL")
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("PriceRadar iOS App - Contact: admin@priceradar.app", forHTTPHeaderField: "User-Agent")

        do {
            print("🌐 Fetching from Open Food Facts: \(url)")

            let (data, response) = try await URLSession.shared.data(for: request)

            // Check if cancelled after network call
            guard !Task.isCancelled else {
                print("⚠️ OFF search cancelled after network call")
                return []
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("❌ OFF search failed with status code")
                return []
            }

            let decoder = JSONDecoder()
            let searchResult = try decoder.decode(OFFSearchResult.self, from: data)

            print("✅ OFF returned \(searchResult.products.count) products")

            // Convert OFF products to our Product model
            let products = searchResult.products.compactMap { offProduct -> Product? in
                // Only include products with valid barcodes
                guard let barcode = offProduct.code, !barcode.isEmpty else {
                    return nil
                }

                return Product(
                    id: barcode,
                    name: offProduct.product_name?.isEmpty == false ? offProduct.product_name! : "Unknown Product",
                    brand: offProduct.brands,
                    category: offProduct.categories,
                    imageURL: offProduct.image_small_url
                )
            }

            return products

        } catch is CancellationError {
            print("⚠️ OFF search cancelled: \(query)")
            return []
        } catch let decodingError as DecodingError {
            print("❌ OFF decode error for '\(query)': \(decodingError)")
            return []
        } catch {
            print("❌ OFF search error for '\(query)': \(error.localizedDescription)")
            return []
        }
    }

    func selectProduct(_ product: Product) {
        selectedProduct = product
    }

    func clearSearch() {
        currentSearchTask?.cancel()
        searchQuery = ""
        searchResults = []
        selectedProduct = nil
    }

    deinit {
        currentSearchTask?.cancel()
    }
}

// MARK: - Open Food Facts Search Models

struct OFFSearchResult: Codable {
    let count: Int?
    let page: Int?
    let page_size: Int?
    let products: [OFFSearchProduct]

    // v2 API uses different top-level key in some responses
    private enum CodingKeys: String, CodingKey {
        case count, page, page_size, products
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = try container.decodeIfPresent(Int.self, forKey: .count)
        page = try container.decodeIfPresent(Int.self, forKey: .page)
        page_size = try container.decodeIfPresent(Int.self, forKey: .page_size)
        // products key is present in both v1 and v2 responses
        products = (try? container.decode([OFFSearchProduct].self, forKey: .products)) ?? []
    }
}

struct OFFSearchProduct: Codable {
    let code: String?              // Barcode
    let product_name: String?
    let brands: String?
    let categories: String?
    let image_small_url: String?
    let image_url: String?
}
