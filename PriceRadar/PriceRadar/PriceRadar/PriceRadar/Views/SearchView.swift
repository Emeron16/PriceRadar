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
                SearchBar(text: $viewModel.searchQuery, isFocused: $isSearchFocused, onSearch: viewModel.search)
                    .padding()

                if !viewModel.hasSearched && !viewModel.isSearching {
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
                    // Loading state - improved UX
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding(.bottom, 8)

                        Text("Searching...")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("Looking for '\(viewModel.searchQuery)'")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxHeight: .infinity)
                } else if viewModel.hasSearched && viewModel.searchResults.isEmpty {
                    // No results after a search was run
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
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.searchResults) { product in
                                ProductRow(product: product)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        isSearchFocused = false
                                        handleProductSelected(product)
                                    }
                                    .padding(.horizontal)
                                Divider()
                                    .padding(.leading, 74)
                            }
                        }
                    }
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
        Task {
            await priceComparisonViewModel.fetchPriceComparison(for: product.id)
        }
    }
}

// MARK: - Search Bar
struct SearchBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var onSearch: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search products...", text: $text)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .onSubmit {
                    isFocused.wrappedValue = false
                    onSearch()
                }

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }

            Button(action: {
                isFocused.wrappedValue = false
                onSearch()
            }) {
                Text("Search")
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            }
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
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
            // Product image or placeholder
            if let imageURL = product.imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        // Loading spinner
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.1))
                                .frame(width: 50, height: 50)

                            ProgressView()
                                .tint(.blue)
                        }
                    case .success(let image):
                        // Successfully loaded image
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .failure(_):
                        // Failed to load, show placeholder
                        productPlaceholder
                    @unknown default:
                        productPlaceholder
                    }
                }
                .frame(width: 50, height: 50)
            } else {
                // No image URL available
                productPlaceholder
            }

            // Product info
            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(2)

                if let brand = product.brand {
                    Text(brand)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let category = product.category {
                    Text(category)
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var productPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.1))
                .frame(width: 50, height: 50)

            Image(systemName: "barcode")
                .font(.title3)
                .foregroundColor(.blue)
        }
    }
}

#Preview {
    SearchView(priceComparisonViewModel: PriceComparisonViewModel())
}
