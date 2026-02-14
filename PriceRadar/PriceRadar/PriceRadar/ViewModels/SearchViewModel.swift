//
//  SearchViewModel.swift
//  PriceRadar
//
//  ViewModel for manual product search
//

import Foundation
import SwiftUI
import Combine

class SearchViewModel: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var searchResults: [Product] = []
    @Published var isSearching: Bool = false
    @Published var selectedProduct: Product?

    private let pricingService = LocalPricingService.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupSearchDebouncing()
    }

    private func setupSearchDebouncing() {
        // Debounce search input (wait 300ms after user stops typing)
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
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

        isSearching = true

        // Search in local database
        let results = pricingService.searchProducts(query: query)
        searchResults = results
        isSearching = false
    }

    func selectProduct(_ product: Product) {
        selectedProduct = product
    }

    func clearSearch() {
        searchQuery = ""
        searchResults = []
        selectedProduct = nil
    }
}
