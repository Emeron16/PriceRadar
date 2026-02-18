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
    @State private var showCrowdsourcePrompt = false

    // Function to change search radius and refresh results
    private func changeRadius(_ newRadius: Double) {
        viewModel.searchRadius = newRadius
        print("🔄🔄🔄 RADIUS CHANGED: \(newRadius) miles 🔄🔄🔄")
        Task {
            await viewModel.refresh()
        }
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if let comparison = viewModel.priceComparison {
                resultsView(comparison: comparison)
            } else if let errorMessage = viewModel.errorMessage {
                errorView(message: errorMessage)
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
                        // Sort options
                        Menu("Sort By") {
                            Button(action: { viewModel.changeSortOption(.price) }) {
                                Label("Price", systemImage: viewModel.sortBy == .price ? "checkmark" : "")
                            }
                            Button(action: { viewModel.changeSortOption(.distance) }) {
                                Label("Distance", systemImage: viewModel.sortBy == .distance ? "checkmark" : "")
                            }
                        }

                        Divider()

                        // Radius options
                        Menu("Search Radius") {
                            Button(action: { changeRadius(2.0) }) {
                                Label("2 miles", systemImage: viewModel.searchRadius == 2.0 ? "checkmark" : "")
                            }
                            Button(action: { changeRadius(5.0) }) {
                                Label("5 miles (Default)", systemImage: viewModel.searchRadius == 5.0 ? "checkmark" : "")
                            }
                            Button(action: { changeRadius(10.0) }) {
                                Label("10 miles", systemImage: viewModel.searchRadius == 10.0 ? "checkmark" : "")
                            }
                            Button(action: { changeRadius(25.0) }) {
                                Label("25 miles", systemImage: viewModel.searchRadius == 25.0 ? "checkmark" : "")
                            }
                            Button(action: { changeRadius(50.0) }) {
                                Label("50 miles", systemImage: viewModel.searchRadius == 50.0 ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
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

            // Crowdsourcing banner (when needed)
            if viewModel.needsCrowdsourcing {
                crowdsourcingBanner
                    .padding()
            }

            // Statistics (only if we have stores with prices)
            if !comparison.stores.isEmpty && comparison.stores.contains(where: { $0.price != nil }) {
                statisticsSection(comparison: comparison)
            }

            // Store list or empty state
            if comparison.stores.isEmpty {
                emptyStoresView
            } else {
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
                NavigationLink(destination: MapView(comparisonViewModel: viewModel)) {
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
    }

    // MARK: - Empty Stores View
    private var emptyStoresView: some View {
        VStack(spacing: 20) {
            Image(systemName: "storefront")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No stores found nearby")
                .font(.headline)

            Text("Try searching in a different area or help us by adding prices!")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if viewModel.needsCrowdsourcing {
                Button(action: { showCrowdsourcePrompt = true }) {
                    HStack {
                        Image(systemName: "star.fill")
                        Text("Report Price")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(Constants.cornerRadius)
                    .padding(.horizontal, 40)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Crowdsourcing Banner
    private var crowdsourcingBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                Text("Help Improve Pricing")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            Text("Know the price at a nearby store? Help the community by adding it!")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: { showCrowdsourcePrompt = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Price at Store")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
        .sheet(isPresented: $showCrowdsourcePrompt) {
            if let product = viewModel.productForCrowdsourcing,
               let comparison = viewModel.priceComparison {
                PriceSubmissionView(
                    product: product,
                    stores: comparison.stores
                )
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

    @State private var showStoreDetail = false

    var body: some View {
        Button(action: { showStoreDetail = true }) {
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
                        .foregroundColor(.primary)

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

                // Chevron indicator
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showStoreDetail) {
            StoreDetailView(store: store, isCheapest: isCheapest)
        }
    }
}

// MARK: - Store Detail View
struct StoreDetailView: View {
    let store: Store
    let isCheapest: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                // Store Header
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(isCheapest ? Color.green.opacity(0.2) : Color.blue.opacity(0.1))
                                    .frame(width: 60, height: 60)

                                Image(systemName: isCheapest ? "star.fill" : "building.2.fill")
                                    .font(.title2)
                                    .foregroundColor(isCheapest ? .green : .blue)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.name)
                                    .font(.title3)
                                    .fontWeight(.bold)

                                if isCheapest {
                                    Text("Best Price")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.1))
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Price Info
                if let price = store.price {
                    Section("Price") {
                        HStack {
                            Text("Current Price")
                            Spacer()
                            Text(Constants.formatPrice(price))
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(isCheapest ? .green : .primary)
                        }

                        if let priceSource = store.priceSource {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                                Text(priceSource)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let confidence = store.confidenceScore {
                            HStack {
                                Text("Confidence")
                                Spacer()
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(store.confidenceColor)
                                        .frame(width: 8, height: 8)
                                    Text("\(Int(confidence * 100))%")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                // Location Info
                Section("Location") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(.red)
                            Text(store.address)
                                .font(.body)
                        }

                        if let distance = store.distanceInMiles {
                            HStack {
                                Image(systemName: "location.fill")
                                    .foregroundColor(.blue)
                                Text(Constants.formatDistance(distance))
                                    .font(.body)
                            }
                        }
                    }
                }

                // Actions
                Section {
                    Button(action: openInMaps) {
                        HStack {
                            Image(systemName: "map.fill")
                                .foregroundColor(.blue)
                            Text("Get Directions")
                                .fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button(action: { dismiss() }) {
                        HStack {
                            Image(systemName: "phone.fill")
                                .foregroundColor(.green)
                            Text("Call Store")
                                .fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Store Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func openInMaps() {
        let latitude = store.latitude
        let longitude = store.longitude
        let name = store.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? store.name

        // Try Apple Maps first
        if let url = URL(string: "maps://?daddr=\(latitude),\(longitude)&saddr=Current+Location") {
            openURL(url)
        } else if let url = URL(string: "http://maps.apple.com/?daddr=\(latitude),\(longitude)&saddr=Current+Location") {
            openURL(url)
        }
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
