//
//  SwingCaptureProgressView.swift
//  golfsim
//

import SwiftUI

struct SwingCaptureProgressView: View {
    let phase: SwingCapturePhase
    let latestMotionTimestamp: TimeInterval?
    let postTriggerDuration: TimeInterval

    var body: some View {
        if case .capturing(let deadline) = phase, let latestMotionTimestamp {
            let elapsed = max(0, latestMotionTimestamp - (deadline - postTriggerDuration))
            let progress = min(1, elapsed / postTriggerDuration)
            let remaining = max(0, deadline - latestMotionTimestamp)

            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress)
                Text(String(format: "%.1f s remaining in post-trigger window", remaining))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

#Preview {
    SwingCaptureProgressView(
        phase: .capturing(postTriggerDeadline: 10),
        latestMotionTimestamp: 7,
        postTriggerDuration: 6
    )
    .padding()
}
