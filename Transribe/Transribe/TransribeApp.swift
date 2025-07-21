//
//  TransribeApp.swift
//  Transribe
//
//  Created by Parag Dulam on 18/07/25.
//

import SwiftUI

@main
struct TransribeApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
