//
//  PriceSubmissionView.swift
//  PriceRadar
//
//  Form for users to submit crowd-sourced pricing data
//

import SwiftUI
import Combine
import MapKit
import CoreLocation

struct PriceSubmissionView: View {
    let product: Product
    let stores: [Store]
    var preselectedStore: Store? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = PriceSubmissionViewModel()

    @State private var selectedStore: Store?
    @State private var priceInput: String = ""
    @State private var showStorePicker = false

    init(product: Product, stores: [Store], preselectedStore: Store? = nil) {
        self.product = product
        self.stores = stores
        self.preselectedStore = preselectedStore
        self._selectedStore = State(initialValue: preselectedStore)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Product Section (autofilled)
                Section("Product") {
                    HStack {
                        // Product image or placeholder
                        if let imageURL = product.imageURL, let url = URL(string: imageURL) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } placeholder: {
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                            }
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 60, height: 60)
                                Image(systemName: "barcode")
                                    .foregroundColor(.gray)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(product.name)
                                .font(.headline)
                            if let brand = product.brand {
                                Text(brand)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text(product.category ?? "General")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                }

                // Store Selection
                Section("Select Store") {
                    if let selected = selectedStore {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selected.name)
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text(selected.address)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if let distance = selected.distanceInMiles {
                                    Text(Constants.formatDistance(distance))
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                            }

                            Spacer()

                            Button("Change") {
                                showStorePicker = true
                            }
                            .font(.caption)
                        }
                    } else {
                        Button(action: { showStorePicker = true }) {
                            HStack {
                                Image(systemName: "building.2")
                                    .foregroundColor(.blue)
                                Text("Choose a store")
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Price Input
                Section("Enter Price") {
                    HStack {
                        Text("$")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        TextField("0.00", text: $priceInput)
                            .keyboardType(.decimalPad)
                            .font(.title2)
                            .fontWeight(.medium)
                    }

                    Text("Enter the exact price you see on the shelf or receipt")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Gamification Info
                Section {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                        Text("Earn 10 points for submitting")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Reward")
                }

                // Submit Button
                Section {
                    Button(action: submitPrice) {
                        HStack {
                            Spacer()
                            if viewModel.isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Submit Price")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                    }
                    .listRowBackground(isFormValid ? Color.green : Color.gray)
                    .disabled(!isFormValid || viewModel.isSubmitting)
                }
            }
            .navigationTitle("Report Price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showStorePicker) {
                StorePickerView(stores: stores, selectedStore: $selectedStore)
            }
            .alert("Success!", isPresented: $viewModel.showSuccessAlert) {
                Button("Great!") {
                    dismiss()
                }
            } message: {
                Text("You earned 10 points! Thanks for helping the community.")
            }
            .alert("Error", isPresented: $viewModel.showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "Failed to submit price. Please try again.")
            }
        }
    }

    private var isFormValid: Bool {
        guard let _ = selectedStore,
              let price = Double(priceInput),
              price > 0 else {
            return false
        }
        return true
    }

    private func submitPrice() {
        guard let store = selectedStore,
              let price = Double(priceInput),
              price > 0 else {
            return
        }

        Task {
            await viewModel.submitPrice(
                barcode: product.id,
                productName: product.name,
                store: store,
                price: price
            )
        }
    }
}

// MARK: - Store Picker Sheet
struct StorePickerView: View {
    let stores: [Store]
    @Binding var selectedStore: Store?
    @Environment(\.dismiss) private var dismiss

    @StateObject private var searchViewModel = StoreSearchViewModel()
    @State private var searchText = ""

    var displayStores: [Store] {
        if searchText.isEmpty {
            return stores + searchViewModel.searchResults
        } else {
            return searchViewModel.searchResults
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search for stores (e.g., Walmart, Target)", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            searchViewModel.clearSearch()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding()
                .onChange(of: searchText) { oldValue, newValue in
                    if !newValue.isEmpty {
                        Task {
                            await searchViewModel.searchStores(query: newValue)
                        }
                    } else {
                        searchViewModel.clearSearch()
                    }
                }

                // Store list
                if searchViewModel.isSearching {
                    VStack {
                        ProgressView()
                            .padding()
                        Text("Searching for stores...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else if displayStores.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Stores Nearby" : "No Stores Found",
                        systemImage: "building.2.crop.circle",
                        description: Text(searchText.isEmpty ? "Use the search bar above to find stores" : "Try a different search term")
                    )
                } else {
                    List {
                        // Section for nearby stores (if any)
                        if !stores.isEmpty && searchText.isEmpty {
                            Section("Nearby Stores") {
                                ForEach(stores) { store in
                                    storeRow(store: store)
                                }
                            }
                        }

                        // Section for search results
                        if !searchViewModel.searchResults.isEmpty {
                            Section(searchText.isEmpty ? "Other Stores" : "Search Results") {
                                ForEach(searchViewModel.searchResults) { store in
                                    storeRow(store: store)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Select Store")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func storeRow(store: Store) -> some View {
        Button(action: {
            selectedStore = store
            dismiss()
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.name)
                        .font(.body)
                        .foregroundColor(.primary)
                    Text(store.address)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let distance = store.distanceInMiles {
                        Text(Constants.formatDistance(distance))
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }

                Spacer()

                if selectedStore?.id == store.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
        }
    }
}

// MARK: - Store Search ViewModel
@MainActor
class StoreSearchViewModel: ObservableObject {
    @Published var searchResults: [Store] = []
    @Published var isSearching = false

    private let locationService = LocationService()

    func searchStores(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true

        // Get user location for search
        let userLocation = locationService.currentLocation?.coordinate ??
                          CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: userLocation,
            latitudinalMeters: 50000,  // ~31 miles radius
            longitudinalMeters: 50000
        )

        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()

            // Convert MKMapItems to Store objects
            let stores = response.mapItems.compactMap { mapItem -> Store? in
                guard let name = mapItem.name,
                      let location = mapItem.placemark.location else {
                    return nil
                }

                // Extract chain name from the store name
                let chain = extractChainName(from: name)

                // Build address string
                let placemark = mapItem.placemark
                let addressComponents = [
                    placemark.thoroughfare,
                    placemark.subThoroughfare,
                    placemark.locality,
                    placemark.administrativeArea,
                    placemark.postalCode
                ].compactMap { $0 }
                let address = addressComponents.joined(separator: ", ")

                // Calculate distance from user
                let userLoc = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
                let storeDistance = userLoc.distance(from: location) / 1609.34  // Convert to miles

                return Store(
                    id: "search_\(UUID().uuidString)",
                    name: name,
                    chain: chain,
                    address: address.isEmpty ? "Address unavailable" : address,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    price: nil,
                    distanceInMiles: storeDistance
                )
            }

            // Sort by distance
            searchResults = stores.sorted { ($0.distanceInMiles ?? 999) < ($1.distanceInMiles ?? 999) }

            print("🔍 Found \(searchResults.count) stores for query: \(query)")

        } catch {
            print("❌ Store search error: \(error.localizedDescription)")
            searchResults = []
        }

        isSearching = false
    }

    func clearSearch() {
        searchResults = []
        isSearching = false
    }

    /// Extract chain name from full store name (e.g., "Walmart Supercenter" -> "Walmart")
    private func extractChainName(from name: String) -> String {
        let knownChains = ["Walmart", "Target", "Safeway", "CVS", "Walgreens",
                          "Kroger", "Whole Foods", "Costco", "Sam's Club",
                          "Trader Joe's", "Aldi", "Food Lion", "Publix",
                          "Stop & Shop", "Giant", "ShopRite", "Wegmans"]

        for chain in knownChains {
            if name.lowercased().contains(chain.lowercased()) {
                return chain
            }
        }

        // If no known chain, use first word of name
        return name.components(separatedBy: " ").first ?? name
    }
}

// MARK: - ViewModel
@MainActor
class PriceSubmissionViewModel: ObservableObject {
    @Published var isSubmitting = false
    @Published var showSuccessAlert = false
    @Published var showErrorAlert = false
    @Published var errorMessage: String?

    func submitPrice(
        barcode: String,
        productName: String,
        store: Store,
        price: Double
    ) async {
        isSubmitting = true

        do {
            try await FirebaseService.shared.submitPrice(
                barcode: barcode,
                productName: productName,
                storeId: store.id,
                storeName: store.name,
                chain: store.chain,
                price: price,
                latitude: store.latitude,
                longitude: store.longitude,
                address: store.address
            )

            isSubmitting = false
            showSuccessAlert = true
            print("✅ Price submitted successfully!")

        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
            showErrorAlert = true
            print("❌ Error submitting price: \(error)")
        }
    }
}

// MARK: - Preview
#Preview {
    PriceSubmissionView(
        product: .sample,
        stores: Store.samples
    )
}
