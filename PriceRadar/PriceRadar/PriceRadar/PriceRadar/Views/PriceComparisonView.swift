//
//  PriceComparisonView.swift
//  PriceRadar
//
//  Price comparison results view
//

import SwiftUI

struct PriceComparisonView: View {
    @ObservedObject var viewModel: PriceComparisonViewModel
    @State private var showingMap = false

    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if let errorMessage = viewModel.errorMessage {
                errorView(message: errorMessage)
            } else if let comparison = viewModel.priceComparison {
                resultsView(comparison: comparison)
            } else {
                emptyView
            }
        }
        .navigationTitle("Price Comparison")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.priceComparison != nil {
                    Menu {
                        Button(action: { viewModel.changeSortOption(.price) }) {
                            Label("Sort by Price", systemImage: viewModel.sortBy == .price ? "checkmark" : "")
                        }
                        Button(action: { viewModel.changeSortOption(.distance) }) {
                            Label("Sort by Distance", systemImage: viewModel.sortBy == .distance ? "checkmark" : "")
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
        }
    }

    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            if viewModel.isSearchingStores {
                Text("Searching nearby stores...")
                    .foregroundColor(.secondary)
                Text("Using Apple Maps")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Finding best prices...")
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Error View
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Try Again") {
                Task {
                    await viewModel.refresh()
                }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Empty View
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cart.fill.badge.questionmark")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No data available")
                .font(.body)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Results View
    private func resultsView(comparison: PriceComparison) -> some View {
        VStack(spacing: 0) {
            // Product header
            productHeader(product: comparison.product)

            // Statistics
            statisticsSection(comparison: comparison)

            // Store list
            List {
                ForEach(comparison.stores) { store in
                    StoreRow(
                        store: store,
                        isCheapest: store.id == comparison.cheapestStore?.id,
                        priceDifference: comparison.priceDifference(for: store)
                    )
                }
            }
            .listStyle(.plain)
            .refreshable {
                await viewModel.refresh()
            }

            // Map button
            NavigationLink(destination: MapView(comparison: comparison)) {
                HStack {
                    Image(systemName: "map.fill")
                    Text("View on Map")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(Constants.cornerRadius)
                .padding()
            }
        }
    }

    // MARK: - Product Header
    private func productHeader(product: Product) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(product.name)
                .font(.title3)
                .fontWeight(.bold)

            if let brand = product.brand {
                Text(brand)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let category = product.category {
                Text(category)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - Statistics Section
    private func statisticsSection(comparison: PriceComparison) -> some View {
        HStack(spacing: 20) {
            if let cheapestPrice = comparison.cheapestStore?.price {
                StatBox(
                    title: "Best Price",
                    value: Constants.formatPrice(cheapestPrice),
                    color: .green
                )
            }

            if let avgPrice = comparison.averagePrice {
                StatBox(
                    title: "Avg Price",
                    value: Constants.formatPrice(avgPrice),
                    color: .blue
                )
            }

            if let maxDiff = comparison.maxPriceDifference {
                StatBox(
                    title: "You Save",
                    value: Constants.formatPrice(maxDiff),
                    color: .orange
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
}

// MARK: - Stat Box
struct StatBox: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.headline)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Store Row
struct StoreRow: View {
    let store: Store
    let isCheapest: Bool
    let priceDifference: Double?

    var body: some View {
        HStack(spacing: 12) {
            // Store icon
            ZStack {
                Circle()
                    .fill(isCheapest ? Color.green.opacity(0.2) : Color.blue.opacity(0.1))
                    .frame(width: 50, height: 50)

                Image(systemName: isCheapest ? "star.fill" : "building.2.fill")
                    .foregroundColor(isCheapest ? .green : .blue)
            }

            // Store info
            VStack(alignment: .leading, spacing: 4) {
                Text(store.name)
                    .font(.body)
                    .fontWeight(.semibold)

                Text(store.address)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if let distance = store.distanceInMiles {
                    Text(Constants.formatDistance(distance))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Price
            VStack(alignment: .trailing, spacing: 4) {
                if let price = store.price {
                    Text(Constants.formatPrice(price))
                        .font(.headline)
                        .foregroundColor(isCheapest ? .green : .primary)

                    // Show price source badge
                    if let priceSource = store.priceSource {
                        if priceSource == "chain_estimate" {
                            Text("Est.")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                } else {
                    Text("Price unavailable")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                if let difference = priceDifference, difference > 0 {
                    Text("+\(Constants.formatPrice(difference))")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if isCheapest {
                    Text("Best price")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    NavigationStack {
        PriceComparisonView(viewModel: {
            let vm = PriceComparisonViewModel()
            vm.priceComparison = .sample
            return vm
        }())
    }
}
