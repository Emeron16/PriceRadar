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
        // Initialize Firebase
        FirebaseApp.configure()
        print("🔥 Firebase configured")

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
