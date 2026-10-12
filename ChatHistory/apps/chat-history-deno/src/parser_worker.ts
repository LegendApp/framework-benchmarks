import {
  DocumentRegistry,
  type DocumentRequest,
} from "../../chat-history-electron/src/document-registry";
const registry = new DocumentRegistry();
globalThis.onmessage = async (event: MessageEvent<DocumentRequest & { id: number }>) => {
  const request = event.data;
  try {
    globalThis.postMessage({ id: request.id, result: await registry.request(request) });
  } catch (error) {
    globalThis.postMessage({ id: request.id, error: String(error) });
  }
};
