//
//  MainTabView.swift
//  golfsim
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            SwingCaptureView()
                .tabItem {
                    Label("Swing", systemImage: "figure.golf")
                }

            MotionDebugView()
                .tabItem {
                    Label("Sensor Lab", systemImage: "waveform.path.ecg")
                }
        }
        .tint(Color(red: 0.47, green: 0.88, blue: 0.58))
        .toolbarBackground(Color(red: 0.025, green: 0.045, blue: 0.035), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

#Preview {
    MainTabView()
        .environment(AppState())
}
