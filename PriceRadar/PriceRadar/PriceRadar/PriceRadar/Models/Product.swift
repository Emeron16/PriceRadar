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
