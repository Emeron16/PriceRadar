//
//  SearchView.swift
//  PriceRadar
//
//  Manual product search view
//

import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @ObservedObject var priceComparisonViewModel: PriceComparisonViewModel
    @State private var showingResults = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                SearchBar(text: $viewModel.searchQuery, isFocused: $isSearchFocused)
                    .padding()

                if viewModel.searchQuery.isEmpty {
                    // Empty state
                    VStack(spacing: 20) {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.blue.opacity(0.6))

                        Text("Search for Products")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Enter a product name or brand to find better prices nearby")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxHeight: .infinity)
                } else if viewModel.isSearching {
                    // Loading state
                    ProgressView("Searching...")
                        .frame(maxHeight: .infinity)
                } else if viewModel.searchResults.isEmpty {
                    // No results
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)

                        Text("No products found")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("Try a different search term")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    // Search results
                    List(viewModel.searchResults) { product in
                        ProductRow(product: product)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isSearchFocused = false // Dismiss keyboard
                                handleProductSelected(product)
                            }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isSearchFocused = false
                    }
                }
            }
            .onTapGesture {
                // Dismiss keyboard when tapping outside
                isSearchFocused = false
            }
            .onChange(of: priceComparisonViewModel.priceComparison) { comparison in
                if comparison != nil {
                    showingResults = true
                }
            }
            .onChange(of: priceComparisonViewModel.errorMessage) { error in
                if error != nil && !priceComparisonViewModel.isLoading {
                    showingResults = true
                }
            }
            .navigationDestination(isPresented: $showingResults) {
                PriceComparisonView(viewModel: priceComparisonViewModel)
            }
        }
    }

    private func handleProductSelected(_ product: Product) {
        viewModel.selectProduct(product)
        // Fetch price comparison (navigation happens via onChange)
        priceComparisonViewModel.fetchPriceComparison(for: product.id)
    }
}

// MARK: - Search Bar
struct SearchBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search products...", text: $text)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .submitLabel(.search)
                .onSubmit {
                    isFocused.wrappedValue = false
                }

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(Constants.cornerRadius)
    }
}

// MARK: - Product Row
struct ProductRow: View {
    let product: Product

    var body: some View {
        HStack(spacing: 12) {
            // Product icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 50, height: 50)

                Image(systemName: "barcode")
                    .font(.title3)
                    .foregroundColor(.blue)
            }

            // Product info
            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(.body)
                    .fontWeight(.medium)

                if let brand = product.brand {
                    Text(brand)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let category = product.category {
                    Text(category)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    SearchView(priceComparisonViewModel: PriceComparisonViewModel())
}
