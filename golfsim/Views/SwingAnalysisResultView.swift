import SwiftUI

struct SwingAnalysisResultView: View {
    let result: SwingAnalysisResult

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Swing Analysis").font(.headline)
                Spacer()
                Text("Quality \(Int(result.confidence * 100))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(result.confidence >= 0.65 ? .green : .orange)
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                metric("Swing", seconds(result.metrics.totalSwingDuration))
                metric("Backswing", seconds(result.metrics.backswingDuration))
                metric("Downswing", seconds(result.metrics.downswingDuration))
                metric("Tempo", String(format: "%.2f : 1", result.metrics.tempoRatio))
                metric("Peak rotation", String(format: "%.2f rad/s", result.metrics.peakRotationalVelocity))
                metric("Peak acceleration", String(format: "%.2f g", result.metrics.peakUserAcceleration))
                metric("Max orientation change", String(format: "%.1f°", result.metrics.maximumRelativeOrientationChangeDegrees))
            }
            Divider()
            Text("Validation Timeline").font(.subheadline.weight(.semibold))
            SwingSignalTimeline(result: result)
                .frame(height: 150)
            phaseLegend
            ForEach(result.diagnostics, id: \.self) { diagnostic in
                Label(diagnostic, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
        }.font(.subheadline)
    }

    private var phaseLegend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(result.phases, id: \.phase) { boundary in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(boundary.phase.rawValue.replacingOccurrences(of: "_", with: " "))
                        Text(String(format: "%+.2fs", boundary.offsetSeconds)).monospacedDigit()
                    }
                    .font(.caption2)
                    .padding(7)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }

    private func seconds(_ value: TimeInterval) -> String { String(format: "%.2f s", value) }
}

private struct SwingSignalTimeline: View {
    let result: SwingAnalysisResult

    var body: some View {
        Canvas { context, size in
            guard
                let minimum = result.signalTimeline.map(\.offsetSeconds).min(),
                let maximum = result.signalTimeline.map(\.offsetSeconds).max(),
                maximum > minimum
            else { return }
            let maxRotation = max(0.1, result.signalTimeline.map(\.smoothedRotationRate).max() ?? 0.1)
            let maxAcceleration = max(0.1, result.signalTimeline.map(\.smoothedAcceleration).max() ?? 0.1)
            func x(_ offset: Double) -> Double { (offset - minimum) / (maximum - minimum) * size.width }
            var rawRotationPath = Path()
            var rawAccelerationPath = Path()
            var rotationPath = Path()
            var accelerationPath = Path()
            for (index, point) in result.signalTimeline.enumerated() {
                let rawPosition = CGPoint(x: x(point.offsetSeconds), y: size.height * (1 - min(1, point.rawRotationRate / maxRotation)))
                let rawAccelerationPosition = CGPoint(x: x(point.offsetSeconds), y: size.height * (1 - min(1, point.rawAcceleration / maxAcceleration)))
                let position = CGPoint(x: x(point.offsetSeconds), y: size.height * (1 - point.smoothedRotationRate / maxRotation))
                let accelerationPosition = CGPoint(x: x(point.offsetSeconds), y: size.height * (1 - point.smoothedAcceleration / maxAcceleration))
                if index == 0 {
                    rawRotationPath.move(to: rawPosition)
                    rawAccelerationPath.move(to: rawAccelerationPosition)
                    rotationPath.move(to: position)
                    accelerationPath.move(to: accelerationPosition)
                } else {
                    rawRotationPath.addLine(to: rawPosition)
                    rawAccelerationPath.addLine(to: rawAccelerationPosition)
                    rotationPath.addLine(to: position)
                    accelerationPath.addLine(to: accelerationPosition)
                }
            }
            context.stroke(rawRotationPath, with: .color(.blue.opacity(0.2)), lineWidth: 0.7)
            context.stroke(rawAccelerationPath, with: .color(.orange.opacity(0.2)), lineWidth: 0.7)
            context.stroke(rotationPath, with: .color(.blue), lineWidth: 2)
            context.stroke(accelerationPath, with: .color(.orange), lineWidth: 1.5)
            for boundary in result.phases {
                let boundaryX = x(boundary.offsetSeconds)
                var path = Path()
                path.move(to: CGPoint(x: boundaryX, y: 0))
                path.addLine(to: CGPoint(x: boundaryX, y: size.height))
                context.stroke(path, with: .color(.green.opacity(0.55)), lineWidth: 1)
            }
        }
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topLeading) {
            HStack(spacing: 8) {
                Text("rotation").foregroundStyle(.blue)
                Text("acceleration").foregroundStyle(.orange)
            }
            .font(.caption2)
        }
        .padding(.top, 16)
    }
}
