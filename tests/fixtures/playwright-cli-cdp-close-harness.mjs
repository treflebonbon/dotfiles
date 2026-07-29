import { pathToFileURL } from "node:url";

const cdpClosePath = process.argv.at(2);

globalThis.fetch = () =>
  Promise.resolve({
    json: () =>
      Promise.resolve({ webSocketDebuggerUrl: "ws://managed-chrome" }),
    ok: true,
  });

globalThis.WebSocket = class extends EventTarget {
  constructor() {
    super();
    queueMicrotask(() => this.dispatchEvent(new Event("open")));
  }

  send() {
    queueMicrotask(() => this.dispatchEvent(new Event("message")));
  }

  close() {
    this.dispatchEvent(new Event("close"));
  }
};

process.argv = [process.execPath, cdpClosePath, "http://127.0.0.1:9222"];
await import(pathToFileURL(cdpClosePath));
