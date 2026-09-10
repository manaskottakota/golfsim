//
//  golfsimApp.swift
//  golfsim
//
//  Created by Manas Kottakota on 9/2/26.
//

import SwiftUI

@main
struct golfsimApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
    }
}
