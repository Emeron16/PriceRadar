//
//  Environment.swift
//  PriceRadar
//
//  Utility for loading environment variables from .env file
//

import Foundation

enum EnvConfig {

    /// Load environment variables from .env file
    static func load() {
        guard let envPath = Bundle.main.path(forResource: ".env", ofType: nil) else {
            print("⚠️ .env file not found - using default values")
            return
        }

        do {
            let envContent = try String(contentsOfFile: envPath, encoding: .utf8)
            let lines = envContent.components(separatedBy: .newlines)

            for line in lines {
                // Skip comments and empty lines
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") {
                    continue
                }

                // Parse KEY=VALUE
                let parts = trimmed.components(separatedBy: "=")
                guard parts.count >= 2 else { continue }

                let key = parts[0].trimmingCharacters(in: .whitespaces)
                // Join remaining parts in case value contains '='
                let value = parts[1...].joined(separator: "=")
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"")) // Remove quotes

                setenv(key, value, 1)
            }

            print("✅ Environment variables loaded from .env")
        } catch {
            print("❌ Error loading .env file: \(error.localizedDescription)")
        }
    }

    /// Get environment variable value
    static func get(_ key: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[key] else {
            return nil
        }
        return value.isEmpty ? nil : value
    }

    /// Get environment variable with fallback
    static func get(_ key: String, default fallback: String) -> String {
        return get(key) ?? fallback
    }

    // MARK: - API Keys

    static var barcodeMonsterAPIKey: String? {
        return get("BARCODE_MONSTER_API_KEY")
    }
}
