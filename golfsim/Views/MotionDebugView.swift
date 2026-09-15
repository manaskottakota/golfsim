//
//  MotionDebugView.swift
//  golfsim
//

import SwiftUI

/// Milestone 1: live Core Motion readout and capture validation on device.
struct MotionDebugView: View {
    @Environment(AppState.self) private var appState
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var alertMessage: String?

    private var motion: MotionCaptureService { appState.motion }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard
                    healthCard
                    if let sample = motion.latestSample {
                        sampleCard(sample)
                    } else {
                        ContentUnavailableView(
                            "No motion data yet",
                            systemImage: "waveform.path.ecg",
                            description: Text("Start streaming to validate sensor output on your iPhone.")
                        )
                        .frame(minHeight: 180)
                    }
                    recordingCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Sensor Lab")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showShareSheet) {
                if let exportURL {
                    ShareSheet(items: [exportURL])
                }
            }
            .alert("Motion capture", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if motion.isStreaming, !appState.motionStreaming.isSensorLabStreamingRequested {
                Text("Live")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Button(appState.motionStreaming.isSensorLabStreamingRequested ? "Stop" : "Stream") {
                    toggleStreaming()
                }
                .fontWeight(.semibold)
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Milestone 1", systemImage: "flag.checkered")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Capture and validate high-frequency device motion before swing phase detection.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                statusChip(
                    title: motion.isStreaming ? "Streaming" : "Idle",
                    color: motion.isStreaming ? .green : .secondary
                )
                if motion.isRecording {
                    statusChip(title: "Recording", color: .red)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stream health")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                metricRow("Samples", value: "\(motion.health.sampleCount)")
                metricRow("Duration", value: formatSeconds(motion.health.streamDuration))
                metricRow("Est. rate", value: formatHz(motion.health.estimatedSampleRateHz))
                metricRow("Target interval", value: String(format: "%.1f ms", motion.preferredUpdateInterval * 1000))
                metricRow("Avg Δt", value: formatMilliseconds(motion.health.averageIntervalSeconds))
                metricRow("Δt range", value: "\(formatMilliseconds(motion.health.minIntervalSeconds)) – \(formatMilliseconds(motion.health.maxIntervalSeconds))")
                metricRow("Possible gaps", value: "\(motion.health.suspectedDropCount)")
            }
            Text(motion.health.qualitySummary)
                .font(.footnote)
                .foregroundStyle(motion.health.suspectedDropCount > 0 ? .orange : .secondary)
            if let error = motion.lastErrorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sampleCard(_ sample: MotionSample) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Latest sample")
                .font(.headline)
            Group {
                vectorSection(
                    title: "Quaternion (w, x, y, z)",
                    values: [sample.quaternionW, sample.quaternionX, sample.quaternionY, sample.quaternionZ]
                )
                vectorSection(
                    title: "Rotation rate (rad/s)",
                    values: [sample.rotationRateX, sample.rotationRateY, sample.rotationRateZ],
                    magnitude: sample.rotationRateMagnitude
                )
                vectorSection(
                    title: "User acceleration (g)",
                    values: [sample.userAccelerationX, sample.userAccelerationY, sample.userAccelerationZ],
                    magnitude: sample.userAccelerationMagnitude
                )
                vectorSection(
                    title: "Gravity (g)",
                    values: [sample.gravityX, sample.gravityY, sample.gravityZ],
                    magnitude: sample.gravityMagnitude
                )
            }
            Divider()
            HStack {
                Text("Motion t")
                Spacer()
                Text(String(format: "%.4f s", sample.motionTimestamp))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            validationHints(sample)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func validationHints(_ sample: MotionSample) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Quick checks")
                .font(.subheadline.weight(.semibold))
            Text("Rest the phone flat: gravity magnitude ≈ 1.0 g, user accel ≈ 0.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            let gravityOK = abs(sample.gravityMagnitude - 1.0) < 0.15
            Label(
                gravityOK ? "Gravity magnitude looks plausible" : "Gravity magnitude unexpected",
                systemImage: gravityOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .font(.footnote)
            .foregroundStyle(gravityOK ? .green : .orange)
        }
    }

    private var recordingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recording")
                .font(.headline)
            Text("Record a short clip, export JSON, and compare sample spacing offline.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button(motion.isRecording ? "Stop clip" : "Record clip") {
                    if motion.isRecording {
                        motion.stopRecording()
                    } else {
                        motion.startRecording()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!motion.isStreaming)

                Button("Export") {
                    exportRecording()
                }
                .buttonStyle(.bordered)
                .disabled(motion.recordedSamples.isEmpty)

                Button("Clear") {
                    motion.clearRecording()
                }
                .buttonStyle(.bordered)
                .disabled(motion.recordedSamples.isEmpty)
            }
            Text("\(motion.recordedSamples.count) samples in buffer")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func vectorSection(title: String, values: [Double], magnitude: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if let magnitude {
                    Spacer()
                    Text("|v| \(String(format: "%.3f", magnitude))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Text(values.map { String(format: "%+.4f", $0) }.joined(separator: "  "))
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }

    private func metricRow(_ title: String, value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.subheadline)
    }

    private func statusChip(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func toggleStreaming() {
        let shouldStream = !appState.motionStreaming.isSensorLabStreamingRequested
        appState.setSensorLabStreamingRequested(shouldStream)
        if let message = motion.lastErrorMessage, shouldStream {
            alertMessage = message
        }
        UIApplication.shared.isIdleTimerDisabled = motion.isStreaming
    }

    private func exportRecording() {
        do {
            exportURL = try motion.makeRecordingExportURL()
            showShareSheet = true
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func formatHz(_ hz: Double) -> String {
        guard hz > 0 else { return "—" }
        return String(format: "%.1f Hz", hz)
    }

    private func formatSeconds(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "—" }
        return String(format: "%.2f s", seconds)
    }

    private func formatMilliseconds(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "—" }
        return String(format: "%.1f ms", seconds * 1000)
    }
}

#Preview {
    MotionDebugView()
        .environment(AppState())
}
