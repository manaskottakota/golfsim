const assert = require("node:assert/strict");
const test = require("node:test");
const { chooseAdvertisedHost, createPairingURL } = require("../server-config");

test("prefers a private LAN address for the pairing QR", () => {
  const host = chooseAdvertisedHost({
    tunnel: [{ family: "IPv4", internal: false, address: "100.64.0.2" }],
    wifi: [{ family: "IPv4", internal: false, address: "192.168.1.25" }],
  });
  assert.equal(host, "192.168.1.25");
});

test("rejects loopback pairing hosts", () => {
  assert.throws(() => chooseAdvertisedHost({}, "127.0.0.1"), /LAN-reachable/);
  assert.throws(() => createPairingURL({ host: "localhost", port: 8080, sessionID: "a", token: "b" }), /loopback/);
});

test("creates a Swift-compatible versioned pairing payload", () => {
  const value = createPairingURL({
    host: "192.168.1.25",
    port: 8080,
    sessionID: "session_123",
    token: "token-456",
  });
  const url = new URL(value);
  assert.equal(url.protocol, "golfsim:");
  assert.equal(url.hostname, "pair");
  assert.equal(url.searchParams.get("v"), "1");
  assert.equal(url.searchParams.get("session"), "session_123");
  assert.equal(url.searchParams.get("token"), "token-456");
  assert.equal(url.searchParams.get("ws"), "ws://192.168.1.25:8080/controller");
});
