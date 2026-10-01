//
//  AlignmentGuideView.swift
//  golfsim
//

import SwiftUI

struct AlignmentGuideView: View {
    let latestSample: MotionSample?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clubface alignment")
                .font(.headline)
            Text("Hold the phone upright, approximately perpendicular to the ground, with the screen facing the direction of the swing.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .aspectRatio(9.0 / 19.5, contentMode: .fit)
                    .frame(maxWidth: 160)

                VStack(spacing: 6) {
                    Image(systemName: "iphone.gen3")
                        .font(.title2)
                    Text("Screen → swing direction")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            if let latestSample {
                alignmentFeedback(for: latestSample)
            } else {
                Label("Start streaming to see tilt feedback.", systemImage: "gyroscope")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func alignmentFeedback(for sample: MotionSample) -> some View {
        let uprightHint = uprightDescription(gravityZ: sample.gravityZ)

        VStack(alignment: .leading, spacing: 6) {
            Label(uprightHint.message, systemImage: uprightHint.icon)
            Text("Gravity can verify that the screen is upright, but not which horizontal direction it faces. Point the screen in the swing direction yourself.")
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .foregroundStyle(uprightHint.isGood ? .green : .orange)
    }

    private func uprightDescription(gravityZ: Double) -> (message: String, icon: String, isGood: Bool) {
        // Device Z is perpendicular to the screen. Near-zero Z gravity means the screen plane is vertical,
        // regardless of whether the user holds the phone in portrait or landscape.
        if abs(gravityZ) < 0.25 {
            return ("Phone is upright for the address position.", "checkmark.circle", true)
        }
        return ("Tilt the phone until its screen is perpendicular to the ground.", "iphone.gen3.radiowaves.left.and.right", false)
    }
}

#Preview {
    AlignmentGuideView(latestSample: nil)
        .padding()
}
