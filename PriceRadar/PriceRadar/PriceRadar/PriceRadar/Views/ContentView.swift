//
//  ContentView.swift
//  PriceRadar
//
//  Main view with tab navigation
//

import SwiftUI

struct ContentView: View {
    @StateObject private var priceComparisonViewModel = PriceComparisonViewModel()

    var body: some View {
        TabView {
            ScannerView(priceComparisonViewModel: priceComparisonViewModel)
                .tabItem {
                    Label("Scan", systemImage: "barcode.viewfinder")
                }

            SearchView(priceComparisonViewModel: priceComparisonViewModel)
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
        }
    }
}

#Preview {
    ContentView()
}
