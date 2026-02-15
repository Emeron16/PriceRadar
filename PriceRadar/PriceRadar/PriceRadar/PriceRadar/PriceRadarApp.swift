//
//  PriceRadarApp.swift
//  PriceRadar
//
//  Created by Prince Marcelle on 2/14/26.
//

import SwiftUI
import CoreData

@main
struct PriceRadarApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
