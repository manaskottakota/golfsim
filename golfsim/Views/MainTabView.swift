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
    }
}

#Preview {
    MainTabView()
        .environment(AppState())
}
