//
//  PriceRadarApp.swift
//  PriceRadar
//
//  Created by Prince Marcelle on 2/14/26.
//

import SwiftUI
import CoreData
import FirebaseCore

@main
struct PriceRadarApp: App {
    let persistenceController = PersistenceController.shared

    init() {
        // Load environment variables from .env file
        EnvConfig.load()

        // Initialize Firebase from .env instead of GoogleService-Info.plist
        if let options = EnvConfig.firebaseOptions {
            FirebaseApp.configure(options: options)
            print("🔥 Firebase configured from .env")
        } else {
            // Fallback to plist (development without .env)
            FirebaseApp.configure()
            print("🔥 Firebase configured from plist (fallback)")
        }

        // Sign in anonymously on launch
        Task {
            try? await FirebaseService.shared.signInAnonymously()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
