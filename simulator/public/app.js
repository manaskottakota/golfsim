const elements = {
  status: document.querySelector("#status"),
  statusLight: document.querySelector("#status-light"),
  connectionDetail: document.querySelector("#connection-detail"),
  disconnect: document.querySelector("#disconnect"),
  pairingPanel: document.querySelector("#pairing-panel"),
  qr: document.querySelector("#qr"),
  pairingURL: document.querySelector("#pairing-url"),
  phone: document.querySelector("#phone"),
  clubItems: [...document.querySelectorAll("#club-list li")],
  rate: document.querySelector("#rate"),
  latency: document.querySelector("#latency"),
  session: document.querySelector("#session"),
  quaternion: ["w", "x", "y", "z"].map((axis) => document.querySelector(`#quaternion-${axis}`)),
  rotation: ["x", "y", "z"].map((axis) => document.querySelector(`#rotation-${axis}`)),
  swingRing: document.querySelector("#swing-ring"),
  swingStatus: document.querySelector("#swing-status"),
  swingMessage: document.querySelector("#swing-message"),
  swingResult: document.querySelector("#swing-result"),
  result: {
    club: document.querySelector("#result-club"),
    duration: document.querySelector("#result-duration"),
    backswing: document.querySelector("#result-backswing"),
    downswing: document.querySelector("#result-downswing"),
    tempo: document.querySelector("#result-tempo"),
    rotation: document.querySelector("#result-rotation"),
    acceleration: document.querySelector("#result-acceleration"),
  },
  phaseTimeline: document.querySelector("#phase-timeline"),
};

let socket;
let updateTimes = [];
let reconnectTimer;
let controllerConnected = false;

function setConnectionState(connected, hasConnected = false) {
  controllerConnected = connected;
  const label = connected ? "Connected" : (hasConnected ? "iPhone Disconnected" : "Waiting for iPhone");
  elements.status.textContent = label;
  elements.connectionDetail.textContent = connected ? "Connected" : (hasConnected ? "Disconnected" : "Waiting");
  elements.statusLight.className = `status-light ${connected ? "connected" : (hasConnected ? "disconnected" : "waiting")}`;
  elements.disconnect.hidden = !connected;
  elements.pairingPanel.classList.toggle("hidden", connected);
  document.body.classList.toggle("controller-connected", connected);
  if (!connected) {
    updateTimes = [];
    elements.rate.textContent = "—";
    elements.latency.textContent = "—";
  }
}

function format(value) {
  return Number.isFinite(Number(value)) ? Number(value).toFixed(3) : "—";
}

function quaternionMatrix({ w, x, y, z }) {
  const length = Math.hypot(w, x, y, z) || 1;
  w /= length; x /= length; y /= length; z /= length;
  return `matrix3d(${[
    1 - 2*y*y - 2*z*z, 2*x*y + 2*w*z, 2*x*z - 2*w*y, 0,
    2*x*y - 2*w*z, 1 - 2*x*x - 2*z*z, 2*y*z + 2*w*x, 0,
    2*x*z + 2*w*y, 2*y*z - 2*w*x, 1 - 2*x*x - 2*y*y, 0,
    0, 0, 0, 1,
  ].join(",")})`;
}

function handlePose(pose) {
  const now = Date.now();
  updateTimes.push(now);
  updateTimes = updateTimes.filter((time) => time >= now - 1000);
  elements.rate.textContent = `${updateTimes.length} Hz`;
  elements.latency.textContent = `${Math.max(0, now - pose.sentAtUnixMilliseconds)} ms`;
  [pose.quaternion.w, pose.quaternion.x, pose.quaternion.y, pose.quaternion.z]
    .forEach((value, index) => { elements.quaternion[index].textContent = format(value); });
  [pose.rotationRate.x, pose.rotationRate.y, pose.rotationRate.z]
    .forEach((value, index) => { elements.rotation[index].textContent = format(value); });
  elements.phone.style.transform = quaternionMatrix(pose.quaternion);
}

function selectClub(club) {
  elements.clubItems.forEach((item) => item.classList.toggle("selected", item.dataset.club === club));
}

const swingStates = {
  waiting_for_address: ["Waiting for address", "Tap Set Address in the iPhone app."],
  address_calibrated: ["Address calibrated", "Ready to record a swing."],
  waiting_for_swing: ["Waiting for swing…", "Make one complete swing with the phone."],
  analyzing: ["Swing detected / Analyzing", "Processing the raw 100 Hz recording on iPhone."],
  swing_complete: ["Swing complete", "Analysis received from iPhone."],
  invalid: ["Invalid swing / Try again", "No valid swing result was produced."],
};

function handleSwingStatus(payload) {
  const [title, defaultMessage] = swingStates[payload.state] || ["Swing capture", "Waiting for iPhone."];
  elements.swingStatus.textContent = title;
  elements.swingMessage.textContent = payload.message || defaultMessage;
  elements.swingRing.classList.toggle("analyzing", payload.state === "analyzing");
  if (payload.state !== "swing_complete") elements.swingResult.hidden = true;
}

function handleSwingResult(result) {
  elements.swingStatus.textContent = "Swing complete";
  elements.swingMessage.textContent = `Analysis quality ${Math.round(result.confidence * 100)}%`;
  elements.swingResult.hidden = false;
  elements.result.club.textContent = result.club.replaceAll("_", " ");
  elements.result.duration.textContent = `${result.swingDuration.toFixed(2)} s`;
  elements.result.backswing.textContent = `${result.backswingDuration.toFixed(2)} s`;
  elements.result.downswing.textContent = `${result.downswingDuration.toFixed(2)} s`;
  elements.result.tempo.textContent = `${result.tempoRatio.toFixed(2)} : 1`;
  elements.result.rotation.textContent = `${result.peakRotationalVelocity.toFixed(2)} rad/s`;
  elements.result.acceleration.textContent = `${result.peakAcceleration.toFixed(2)} g`;
  elements.phaseTimeline.replaceChildren();
  const orderedPhases = ["address", "takeaway", "backswing", "transition", "downswing", "impact_region", "follow_through", "motion_end"];
  const maximum = Math.max(result.swingDuration, ...Object.values(result.phaseOffsets));
  for (const phase of orderedPhases) {
    if (result.phaseOffsets[phase] === undefined) continue;
    const marker = document.createElement("span");
    marker.className = `phase-marker phase-${phase}`;
    marker.style.left = `${Math.max(0, Math.min(100, result.phaseOffsets[phase] / maximum * 100))}%`;
    marker.title = `${phase.replaceAll("_", " ")} ${result.phaseOffsets[phase].toFixed(2)}s`;
    elements.phaseTimeline.append(marker);
  }
}

function connectDisplay(sessionID) {
  clearTimeout(reconnectTimer);
  const scheme = location.protocol === "https:" ? "wss" : "ws";
  socket = new WebSocket(`${scheme}://${location.host}/display?session=${encodeURIComponent(sessionID)}`);
  socket.addEventListener("message", (event) => {
    let message;
    try { message = JSON.parse(event.data); } catch { return; }
    if (message.protocolVersion !== 1) return;
    if (message.type === "displayState") {
      elements.session.textContent = message.payload.sessionID?.slice(0, 8) || sessionID.slice(0, 8);
      setConnectionState(message.payload.connected, message.payload.hasConnected);
    } else if (message.type === "livePose") {
      handlePose(message.payload);
    } else if (message.type === "clubSelection") {
      selectClub(message.payload.club);
    } else if (message.type === "swingStatus") {
      handleSwingStatus(message.payload);
    } else if (message.type === "swingResult") {
      handleSwingResult(message.payload);
    }
  });
  socket.addEventListener("close", () => {
    if (controllerConnected) setConnectionState(false, true);
    reconnectTimer = setTimeout(() => connectDisplay(sessionID), 1500);
  });
  socket.addEventListener("error", () => socket.close());
}

elements.disconnect.addEventListener("click", () => {
  if (socket?.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify({ protocolVersion: 1, type: "disconnectController", payload: {} }));
  }
});

fetch("/api/session")
  .then((response) => {
    if (!response.ok) throw new Error(`Session request failed (${response.status})`);
    return response.json();
  })
  .then((session) => {
    elements.qr.src = session.qrDataURL;
    elements.pairingURL.textContent = session.pairingURL;
    elements.session.textContent = session.sessionID.slice(0, 8);
    connectDisplay(session.sessionID);
  })
  .catch((error) => {
    elements.status.textContent = error.message;
    elements.statusLight.className = "status-light disconnected";
  });
