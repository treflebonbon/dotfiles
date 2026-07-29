import { once } from "node:events";
import { setTimeout as delay } from "node:timers/promises";

const [endpoint] = process.argv.slice(2);

if (!endpoint) {
  throw new Error("CDP endpoint is required");
}

const response = await fetch(`${endpoint}/json/version`);
if (!response.ok) {
  throw new Error(`CDP version request failed with HTTP ${response.status}`);
}

const { webSocketDebuggerUrl } = await response.json();
if (!webSocketDebuggerUrl) {
  throw new Error("CDP response did not include webSocketDebuggerUrl");
}

const socket = new WebSocket(webSocketDebuggerUrl);
const opened = await Promise.race([
  once(socket, "open").then(() => true),
  once(socket, "error").then(() => false),
  delay(5000, undefined, { ref: false }).then(() => false),
]);
if (!opened) {
  socket.close();
  throw new Error("Browser.close connection failed");
}

socket.send(JSON.stringify({ id: 1, method: "Browser.close" }));
const result = await Promise.race([
  once(socket, "message").then(() => "message"),
  once(socket, "close").then(() => "close"),
  once(socket, "error").then(() => "error"),
  delay(5000, undefined, { ref: false }).then(() => "timeout"),
]);
if (result === "error" || result === "timeout") {
  socket.close();
  throw new Error(`Browser.close ${result}`);
}
if (result === "message") {
  socket.close();
}
