const elements = {
  status: document.querySelector("#status"),
  qr: document.querySelector("#qr"),
  pairingURL: document.querySelector("#pairing-url"),
  phone: document.querySelector("#phone"),
  club: document.querySelector("#club"),
  rate: document.querySelector("#rate"),
  latency: document.querySelector("#latency"),
  sequence: document.querySelector("#sequence"),
  quaternion: document.querySelector("#quaternion"),
  rotation: document.querySelector("#rotation"),
};

let socket;
let updateTimes = [];

function setStatus(label, style) {
  elements.status.className = `status ${style}`;
  elements.status.lastChild.textContent = ` ${label}`;
}

function format(values) {
  return values.map((value) => Number(value).toFixed(4)).join("   ");
}

function quaternionMatrix({ w, x, y, z }) {
  const length = Math.hypot(w, x, y, z) || 1;
  w /= length; x /= length; y /= length; z /= length;
  const matrix = [
    1 - 2 * y * y - 2 * z * z, 2 * x * y + 2 * w * z, 2 * x * z - 2 * w * y, 0,
    2 * x * y - 2 * w * z, 1 - 2 * x * x - 2 * z * z, 2 * y * z + 2 * w * x, 0,
    2 * x * z + 2 * w * y, 2 * y * z - 2 * w * x, 1 - 2 * x * x - 2 * y * y, 0,
    0, 0, 0, 1,
  ];
  return `matrix3d(${matrix.join(",")})`;
}

function handlePose(pose) {
  const now = Date.now();
  updateTimes.push(now);
  updateTimes = updateTimes.filter((time) => time >= now - 1000);
  elements.rate.textContent = `${updateTimes.length} Hz`;
  elements.latency.textContent = `${Math.max(0, now - pose.sentAtUnixMilliseconds)} ms`;
  elements.sequence.textContent = pose.sequenceNumber;
  elements.quaternion.textContent = format([pose.quaternion.w, pose.quaternion.x, pose.quaternion.y, pose.quaternion.z]);
  elements.rotation.textContent = format([pose.rotationRate.x, pose.rotationRate.y, pose.rotationRate.z]);
  elements.phone.style.transform = quaternionMatrix(pose.quaternion);
}

function connectDisplay(sessionID) {
  const scheme = location.protocol === "https:" ? "wss" : "ws";
  socket = new WebSocket(`${scheme}://${location.host}/display?session=${encodeURIComponent(sessionID)}`);
  socket.addEventListener("open", () => setStatus("Waiting", "waiting"));
  socket.addEventListener("message", (event) => {
    let message;
    try { message = JSON.parse(event.data); } catch { return; }
    if (message.protocolVersion !== 1) return;
    if (message.type === "displayState") {
      const label = message.payload.connected ? "Connected" : (message.payload.hasConnected ? "Disconnected" : "Waiting");
      const style = message.payload.connected ? "connected" : (message.payload.hasConnected ? "disconnected" : "waiting");
      setStatus(label, style);
    } else if (message.type === "livePose") {
      handlePose(message.payload);
    } else if (message.type === "clubSelection") {
      elements.club.textContent = message.payload.club.replaceAll("_", " ");
    }
  });
  socket.addEventListener("close", () => {
    setStatus("Disconnected", "disconnected");
    setTimeout(() => connectDisplay(sessionID), 1500);
  });
  socket.addEventListener("error", () => socket.close());
}

fetch("/api/session")
  .then((response) => {
    if (!response.ok) throw new Error(`Session request failed (${response.status})`);
    return response.json();
  })
  .then((session) => {
    elements.qr.src = session.qrDataURL;
    elements.pairingURL.textContent = session.pairingURL;
    connectDisplay(session.sessionID);
  })
  .catch((error) => setStatus(error.message, "disconnected"));
