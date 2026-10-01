const net = require("node:net");

const PROTOCOL_VERSION = 1;

function isLoopback(host) {
  const normalized = host.trim().toLowerCase();
  return normalized === "localhost" || normalized === "::1" || normalized.startsWith("127.");
}

function isPrivateIPv4(host) {
  if (net.isIP(host) !== 4) return false;
  const [a, b] = host.split(".").map(Number);
  return a === 10 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168);
}

function chooseAdvertisedHost(networkInterfaces, configuredHost) {
  if (configuredHost) {
    const host = configuredHost.trim();
    if (!host || isLoopback(host)) {
      throw new Error("GOLFSIM_HOST must be a LAN-reachable hostname or address, not localhost or loopback.");
    }
    return host;
  }

  const addresses = Object.entries(networkInterfaces)
    .flatMap(([name, entries]) => (entries || []).map((entry) => ({ name, ...entry })))
    .filter((entry) => entry.family === "IPv4" && !entry.internal && !isLoopback(entry.address))
    .sort((a, b) => interfaceRank(a.name) - interfaceRank(b.name));
  const selected = addresses.find((entry) => isPrivateIPv4(entry.address))?.address || addresses[0]?.address;
  if (!selected) {
    throw new Error("No LAN-reachable IPv4 address was found. Set GOLFSIM_HOST to the laptop's Wi-Fi address.");
  }
  return selected;
}

function interfaceRank(name) {
  const normalized = name.toLowerCase();
  if (/^(en0|wi-?fi|wlan0)$/.test(normalized)) return 0;
  if (/^(en1|wlan\d+|wl)/.test(normalized)) return 1;
  if (/(bridge|docker|vbox|vmnet|utun|tun|tap)/.test(normalized)) return 10;
  return 5;
}

function createPairingURL({ host, port, sessionID, token }) {
  if (isLoopback(host)) throw new Error("Refusing to create a pairing QR with a loopback host.");
  const socketURL = `ws://${host}:${port}/controller`;
  const parameters = new URLSearchParams({
    v: String(PROTOCOL_VERSION),
    session: sessionID,
    token,
    ws: socketURL,
  });
  return `golfsim://pair?${parameters.toString()}`;
}

module.exports = {
  PROTOCOL_VERSION,
  chooseAdvertisedHost,
  createPairingURL,
  isLoopback,
};
