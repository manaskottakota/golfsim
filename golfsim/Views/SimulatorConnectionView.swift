import SwiftUI

struct SimulatorConnectionView: View {
    @Environment(AppState.self) private var appState
    @State private var isShowingScanner = false
    @State private var pairingError: String?

    private var session: SimulatorSessionCoordinator { appState.simulatorSession }
    private var connection: SimulatorConnectionService { session.connection }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Simulator")
                    .font(.headline)
                Spacer()
                statusLabel
            }

            Text("Pair with the laptop simulator, then move the phone to drive its live controller view.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if connection.state.isConnected {
                Button("Disconnect", role: .destructive) {
                    session.disconnect()
                }
                .buttonStyle(.bordered)
            } else {
                HStack {
                    Button {
                        pairingError = nil
                        isShowingScanner = true
                    } label: {
                        Label("Pair with Simulator", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    if session.canReconnect {
                        Button("Reconnect") {
                            pairingError = nil
                            session.reconnect()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .disabled(connection.state == .connecting)
            }

            if let error = pairingError ?? connection.lastErrorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .sheet(isPresented: $isShowingScanner) {
            NavigationStack {
                QRCodeScannerView(
                    onScanned: handleScannedValue,
                    onError: handleScannerError
                )
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Scan simulator QR")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isShowingScanner = false }
                    }
                }
            }
        }
    }

    private var statusLabel: some View {
        Label(connection.state.label, systemImage: connection.state.isConnected ? "checkmark.circle.fill" : "circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(connection.state.isConnected ? .green : .secondary)
    }

    private func handleScannedValue(_ value: String) {
        do {
            let payload = try PairingPayload(scannedValue: value)
            isShowingScanner = false
            session.connect(using: payload)
        } catch {
            pairingError = error.localizedDescription
            isShowingScanner = false
        }
    }

    private func handleScannerError(_ message: String) {
        pairingError = message
        isShowingScanner = false
    }
}
