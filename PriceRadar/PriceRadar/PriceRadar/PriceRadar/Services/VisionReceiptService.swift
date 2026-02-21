//
//  VisionReceiptService.swift
//  PriceRadar
//
//  Receipt OCR using Apple Vision framework — no API key required, works offline.
//

import Foundation
import UIKit
import Vision

class VisionReceiptService {
    static let shared = VisionReceiptService()

    private init() {
        print("🧾 VisionReceiptService initialized (Apple Vision, no API key needed)")
    }

    // MARK: - Public API

    func processReceipt(image: UIImage) async throws -> ReceiptPrediction {
        // Normalize image orientation so Vision reads top-to-bottom correctly
        let normalizedImage = image.normalized()

        let observations = try await recognizeText(from: normalizedImage)

        // Only throw if Vision returned no text at all (truly unreadable image)
        guard !observations.isEmpty else {
            throw ReceiptOCRError.invalidResponse
        }

        // Vision bounding box origin is bottom-left, so sort descending minY = top-to-bottom
        let sorted = observations.sorted { $0.boundingBox.minY > $1.boundingBox.minY }
        let lines: [String] = sorted.compactMap { $0.topCandidates(1).first?.string }

        guard !lines.isEmpty else {
            throw ReceiptOCRError.invalidResponse
        }

        print("🔍 Vision OCR extracted \(lines.count) text lines:")
        lines.enumerated().forEach { print("  [\($0.offset)] \($0.element)") }

        let lineItems = parseLineItems(from: sorted)
        let merchantName = extractMerchantName(from: lines)
        let total = extractTotal(from: lines)
        let tax = extractTax(from: lines)
        let dateString = extractDate(from: lines)
        let address = extractAddress(from: lines)

        print("📝 Parsed \(lineItems.count) line items")
        print("🏪 Merchant: \(merchantName ?? "Unknown")")
        print("💰 Total: \(total.map { "$\(String(format: "%.2f", $0))" } ?? "Unknown")")

        return ReceiptPrediction(
            supplier_name: merchantName.map { ReceiptField(value: $0) },
            supplier_address: address.map { ReceiptField(value: $0) },
            date: dateString.map { ReceiptField(value: $0) },
            time: nil,
            total_amount: total.map { ReceiptAmountField(value: $0) },
            total_tax: tax.map { ReceiptAmountField(value: $0) },
            line_items: lineItems.isEmpty ? nil : lineItems
        )
    }

    // MARK: - Vision Text Recognition

    private func recognizeText(from image: UIImage) async throws -> [VNRecognizedTextObservation] {
        guard let cgImage = image.cgImage else {
            throw ReceiptOCRError.imageCompressionFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                continuation.resume(returning: observations)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false  // Disable for receipts — product names aren't natural language

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Line Item Parsing

    /// Lines that are definitely not product items
    private let skipPatterns: [NSRegularExpression] = [
        // Store totals / tax
        try! NSRegularExpression(pattern: #"(?i)^\s*(subtotal|sub-total|total|no\s+tax|tax|gst|hst|pst|vat|change|balance)"#),
        // Payment methods and network charges
        try! NSRegularExpression(pattern: #"(?i)\b(cash|card|visa|mastercard|amex|discover|debit|credit|payment|paid|approved|network\s+charge|charge)\b"#),
        // Receipt footer / store admin
        try! NSRegularExpression(pattern: #"(?i)\b(thank|thanks|cashier|operator|register|terminal|loyalty|reward|points|member|survey|return|policy|refund|when\s+you|will\s+not|promotional|original\s+order)\b"#),
        // URLs and emails
        try! NSRegularExpression(pattern: #"(?i)(www\.|https?://|\.com|\.net|\.org|@)"#),
        // Phone numbers
        try! NSRegularExpression(pattern: #"\b\d{3}[-.\s]\d{3}[-.\s]\d{4}\b"#),
        // Store/register/transaction codes
        try! NSRegularExpression(pattern: #"(?i)\b(str|reg|trn|ref|auth|appr|seq|tran|inv|acct|rec|aid|auth\s+code)[\s#:]*\d*"#),
        // Lines that are purely a code
        try! NSRegularExpression(pattern: #"^\*?\d{4,}[A-Z]?$"#),
        try! NSRegularExpression(pattern: #"^[A-Z]{2,4}:\s"#),
        // Date/time lines
        try! NSRegularExpression(pattern: #"\b\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4}\b"#),
        try! NSRegularExpression(pattern: #"\b\d{1,2}:\d{2}(:\d{2})?\s*(AM|PM)?\b"#),
        // Quantity/unit lines (e.g., "2 @ $4.79 ea", "2 0 $4.79 ea" — OCR misreads @ as 0)
        // Use \s+ to require whitespace around the separator — prevents matching barcodes like "071050315"
        try! NSRegularExpression(pattern: #"^\d{1,3}\s+[@0oO]\s+\$?\d"#),
        try! NSRegularExpression(pattern: #"(?i)^\d{1,3}\s+[@0oO]\s+\$?\d.*\b(ea|each|lb|oz|pk)\s*$"#),
        // Category headers (e.g., "GROCERY", "NF")
        try! NSRegularExpression(pattern: #"(?i)^\s*(grocery|produce|bakery|deli|dairy|frozen|beverage|household|personal|nf|wic)\s*[\(]?\s*$"#),
        // City, State lines (e.g., "Brooklyn, New York", "Brooklyn. New York", "Brooklyn NY 11234")
        // OCR sometimes reads comma as period/space, so match flexibly
        try! NSRegularExpression(pattern: #"(?i)^[A-Za-z][A-Za-z\s'1]+[,\.\s]\s*(New York|California|Texas|Florida|Illinois|Pennsylvania|Ohio|Georgia|Michigan|New Jersey|Washington|[A-Z]{2}\s*\d{0,5})\b"#),
        // Lines containing a ZIP or ZIP+4 code embedded (address continuation lines)
        try! NSRegularExpression(pattern: #"\b\d{5}(-\d{4})?\b"#),
        // Trailing-comma city fragments (e.g., "Brook 1yn," — OCR city name split across lines)
        try! NSRegularExpression(pattern: #"^[A-Za-z0-9][A-Za-z0-9\s]+,\s*$"#),
        // ZIP codes alone or zip+4
        try! NSRegularExpression(pattern: #"^\d{5}(-\d{4})?$"#),
        // "ITEMS SOLD", discount lines
        try! NSRegularExpression(pattern: #"(?i)\b(items?\s*(sold)?|savings?|you\s+saved|sale|coupon|discount)\b"#),
    ]

    private func shouldSkip(_ line: String) -> Bool {
        let range = NSRange(line.startIndex..., in: line)
        for (idx, pattern) in skipPatterns.enumerated() {
            if pattern.firstMatch(in: line, range: range) != nil {
                print("  🚫 skip[\(idx)] matched: '\(line)'")
                return true
            }
        }
        return false
    }

    /// Parse line items — handles both "ITEM NAME  $X.XX" and "ITEM NAME\n$X.XX" layouts
    private func parseLineItems(from observations: [VNRecognizedTextObservation]) -> [LineItemPrediction] {
        // Price pattern: optional $, digits, dot, exactly 2 digits — anchored to end of meaningful content
        let priceRegex = try! NSRegularExpression(pattern: #"\$?\s*(\d{1,3}(?:,\d{3})*\.\d{2})\s*[A-Z]?\s*$"#)
        // Price-only line: the entire line is just a price
        let priceOnlyRegex = try! NSRegularExpression(pattern: #"^\s*\$?\s*(\d{1,3}(?:,\d{3})*\.\d{2})\s*[A-Z]?\s*$"#)

        struct ParsedLine {
            let text: String
            let price: Double?
            let isPriceOnly: Bool
        }

        let parsed: [ParsedLine] = observations.compactMap { obs in
            guard let text = obs.topCandidates(1).first?.string else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }

            let fullRange = NSRange(trimmed.startIndex..., in: trimmed)
            let isPriceOnly = priceOnlyRegex.firstMatch(in: trimmed, range: fullRange) != nil
            let price = extractPriceValue(from: trimmed, using: priceRegex)
            return ParsedLine(text: trimmed, price: price, isPriceOnly: isPriceOnly)
        }

        var results: [LineItemPrediction] = []
        var claimedIndices = Set<Int>()  // Track which indices have been consumed
        var i = 0

        print("🔎 Parsing \(parsed.count) lines:")
        parsed.enumerated().forEach { idx, p in
            let priceStr = p.price.map { String(format: "%.2f", $0) } ?? "nil"
            print("  [\(idx)] text='\(p.text)' price=\(priceStr) isPriceOnly=\(p.isPriceOnly) skip=\(shouldSkip(p.text))")
        }

        while i < parsed.count {
            let current = parsed[i]

            // Skip known non-item lines
            if shouldSkip(current.text) {
                print("⏭️ [\(i)] SKIP: '\(current.text)'")
                i += 1
                continue
            }

            // Pattern A: Line contains both description and price (e.g., "MILK 2% GALLON  3.99")
            if let price = current.price, !current.isPriceOnly {
                let description = stripPriceFromEnd(from: current.text, using: priceRegex)
                    .trimmingCharacters(in: .whitespaces)
                if isValidDescription(description) {
                    print("✅ [\(i)] Pattern A: '\(description)' @ $\(price)")
                    results.append(LineItemPrediction(
                        description: description,
                        quantity: 1.0,
                        total_amount: price,
                        unit_price: price
                    ))
                    claimedIndices.insert(i)
                    i += 1
                    continue
                }
            }

            // Pattern B: Description line, then 1-3 intervening lines (tax codes, qty), then price-only line
            // e.g.: "071050315 SUNCHIPS" → "NF" → "$9.58"
            if isValidDescription(current.text) && !current.isPriceOnly {
                var found = false
                var lookahead = i + 1
                while lookahead < parsed.count && lookahead <= i + 3 {
                    let candidate = parsed[lookahead]
                    if candidate.isPriceOnly, let price = candidate.price, !shouldSkip(candidate.text) {
                        print("✅ [\(i)] Pattern B: '\(current.text)' @ $\(price) (price at [\(lookahead)])")
                        results.append(LineItemPrediction(
                            description: current.text.trimmingCharacters(in: .whitespaces),
                            quantity: 1.0,
                            total_amount: price,
                            unit_price: price
                        ))
                        claimedIndices.insert(i)
                        claimedIndices.insert(lookahead)
                        i = lookahead + 1
                        found = true
                        break
                    }
                    // Only skip over short tax-code lines (≤3 chars) or explicitly skippable lines
                    let isInterveningCode = candidate.text.trimmingCharacters(in: .whitespaces).count <= 3
                        || shouldSkip(candidate.text)
                    if isInterveningCode {
                        print("  ↔️ B lookahead [\(lookahead)] intervening: '\(candidate.text)'")
                        lookahead += 1
                    } else {
                        print("  🛑 B lookahead [\(lookahead)] blocked: '\(candidate.text)'")
                        break
                    }
                }
                if found { continue }
                print("❌ [\(i)] Pattern B miss for: '\(current.text)'")
            }

            // Pattern C: Price-only line followed by description (reversed column read order)
            // e.g.: "$9.58" → "071050315 SUNCHIPS"
            if current.isPriceOnly, let price = current.price, !shouldSkip(current.text) {
                var lookahead = i + 1
                var foundC = false
                while lookahead < parsed.count && lookahead <= i + 2 {
                    let candidate = parsed[lookahead]
                    let alreadyClaimed = claimedIndices.contains(lookahead)
                    if isValidDescription(candidate.text) && !candidate.isPriceOnly && !shouldSkip(candidate.text) && !alreadyClaimed {
                        print("✅ [\(i)] Pattern C: '\(candidate.text)' @ $\(price) (desc at [\(lookahead)])")
                        results.append(LineItemPrediction(
                            description: candidate.text.trimmingCharacters(in: .whitespaces),
                            quantity: 1.0,
                            total_amount: price,
                            unit_price: price
                        ))
                        claimedIndices.insert(i)
                        claimedIndices.insert(lookahead)
                        i = lookahead + 1
                        foundC = true
                        break
                    } else {
                        print("  ❌ C lookahead [\(lookahead)] rejected: '\(candidate.text)' validDesc=\(isValidDescription(candidate.text)) isPriceOnly=\(candidate.isPriceOnly) skip=\(shouldSkip(candidate.text)) claimed=\(alreadyClaimed)")
                    }
                    // Only step over short codes (NF, F, T) between price and description
                    if candidate.text.trimmingCharacters(in: .whitespaces).count <= 3 && !isValidDescription(candidate.text) {
                        lookahead += 1
                    } else {
                        break
                    }
                }
                if foundC { continue }
                if !foundC {
                    print("❌ [\(i)] Pattern C miss for price $\(price)")
                }
            }

            print("⏩ [\(i)] No pattern matched: '\(current.text)'")
            i += 1
        }

        return results
    }

    /// A valid item description must be at least 3 chars, not all-numeric, not a lone letter
    private func isValidDescription(_ text: String) -> Bool {
        guard text.count >= 3 else { return false }
        // Not purely numeric (store numbers, barcodes)
        guard !text.allSatisfy({ $0.isNumber || $0 == "," || $0 == "." || $0 == "-" }) else { return false }
        // Must contain at least one letter
        guard text.contains(where: { $0.isLetter }) else { return false }
        return true
    }

    // MARK: - Merchant Name Extraction

    /// Known store brand names to look for anywhere in the receipt
    private let knownStores: [String: String] = [
        "target": "Target",
        "walmart": "Walmart",
        "costco": "Costco",
        "kroger": "Kroger",
        "safeway": "Safeway",
        "whole foods": "Whole Foods",
        "trader joe": "Trader Joe's",
        "cvs": "CVS",
        "walgreens": "Walgreens",
        "rite aid": "Rite Aid",
        "publix": "Publix",
        "aldi": "ALDI",
        "lidl": "Lidl",
        "wegmans": "Wegmans",
        "meijer": "Meijer",
        "heb": "H-E-B",
        "food lion": "Food Lion",
        "stop & shop": "Stop & Shop",
        "giant": "Giant",
        "harris teeter": "Harris Teeter",
        "sprouts": "Sprouts",
        "dollar tree": "Dollar Tree",
        "dollar general": "Dollar General",
        "family dollar": "Family Dollar",
        "best buy": "Best Buy",
        "home depot": "Home Depot",
        "lowe's": "Lowe's",
        "lowes": "Lowe's",
    ]

    private func extractMerchantName(from lines: [String]) -> String? {
        let allText = lines.joined(separator: " ").lowercased()

        // 1. Look for a known store brand name anywhere in the receipt
        for (keyword, brandName) in knownStores {
            if allText.contains(keyword) {
                return brandName
            }
        }

        // 2. Prefer the first line that looks like "Store Name - phone" or "Store Name (location)"
        //    These are the richest store header lines (e.g., "Brooklyn Kings Hwy - 917-933-8856")
        let storeHeaderRegex = try! NSRegularExpression(pattern: #".{4,}\s*[-–]\s*\d{3}"#)
        let topLines = Array(lines.prefix(max(6, lines.count / 3)))

        for line in topLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if storeHeaderRegex.firstMatch(in: trimmed, range: range) != nil {
                // Strip the phone number suffix, keep the store name part
                let namePart = trimmed.components(separatedBy: " - ").first?
                    .components(separatedBy: " – ").first?
                    .trimmingCharacters(in: .whitespaces) ?? trimmed
                if namePart.count >= 4 { return namePart }
            }
        }

        // 3. Fallback: first line that has letters, isn't a pure address/price/code
        let priceRegex = try! NSRegularExpression(pattern: #"^\$?\d+\.\d{2}$"#)
        let addressRegex = try! NSRegularExpression(pattern: #"^\d+\s+[A-Za-z]"#)  // starts with street number
        let codeRegex = try! NSRegularExpression(pattern: #"^[A-Z0-9]{3,8}$"#)

        for line in topLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 4, trimmed.contains(where: { $0.isLetter }) else { continue }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if priceRegex.firstMatch(in: trimmed, range: range) != nil { continue }
            if addressRegex.firstMatch(in: trimmed, range: range) != nil { continue }
            if codeRegex.firstMatch(in: trimmed, range: range) != nil { continue }
            if shouldSkip(trimmed) { continue }
            return trimmed
        }

        return nil
    }

    // MARK: - Total / Tax / Date / Address

    private func extractTotal(from lines: [String]) -> Double? {
        let priceRegex = try! NSRegularExpression(pattern: #"\$?\s*(\d{1,3}(?:,\d{3})*\.\d{2})"#)
        var bestTotal: Double?

        for (i, line) in lines.enumerated() {
            let lower = line.lowercased().trimmingCharacters(in: .whitespaces)
            guard lower.contains("total") && !lower.contains("subtotal") && !lower.contains("sub-total") else { continue }

            // Price on same line (e.g., "TOTAL $9.58")
            if let price = extractPriceValue(from: line, using: priceRegex) {
                if bestTotal == nil || price > bestTotal! { bestTotal = price }
            }
            // Price on the very next line (e.g., "TOTAL\n$9.58")
            else if i + 1 < lines.count, let price = extractPriceValue(from: lines[i + 1], using: priceRegex) {
                if bestTotal == nil || price > bestTotal! { bestTotal = price }
            }
        }
        return bestTotal
    }

    private func extractTax(from lines: [String]) -> Double? {
        let priceRegex = try! NSRegularExpression(pattern: #"\$?\s*(\d{1,3}(?:,\d{3})*\.\d{2})"#)
        for line in lines {
            let lower = line.lowercased()
            guard lower.contains("tax") || lower.contains("gst") || lower.contains("hst") || lower.contains("vat") else { continue }
            if let price = extractPriceValue(from: line, using: priceRegex) {
                return price
            }
        }
        return nil
    }

    private func extractDate(from lines: [String]) -> String? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if let match = detector?.firstMatch(in: line, range: range), let date = match.date {
                // Sanity check: don't accept dates more than 30 days in the future
                if date <= Date().addingTimeInterval(30 * 86400) {
                    return formatter.string(from: date)
                }
            }
        }
        return nil
    }

    private func extractAddress(from lines: [String]) -> String? {
        // Street address: starts with a number followed by a street name word
        let addressRegex = try! NSRegularExpression(pattern: #"^\d+\s+[A-Za-z]"#)
        for line in lines.prefix(10) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if addressRegex.firstMatch(in: trimmed, range: range) != nil {
                return trimmed
            }
        }
        return nil
    }

    // MARK: - Helpers

    /// Extract the last price value from a string
    private func extractPriceValue(from text: String, using regex: NSRegularExpression) -> Double? {
        let range = NSRange(text.startIndex..., in: text)
        var lastMatch: NSTextCheckingResult?
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            lastMatch = match
        }
        guard let match = lastMatch else { return nil }

        // Use capture group 1 if available (strips the $), else full match
        let valueRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
        guard let swiftRange = Range(valueRange, in: text) else { return nil }
        let priceString = String(text[swiftRange]).replacingOccurrences(of: ",", with: "")
        return Double(priceString)
    }

    /// Remove the trailing price from a line to leave just the description
    private func stripPriceFromEnd(from text: String, using regex: NSRegularExpression) -> String {
        let range = NSRange(text.startIndex..., in: text)
        var lastMatchRange: NSRange?
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            lastMatchRange = match?.range
        }
        guard let matchRange = lastMatchRange,
              let swiftRange = Range(matchRange, in: text) else { return text }
        return String(text[text.startIndex..<swiftRange.lowerBound])
    }
}

// MARK: - UIImage Orientation Normalization

private extension UIImage {
    /// Redraw image so its orientation is .up — critical for correct Vision OCR ordering
    func normalized() -> UIImage {
        guard imageOrientation != .up else { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext() ?? self
        UIGraphicsEndImageContext()
        return normalized
    }
}
