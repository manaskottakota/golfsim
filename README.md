# thegolfgame

**thegolfgame** is a phone-powered golf swing game. Open the driving range on a laptop, scan the pairing QR code with an iPhone, and use the phone as the club controller. No iPhone app installation is required for the web experience.

**Live site:** https://golfsim-rust.vercel.app/

## How it works

The project is split into two deployed pieces:

- **Vercel** serves the public driving-range UI and the mobile Safari controller.
- **Railway** runs the persistent Node.js/WebSocket backend used for realtime pairing and motion data.
- The laptop creates a session and displays a QR code.
- Scanning the QR opens the Vercel mobile controller with that session's credentials.
- The iPhone and laptop then connect to the same Railway WebSocket backend.

This keeps the UI deployable as a normal website while Railway handles the persistent connection that a serverless Vercel deployment cannot reliably maintain.

## Playing

1. Open https://golfsim-rust.vercel.app/ on a laptop.
2. Scan the displayed QR code using the normal iPhone Camera app.
3. Safari opens the mobile **thegolfgame** controller. No native app is required.
4. Select a club on the phone.
5. Allow motion access when prompted.
6. Hold the phone upright, approximately perpendicular to the ground, with the screen facing the swing direction.
7. Tap **Set Address** while holding the phone still.
8. Tap **Start Swing** and make a complete swing.
9. The laptop receives the result and displays the shot on the driving range.

## Game model

The phone's motion sensors drive a game-oriented swing model rather than claiming to measure true club or ball physics. Swing motion influences:

- **Power** from rotational speed and acceleration
- **Tempo** from the timing of the swing
- **Quality** from tempo, completeness, and analysis confidence
- **Carry and total distance** using the selected club plus the swing traits
- **Shot shape and dispersion** as game outcomes

The selected club provides the baseline distance and launch characteristics, while the captured swing changes the resulting shot.

## Web architecture

```text
Laptop browser (Vercel) ──┐
                          ├── WebSocket ── Railway realtime server
iPhone Safari (Vercel) ───┘
```

The desktop frontend requests a pairing session from Railway. Railway generates the session ID and token, but the QR points the phone to the Vercel-hosted `/controller.html` page. The controller then connects back to Railway for realtime communication.

Current realtime backend:

```text
https://game-server-v2-production-934e.up.railway.app
```

## Local development

The simulator can still run locally:

```bash
cd simulator
npm install
npm start
```

Then open `http://localhost:8080`. The local Node server serves the simulator and handles the WebSocket connection.

Useful checks:

```bash
swift test

cd simulator
npm run check
npm test
```

## Native iOS code

The repository also contains the original native Swift/SwiftUI controller and swing-analysis pipeline. It uses Core Motion to record high-frequency motion data and includes the existing swing-phase and metric analysis work.

That native analysis is intentionally kept separate from the current web game's simplified game layer and remains available for future development.

## Current limitations

- The deployed backend currently uses one in-memory game session per Railway server process.
- The motion-derived results are game mechanics, not measurements of real clubhead speed or ball-flight physics.
- Safari requires motion permission before sensor data is available.
- A server restart creates a new in-memory session.
- The current architecture is intended for the project/demo experience rather than many simultaneous public games.
