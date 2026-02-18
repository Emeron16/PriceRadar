//
//  MapView.swift
//  PriceRadar
//
//  Map view showing stores with prices
//

import SwiftUI
import MapKit

struct MapView: View {
    @ObservedObject var comparisonViewModel: PriceComparisonViewModel  // Single source of truth
    @StateObject private var viewModel = MapViewModel()
    @State private var selectedStore: Store?

    // Get comparison from ViewModel (reactive)
    private var comparison: PriceComparison? {
        comparisonViewModel.priceComparison
    }

    // Use the ViewModel's search radius (single source of truth)
    private var selectedRadius: Double {
        comparisonViewModel.searchRadius
    }

    private var filteredStores: [Store] {
        guard let comparison = comparison else { return [] }
        return comparison.stores.filter { store in
            guard let distance = store.distanceInMiles else { return true }
            return distance <= selectedRadius
        }
    }

    var body: some View {
        Group {
            if let comparison = comparison {
                ZStack(alignment: .bottom) {
                    // Map
                    Map(coordinateRegion: $viewModel.region, showsUserLocation: true, annotationItems: filteredStores) { store in
                        MapAnnotation(coordinate: store.coordinate) {
                            StoreMapPin(
                                store: store,
                                isCheapest: store.id == comparison.cheapestStore?.id,
                                isSelected: selectedStore?.id == store.id
                            )
                            .onTapGesture {
                                selectedStore = store
                            }
                        }
                    }
                    .ignoresSafeArea()

                    // Store count indicator (top)
                    VStack {
                        HStack {
                            Text("\(filteredStores.count) stores within \(Int(selectedRadius)) mi")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(20)
                            Spacer()
                        }
                        .padding()
                        Spacer()
                    }

                    // Selected store card
                    if let store = selectedStore {
                        StoreDetailCard(store: store, comparison: comparison)
                            .transition(.move(edge: .bottom))
                            .animation(.spring(), value: selectedStore)
                    }
                }
                .onAppear {
                    viewModel.updateWithComparison(comparison, radius: selectedRadius)
                }
                .onChange(of: comparison.stores.count) { oldCount, newCount in
                    print("🗺️ MAP VIEW: Store count changed from \(oldCount) to \(newCount) - updating region")
                    viewModel.updateWithComparison(comparison, radius: selectedRadius)
                }
            } else {
                // Loading state
                VStack {
                    ProgressView()
                    Text("Loading map...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Store Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { updateRadius(5.0) }) {
                        Label("5 miles", systemImage: selectedRadius == 5.0 ? "checkmark" : "")
                    }
                    Button(action: { updateRadius(10.0) }) {
                        Label("10 miles", systemImage: selectedRadius == 10.0 ? "checkmark" : "")
                    }
                    Button(action: { updateRadius(20.0) }) {
                        Label("20 miles", systemImage: selectedRadius == 20.0 ? "checkmark" : "")
                    }
                    Button(action: { updateRadius(50.0) }) {
                        Label("50 miles", systemImage: selectedRadius == 50.0 ? "checkmark" : "")
                    }
                } label: {
                    Label("\(Int(selectedRadius)) mi", systemImage: "location.circle")
                }
            }
        }
    }

    private func updateRadius(_ radius: Double) {
        print("🗺️🗺️🗺️ MAP VIEW RADIUS CHANGED: \(radius) miles 🗺️🗺️🗺️")
        comparisonViewModel.searchRadius = radius
        Task {
            await comparisonViewModel.refresh()
        }
    }
}

// MARK: - Store Map Pin
struct StoreMapPin: View {
    let store: Store
    let isCheapest: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Price tag
            if let price = store.price {
                Text(Constants.formatPrice(price))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isCheapest ? Color.green : Color.blue)
                    .cornerRadius(8)
            }

            // Pin icon
            Image(systemName: isCheapest ? "star.circle.fill" : "mappin.circle.fill")
                .font(.title)
                .foregroundColor(isCheapest ? .green : .blue)
                .background(
                    Circle()
                        .fill(.white)
                        .frame(width: 30, height: 30)
                )
                .scaleEffect(isSelected ? 1.3 : 1.0)
                .animation(.spring(), value: isSelected)
        }
    }
}

// MARK: - Store Detail Card
struct StoreDetailCard: View {
    let store: Store
    let comparison: PriceComparison
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.name)
                        .font(.headline)

                    Text(store.address)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { openInMaps() }) {
                    Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }

            Divider()

            HStack(spacing: 20) {
                if let price = store.price {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Price")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(Constants.formatPrice(price))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(store.id == comparison.cheapestStore?.id ? .green : .primary)
                    }
                }

                if let distance = store.distanceInMiles {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Distance")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(Constants.formatDistance(distance))
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                }

                if let difference = comparison.priceDifference(for: store) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("vs Best")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(Constants.formatPriceDifference(difference))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(difference == 0 ? .green : .orange)
                    }
                }
            }

            Button(action: openInMaps) {
                HStack {
                    Image(systemName: "location.fill")
                    Text("Get Directions")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(Constants.cornerRadius)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Constants.cornerRadius)
                .fill(.ultraThinMaterial)
        )
        .padding()
        .shadow(radius: 10)
    }

    private func openInMaps() {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: store.coordinate))
        mapItem.name = store.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
}

#Preview {
    NavigationStack {
        let vm: PriceComparisonViewModel = {
            let viewModel = PriceComparisonViewModel()
            viewModel.priceComparison = .sample
            return viewModel
        }()
        return MapView(comparisonViewModel: vm)
    }
}
