the //
//  ContentView.swift
//  golfsim
//
//  Created by Manas Kottakota on 9/2/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        MainTabView()
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
