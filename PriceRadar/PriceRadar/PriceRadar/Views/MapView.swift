//
//  MapView.swift
//  PriceRadar
//
//  Map view showing stores with prices
//

import SwiftUI
import MapKit

struct MapView: View {
    let comparison: PriceComparison
    @StateObject private var viewModel = MapViewModel()
    @State private var selectedStore: Store?

    var body: some View {
        ZStack(alignment: .bottom) {
            // Map
            Map(coordinateRegion: $viewModel.region, annotationItems: comparison.stores) { store in
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

            // Selected store card
            if let store = selectedStore {
                StoreDetailCard(store: store, comparison: comparison)
                    .transition(.move(edge: .bottom))
                    .animation(.spring(), value: selectedStore)
            }
        }
        .navigationTitle("Store Map")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.updateWithComparison(comparison)
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
        let placemark = MKPlacemark(coordinate: store.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = store.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
}

#Preview {
    NavigationStack {
        MapView(comparison: .sample)
    }
}
