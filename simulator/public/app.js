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
