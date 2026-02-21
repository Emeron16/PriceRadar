//
//  Environment.swift
//  PriceRadar
//
//  Utility for loading environment variables from .env file
//

import Foundation
import FirebaseCore

enum EnvConfig {

    /// Load environment variables from .env file
    static func load() {
        // Try multiple locations for .env file
        var envPath: String?

        // 1. Try bundle (for production builds)
        if let bundlePath = Bundle.main.path(forResource: ".env", ofType: nil) {
            envPath = bundlePath
            print("📍 Found .env in app bundle")
        }

        // 2. Try project root (for development/simulator)
        if envPath == nil {
            // Navigate up from app bundle to find project root
            let fileManager = FileManager.default
            if let bundlePath = Bundle.main.bundlePath as NSString? {
                var currentPath = bundlePath as String

                // Go up directories to find .env
                for _ in 0..<10 {
                    currentPath = (currentPath as NSString).deletingLastPathComponent
                    let potentialEnvPath = (currentPath as NSString).appendingPathComponent(".env")

                    if fileManager.fileExists(atPath: potentialEnvPath) {
                        envPath = potentialEnvPath
                        print("📍 Found .env at project root: \(potentialEnvPath)")
                        break
                    }
                }
            }
        }

        guard let finalPath = envPath else {
            print("⚠️ .env file not found in bundle or project root")
            print("   Searched from: \(Bundle.main.bundlePath)")
            return
        }

        do {
            let envContent = try String(contentsOfFile: finalPath, encoding: .utf8)
            let lines = envContent.components(separatedBy: .newlines)

            var loadedCount = 0

            for line in lines {
                // Skip comments and empty lines
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") {
                    continue
                }

                // Parse KEY=VALUE (handle spaces around =)
                let parts = trimmed.components(separatedBy: "=")
                guard parts.count >= 2 else { continue }

                let key = parts[0].trimmingCharacters(in: .whitespaces)
                // Join remaining parts in case value contains '='
                let value = parts[1...].joined(separator: "=")
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"")) // Remove quotes

                setenv(key, value, 1)
                loadedCount += 1
                print("   ✓ Loaded: \(key) = \(value.prefix(10))***") // Show first 10 chars only
            }

            print("✅ Loaded \(loadedCount) environment variables from .env")
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

    // MARK: - Firebase Options

    /// Build FirebaseOptions from environment variables instead of GoogleService-Info.plist
    static var firebaseOptions: FirebaseOptions? {
        guard
            let apiKey = get("FIREBASE_API_KEY"),
            let gcmSenderID = get("FIREBASE_GCM_SENDER_ID"),
            let googleAppID = get("FIREBASE_GOOGLE_APP_ID")
        else {
            print("❌ Missing required Firebase environment variables")
            return nil
        }

        let options = FirebaseOptions(googleAppID: googleAppID, gcmSenderID: gcmSenderID)
        options.apiKey = apiKey
        options.projectID = get("FIREBASE_PROJECT_ID")
        options.storageBucket = get("FIREBASE_STORAGE_BUCKET")
        options.bundleID = get("FIREBASE_BUNDLE_ID") ?? Bundle.main.bundleIdentifier ?? ""
        return options
    }
}
