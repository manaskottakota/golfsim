# golfsim development

golfsim currently consists of a native iPhone controller and a minimal laptop development display. The phone keeps capturing Core Motion at approximately 100 Hz. While paired, it sends only the newest pose at approximately 30 Hz over a local WebSocket; raw samples remain on the phone for recording and future analysis.

## Requirements

- A Mac or laptop with Node.js 20 or newer.
- An iPhone and laptop connected to the same local network.
- Xcode capable of building the included iOS project.
- Firewall permission for Node.js to accept incoming connections on the selected port.

## 1. Start the laptop simulator

From the repository root:

```bash
cd simulator
npm install
npm start
```

Open <http://localhost:8080> on the laptop. The terminal prints both the page URL and the local address encoded into the QR code. A new server process creates a new session and one-time development token.

The server automatically chooses the first non-loopback IPv4 address. If that is not the address reachable by the iPhone, restart it with the correct Wi-Fi address:

```bash
GOLFSIM_HOST=192.168.1.25 npm start
```

Find the laptop's address in macOS **System Settings → Wi-Fi → Details → TCP/IP**, or run:

```bash
ipconfig getifaddr en0
```

Use a different port if 8080 is occupied:

```bash
PORT=8081 GOLFSIM_HOST=192.168.1.25 npm start
```

Keep this terminal process running. Reloading the web page keeps the same session; restarting Node creates a new QR code.

## 2. Run and pair the iPhone app

1. Open `golfsim.xcodeproj` in Xcode.
2. Select your development team if Xcode requests signing configuration.
3. Select a physical iPhone as the run destination and run the `golfsim` scheme.
4. Open the **Swing** tab.
5. Tap **Pair with Simulator**.
6. Approve camera access so the app can scan the QR code.
7. Scan the QR code displayed at `http://localhost:8080` on the laptop.
8. Approve the iOS **Local Network** prompt if it appears.

The iPhone card and laptop header should both show **Connected**. Select another club on the phone and verify that the laptop's Club value changes. Rotate the phone and verify that the rectangular controller and quaternion/rotation-rate readouts move immediately. The page also reports the received update rate and an approximate send-to-browser latency.

Use **Disconnect** on the phone to close the controller connection. **Reconnect** retries the last scanned session while the same Node server is still running. Scan the new QR after restarting the server because its session and token change.

## 3. Address-position convention

The phone represents the clubface. Hold it upright, with the screen approximately perpendicular to the ground and facing the intended swing direction. The current guide checks only whether gravity lies mostly in the plane of the screen; gravity cannot determine which horizontal direction the screen faces. This guide is not address calibration, and the transmitted quaternion is not yet transformed into an address-relative clubface orientation.

## Network permissions and development security

The app includes camera and local-network usage descriptions. This development build permits an insecure `ws://` connection because the server is running directly on the LAN. The QR token prevents an accidental unauthenticated controller from joining, but traffic is not encrypted and the laptop display endpoint is intended only for a trusted development network. Production pairing will require TLS, expiration, stronger session lifecycle rules, and likely a signaling/relay service.

If pairing fails:

- confirm both devices are on the same non-isolated Wi-Fi network;
- confirm `GOLFSIM_HOST` is the laptop address reachable from the phone;
- allow incoming Node.js connections in the laptop firewall;
- disable VPNs that prevent LAN routing;
- restart Node and scan the newly generated code;
- avoid guest Wi-Fi networks that isolate clients.

## Checks

Run protocol/parser tests from the repository root:

```bash
swift test
```

Run JavaScript syntax checks after installing laptop dependencies:

```bash
cd simulator
npm run check
```

## Known limitations

- One iPhone controller is supported per server process.
- Pairing is local-development-only and uses unencrypted WebSocket traffic.
- Reconnection is user initiated; completed swings are not queued for delivery yet.
- Live pose is absolute Core Motion attitude, not calibrated address-relative orientation.
- Browser and phone clocks provide only approximate latency.
- The phone controller graphic is a diagnostics view, not a golf course.
- No swing analysis, shot model, ball physics, or 3D golf environment is implemented.
- Raw 100 Hz motion remains local and is not continuously sent to the laptop.
