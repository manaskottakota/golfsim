import SwiftUI

struct AddressCalibrationView: View {
    @Environment(AppState.self) private var appState

    private var service: AddressCalibrationService { appState.swingAnalysis.addressCalibration }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Address Reference").font(.headline)
                Spacer()
                stateLabel
            }
            Text("Hold the phone upright and still, with the screen facing the direction of the swing. The measured quaternion defines heading; gravity only verifies upright tilt.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if case .collecting(let progress) = service.state {
                ProgressView(value: progress)
                Text("Hold phone still at address")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            if case .failed(let message) = service.state {
                Text(message).font(.footnote).foregroundStyle(.red)
            }

            Button {
                appState.swingAnalysis.setAddress()
            } label: {
                Label("Set Address", systemImage: "scope")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!appState.motion.isStreaming || isCollecting)
        }
        .padding()
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.10)) }
        .foregroundStyle(.white)
    }

    private var isCollecting: Bool {
        if case .collecting = service.state { return true }
        return false
    }

    @ViewBuilder
    private var stateLabel: some View {
        switch service.state {
        case .notCalibrated:
            Label("Not set", systemImage: "circle").foregroundStyle(.secondary)
        case .collecting:
            Label("Measuring", systemImage: "waveform").foregroundStyle(.orange)
        case .calibrated:
            Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Label("Try again", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }
}
