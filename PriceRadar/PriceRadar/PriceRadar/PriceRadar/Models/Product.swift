//
//  Product.swift
//  PriceRadar
//
//  Data model representing a product
//

import Foundation

struct Product: Identifiable, Codable, Equatable {
    let id: String // UPC/barcode
    let name: String
    let brand: String?
    let category: String?
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case id = "barcode"
        case name
        case brand
        case category
        case imageURL = "image_url"
    }
}

// MARK: - API Initializers
extension Product {
    /// Initialize from Open Food Facts API response (PRIMARY SOURCE)
    init(barcode: String, offProduct: OFFProduct) {
        self.init(
            id: barcode,
            name: offProduct.displayName,
            brand: offProduct.displayBrand,
            category: offProduct.categories ?? "General",
            imageURL: offProduct.image_small_url
        )
    }

    /// Initialize from Barcode Monster API response (SECONDARY - for autofill)
    init(barcode: String, barcodeMonsterProduct: BarcodeMonsterProduct) {
        self.init(
            id: barcode,
            name: barcodeMonsterProduct.name,
            brand: barcodeMonsterProduct.brand,
            category: barcodeMonsterProduct.category ?? "General",
            imageURL: nil  // Barcode Monster doesn't provide images
        )
    }

    /// Initialize from user input (FALLBACK - manual entry)
    init(barcode: String, userEnteredName: String) {
        self.init(
            id: barcode,
            name: userEnteredName,
            brand: "Unknown",
            category: "User Added",
            imageURL: nil
        )
    }
}

// MARK: - Sample Data for Previews
extension Product {
    static let sample = Product(
        id: "012000161551",
        name: "Coca-Cola Classic 12 Pack",
        brand: "Coca-Cola",
        category: "Beverages",
        imageURL: nil
    )

    static let samples = [
        Product(
            id: "012000161551",
            name: "Coca-Cola Classic 12 Pack",
            brand: "Coca-Cola",
            category: "Beverages",
            imageURL: nil
        ),
        Product(
            id: "028400064316",
            name: "Lay's Classic Potato Chips",
            brand: "Lay's",
            category: "Snacks",
            imageURL: nil
        ),
        Product(
            id: "037000850076",
            name: "Tide Original Scent Liquid Laundry Detergent",
            brand: "Tide",
            category: "Household",
            imageURL: nil
        )
    ]
}
