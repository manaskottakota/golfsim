//
//  SwingCaptureView.swift
//  golfsim
//

import SwiftUI

struct SwingCaptureView: View {
    @Environment(AppState.self) private var appState
    @State private var volumeTrigger = VolumeSwingTrigger()
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var alertMessage: String?

    private var motion: MotionCaptureService { appState.motion }
    private var clubSelection: ClubSelectionStore { appState.clubSelection }

    var body: some View {
        @Bindable var clubSelection = appState.clubSelection

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ClubPickerView(clubSelection: clubSelection)
                    AlignmentGuideView(latestSample: motion.latestSample)
                    captureControls
                    if let swing = motion.latestSwing {
                        swingSummary(swing)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Swing")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                beginSession()
            }
            .onDisappear {
                volumeTrigger.disable()
            }
            .sheet(isPresented: $showShareSheet) {
                if let exportURL {
                    ShareSheet(items: [exportURL])
                }
            }
            .alert("Swing capture", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private var captureControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Capture")
                .font(.headline)

            HStack(spacing: 8) {
                statusChip(
                    title: motion.isStreaming ? "Live" : "Offline",
                    color: motion.isStreaming ? .green : .secondary
                )
                if isCapturingSwing {
                    statusChip(title: "Recording swing", color: .red)
                }
                statusChip(
                    title: "Buffer \(motion.ringBufferSampleCount)",
                    color: .blue
                )
            }

            Text("Tap Start Swing or press Volume Up to capture pre-roll plus 6 seconds after trigger.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            SwingCaptureProgressView(
                phase: motion.swingPhase,
                latestMotionTimestamp: motion.latestSample?.motionTimestamp,
                postTriggerDuration: MotionCaptureService.postTriggerCaptureSeconds
            )

            Button(action: triggerSwing) {
                Text(isCapturingSwing ? "Capturing…" : "Start Swing")
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!motion.isStreaming || isCapturingSwing)

            if volumeTrigger.isEnabled {
                Label("Volume Up enabled", systemImage: "speaker.plus.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func swingSummary(_ swing: SwingRecording) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last swing")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                summaryRow("Club", value: swing.club.displayName)
                summaryRow("Samples", value: "\(swing.samples.count)")
                summaryRow("Duration", value: String(format: "%.2f s", swing.durationSeconds))
            }
            HStack(spacing: 12) {
                Button("Export JSON") {
                    exportSwing(swing)
                }
                .buttonStyle(.borderedProminent)

                Button("Clear") {
                    motion.clearLatestSwing()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).frame(maxWidth: .infinity, alignment: .trailing)
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

    private var isCapturingSwing: Bool {
        if case .capturing = motion.swingPhase { return true }
        return false
    }

    private func beginSession() {
        if !motion.isStreaming {
            do {
                try motion.startStreaming()
                UIApplication.shared.isIdleTimerDisabled = true
            } catch {
                alertMessage = error.localizedDescription
            }
        }

        volumeTrigger.onVolumeUp = { [motion, clubSelection] in
            motion.triggerSwingCapture(club: clubSelection.selectedClub)
        }
        volumeTrigger.enable()
    }

    private func triggerSwing() {
        motion.triggerSwingCapture(club: clubSelection.selectedClub)
    }

    private func exportSwing(_ swing: SwingRecording) {
        do {
            exportURL = try motion.makeSwingExportURL(from: swing)
            showShareSheet = true
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

#Preview {
    SwingCaptureView()
        .environment(AppState())
}
