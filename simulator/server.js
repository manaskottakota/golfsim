const crypto = require("node:crypto");
const http = require("node:http");
const os = require("node:os");
const path = require("node:path");
const fs = require("node:fs");
const QRCode = require("qrcode");
const { WebSocketServer, WebSocket } = require("ws");

const PROTOCOL_VERSION = 1;
const PORT = Number(process.env.PORT || 8080);
const PUBLIC_DIRECTORY = path.join(__dirname, "public");

function localIPv4Addresses() {
  return Object.values(os.networkInterfaces())
    .flat()
    .filter((address) => address && address.family === "IPv4" && !address.internal)
    .map((address) => address.address);
}

const advertisedHost = process.env.GOLFSIM_HOST || localIPv4Addresses()[0] || "127.0.0.1";
const session = {
  id: crypto.randomBytes(12).toString("base64url"),
  token: crypto.randomBytes(24).toString("base64url"),
  controller: null,
  displays: new Set(),
  hasConnected: false,
};

function pairingURL() {
  const socketURL = `ws://${advertisedHost}:${PORT}/controller`;
  const parameters = new URLSearchParams({
    v: String(PROTOCOL_VERSION),
    session: session.id,
    token: session.token,
    ws: socketURL,
  });
  return `golfsim://pair?${parameters.toString()}`;
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
    const contentTypes = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css" };
    response.writeHead(200, { "Content-Type": `${contentTypes[extension] || "application/octet-stream"}; charset=utf-8` });
    response.end(data);
  });
}

const server = http.createServer(async (request, response) => {
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
  socket.isAlive = true;
  socket.on("pong", () => { socket.isAlive = true; });

  if (role === "/display") {
    session.displays.add(socket);
    send(socket, "displayState", { connected: Boolean(session.controller), hasConnected: session.hasConnected });
    socket.on("close", () => session.displays.delete(socket));
    return;
  }

  if (session.controller) {
    send(session.controller, "disconnect", { reason: "A new iPhone connected to this session." });
    session.controller.close(1000, "Replaced by new controller");
  }
  session.controller = socket;

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
      session.hasConnected = true;
      send(socket, "connectionAccepted", { sessionID: session.id });
      broadcast("phoneHello", message.payload);
      broadcast("displayState", { connected: true, hasConnected: true });
    } else if (message.type === "ping") {
      send(socket, "pong", message.payload);
    } else if (message.type === "disconnect") {
      socket.close(1000, message.payload.reason || "Controller disconnected");
    } else if (["livePose", "clubSelection", "pong"].includes(message.type)) {
      broadcast(message.type, message.payload);
    } else {
      send(socket, "error", { message: `Message type ${message.type} is not accepted from a phone.` });
    }
  });

  socket.on("close", () => {
    if (session.controller === socket) {
      session.controller = null;
      broadcast("displayState", { connected: false, hasConnected: session.hasConnected });
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
