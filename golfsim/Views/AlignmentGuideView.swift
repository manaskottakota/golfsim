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
            Text("Hold the phone on the clubface so the screen faces the ball. Keep the long edge parallel to the sole.")
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
                    Text("Screen → ball")
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
        let pitchHint = pitchDescription(gravityY: sample.gravityY)
        let rollHint = rollDescription(gravityX: sample.gravityX)

        VStack(alignment: .leading, spacing: 6) {
            Label(pitchHint.message, systemImage: pitchHint.icon)
            Label(rollHint.message, systemImage: rollHint.icon)
        }
        .font(.footnote)
        .foregroundStyle(pitchHint.isGood && rollHint.isGood ? .green : .orange)
    }

    private func pitchDescription(gravityY: Double) -> (message: String, icon: String, isGood: Bool) {
        if abs(gravityY) < 0.25 {
            return ("Pitch: phone is fairly upright for face-on mounting.", "checkmark.circle", true)
        }
        if gravityY > 0.25 {
            return ("Pitch: tilt top edge toward the ground.", "arrow.down.forward", false)
        }
        return ("Pitch: tilt top edge toward the sky.", "arrow.up.forward", false)
    }

    private func rollDescription(gravityX: Double) -> (message: String, icon: String, isGood: Bool) {
        if abs(gravityX) < 0.25 {
            return ("Roll: level left-to-right.", "checkmark.circle", true)
        }
        if gravityX > 0.25 {
            return ("Roll: lower the right edge slightly.", "arrow.right", false)
        }
        return ("Roll: lower the left edge slightly.", "arrow.left", false)
    }
}

#Preview {
    AlignmentGuideView(latestSample: nil)
        .padding()
}
