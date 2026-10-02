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
                VStack(alignment: .leading, spacing: 16) {
                    mobileBrand
                    SimulatorConnectionView()
                    ClubPickerView(clubSelection: clubSelection)
                    AddressCalibrationView()
                    captureControls
                    if let result = appState.swingAnalysis.latestResult {
                        SwingAnalysisResultView(result: result)
                    }
                    if let swing = motion.latestSwing {
                        swingSummary(swing)
                    }
                }
                .padding()
            }
            .background(Color(red: 0.025, green: 0.045, blue: 0.035).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .tint(Color(red: 0.47, green: 0.88, blue: 0.58))
            .onAppear {
                appState.setSwingSessionActive(true)
                UIApplication.shared.isIdleTimerDisabled = true
                configureVolumeTrigger()
            }
            .onDisappear {
                appState.setSwingSessionActive(false)
                UIApplication.shared.isIdleTimerDisabled = appState.motion.isStreaming
                volumeTrigger.disable()
            }
            .onChange(of: clubSelection.selectedClub) {
                appState.simulatorSession.sendSelectedClub()
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

    private var mobileBrand: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("thegolfgame")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .tracking(-1.4)
                    .foregroundStyle(.white)
                Text("IPHONE CONTROLLER")
                    .font(.caption2.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(Color(red: 0.47, green: 0.88, blue: 0.58))
            }
            Spacer()
            Circle()
                .fill(motion.isStreaming ? Color.green : Color.orange)
                .frame(width: 9, height: 9)
                .shadow(color: motion.isStreaming ? .green.opacity(0.7) : .orange.opacity(0.7), radius: 8)
        }
        .padding(.top, 6)
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

            Text(captureInstruction)
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
            .disabled(!motion.isStreaming || isCapturingSwing || appState.swingAnalysis.addressCalibration.calibration == nil)

            if volumeTrigger.isEnabled {
                Label("Volume Up enabled", systemImage: "speaker.plus.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.10)) }
        .foregroundStyle(.white)
    }

    private func swingSummary(_ swing: SwingRecording) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last swing")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                summaryRow("Club", value: swing.club.displayName)
                summaryRow("Samples", value: "\(swing.samples.count)")
                summaryRow("Pre-trigger", value: "\(swing.prePostTriggerSampleCounts.preTrigger)")
                summaryRow("Post-trigger", value: "\(swing.prePostTriggerSampleCounts.postTrigger)")
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

    private func configureVolumeTrigger() {
        volumeTrigger.onVolumeUp = { [appState, clubSelection] in
            appState.swingAnalysis.startSwingCapture(club: clubSelection.selectedClub)
        }
        volumeTrigger.enable()
    }

    private func triggerSwing() {
        appState.swingAnalysis.startSwingCapture(club: clubSelection.selectedClub)
    }

    private var captureInstruction: String {
        if appState.swingAnalysis.addressCalibration.calibration == nil {
            return "Set Address before starting a swing. Capture keeps the existing pre-roll plus 6 seconds after trigger."
        }
        switch appState.swingAnalysis.workflowState {
        case .analyzing: return "Swing captured — analyzing raw motion locally…"
        case .invalid(let message): return "Invalid swing: \(message)"
        default: return "Tap Start Swing or press Volume Up, then make one complete swing."
        }
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
