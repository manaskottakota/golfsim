const crypto = require("node:crypto");
const http = require("node:http");
const os = require("node:os");
const path = require("node:path");
const fs = require("node:fs");
const QRCode = require("qrcode");
const { WebSocketServer, WebSocket } = require("ws");
const { PROTOCOL_VERSION, chooseAdvertisedHost, createPairingURL } = require("./server-config");

const PORT = Number(process.env.PORT || 8080);
const PUBLIC_DIRECTORY = path.join(__dirname, "public");

const advertisedHost = chooseAdvertisedHost(os.networkInterfaces(), process.env.GOLFSIM_HOST);
const session = {
  id: crypto.randomBytes(12).toString("base64url"),
  token: crypto.randomBytes(24).toString("base64url"),
  controller: null,
  controllerAccepted: false,
  displays: new Set(),
  hasConnected: false,
};

function pairingURL() {
  return createPairingURL({
    host: advertisedHost,
    port: PORT,
    sessionID: session.id,
    token: session.token,
  });
}

function send(socket, type, payload) {
  if (socket.readyState !== WebSocket.OPEN) return;
  socket.send(JSON.stringify({ protocolVersion: PROTOCOL_VERSION, type, payload }));
}

function broadcast(type, payload) {
  for (const display of session.displays) send(display, type, payload);
}

function serveStatic(request, response) {
  const requestPath = request.url === "/" ? "/index.html" : new URL(request.url, "http://localhost").pathname;
  const filePath = path.normalize(path.join(PUBLIC_DIRECTORY, requestPath));
  if (!filePath.startsWith(PUBLIC_DIRECTORY)) {
    response.writeHead(403).end("Forbidden");
    return;
  }
  fs.readFile(filePath, (error, data) => {
    if (error) {
      response.writeHead(404).end("Not found");
      return;
    }
    const extension = path.extname(filePath);
    const contentTypes = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".svg": "image/svg+xml" };
    response.writeHead(200, { "Content-Type": `${contentTypes[extension] || "application/octet-stream"}; charset=utf-8` });
    response.end(data);
  });
}

const server = http.createServer(async (request, response) => {
  if (request.url.startsWith("/api/qr.png")) {
    try {
      const png = await QRCode.toBuffer(pairingURL(), { errorCorrectionLevel: "M", margin: 2, width: 360, type: "png" });
      response.writeHead(200, { "Content-Type": "image/png", "Cache-Control": "no-store" });
      response.end(png);
    } catch (error) {
      response.writeHead(500).end("QR generation failed");
    }
    return;
  }
  if (request.url === "/api/session") {
    const pairURL = pairingURL();
    const qrDataURL = await QRCode.toDataURL(pairURL, { errorCorrectionLevel: "M", margin: 2, width: 360 });
    response.writeHead(200, { "Content-Type": "application/json", "Cache-Control": "no-store" });
    response.end(JSON.stringify({ sessionID: session.id, pairingURL: pairURL, qrDataURL }));
    return;
  }
  serveStatic(request, response);
});

const webSocketServer = new WebSocketServer({ noServer: true });

server.on("upgrade", (request, socket, head) => {
  const url = new URL(request.url, `http://${request.headers.host}`);
  if (!["/controller", "/display"].includes(url.pathname)) {
    socket.destroy();
    return;
  }
  if (url.searchParams.get("session") !== session.id) {
    socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
    socket.destroy();
    return;
  }
  if (url.pathname === "/controller" && url.searchParams.get("token") !== session.token) {
    socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
    socket.destroy();
    return;
  }
  webSocketServer.handleUpgrade(request, socket, head, (webSocket) => {
    webSocketServer.emit("connection", webSocket, request, url.pathname);
  });
});

webSocketServer.on("connection", (socket, request, role) => {
  console.log(`[ws] ${role === "/controller" ? "iPhone controller" : "browser display"} socket opened`);
  socket.isAlive = true;
  socket.on("pong", () => { socket.isAlive = true; });

  if (role === "/display") {
    session.displays.add(socket);
    send(socket, "displayState", {
      connected: session.controllerAccepted,
      hasConnected: session.hasConnected,
      sessionID: session.id,
    });
    socket.on("message", (buffer) => {
      let message;
      try { message = JSON.parse(buffer.toString()); } catch { return; }
      if (message.type === "disconnectController" && session.controller) {
        send(session.controller, "disconnect", { reason: "Disconnected from the laptop simulator." });
        session.controller.close(1000, "Disconnected from display");
      }
    });
    socket.on("close", () => session.displays.delete(socket));
    return;
  }

  if (session.controller) {
    send(session.controller, "disconnect", { reason: "A new iPhone connected to this session." });
    session.controller.close(1000, "Replaced by new controller");
  }
  session.controller = socket;
  session.controllerAccepted = false;

  socket.on("message", (buffer, isBinary) => {
    let message;
    try {
      message = JSON.parse(buffer.toString());
    } catch {
      send(socket, "error", { message: "Malformed JSON message." });
      return;
    }
    if (message.protocolVersion !== PROTOCOL_VERSION || typeof message.type !== "string" || !message.payload) {
      send(socket, "error", { message: "Unsupported or malformed protocol message." });
      return;
    }

    if (message.type === "phoneHello") {
      console.log(`[controller] phoneHello from ${message.payload.deviceName || "iPhone"}`);
      if (typeof message.payload.deviceName !== "string" || typeof message.payload.appVersion !== "string") {
        send(socket, "error", { message: "Malformed phoneHello payload." });
        return;
      }
      session.controllerAccepted = true;
      session.hasConnected = true;
      send(socket, "connectionAccepted", { sessionID: session.id });
      broadcast("phoneHello", message.payload);
      broadcast("displayState", { connected: true, hasConnected: true, sessionID: session.id });
      console.log("[controller] accepted; telemetry forwarding enabled");
    } else if (message.type === "ping") {
      send(socket, "pong", message.payload);
    } else if (message.type === "disconnect") {
      socket.close(1000, message.payload.reason || "Controller disconnected");
    } else if (["livePose", "clubSelection", "swingStatus", "swingResult", "pong"].includes(message.type)) {
      if (!session.controllerAccepted) {
        send(socket, "error", { message: "Send phoneHello before telemetry." });
        return;
      }
      broadcast(message.type, message.payload);
    } else {
      send(socket, "error", { message: `Message type ${message.type} is not accepted from a phone.` });
    }
  });

  socket.on("close", (code, reason) => {
    console.log(`[controller] socket closed (${code}) ${reason?.toString() || ""}`);
    if (session.controller === socket) {
      session.controller = null;
      session.controllerAccepted = false;
      broadcast("displayState", { connected: false, hasConnected: session.hasConnected, sessionID: session.id });
    }
  });
  socket.on("error", (error) => console.error("Controller socket error:", error.message));
});

const heartbeat = setInterval(() => {
  for (const socket of webSocketServer.clients) {
    if (!socket.isAlive) {
      socket.terminate();
      continue;
    }
    socket.isAlive = false;
    socket.ping();
  }
}, 15_000);

server.on("close", () => clearInterval(heartbeat));
server.listen(PORT, "0.0.0.0", () => {
  console.log(`golfsim laptop simulator: http://localhost:${PORT}`);
  console.log(`Phone pairing address: ws://${advertisedHost}:${PORT}`);
  console.log("Open the simulator URL on this laptop, then scan its QR code in the iPhone app.");
});
