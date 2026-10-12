import { parentPort } from "node:worker_threads";
import { DocumentRegistry, type DocumentRequest } from "./document-registry";
const registry = new DocumentRegistry();
if (!parentPort) throw new Error("The document registry must run in a worker");
const port = parentPort;
port.on("message", async (request: DocumentRequest & { id: number }) => {
  try {
    port.postMessage({ id: request.id, result: await registry.request(request) });
  } catch (error) {
    port.postMessage({ id: request.id, error: String(error) });
  }
});
