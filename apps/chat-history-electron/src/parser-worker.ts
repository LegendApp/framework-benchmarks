import { parentPort } from "node:worker_threads";
import type { ChatDocument, ChatProvider } from "./model";
import { openChatFile } from "./parser";

type ParseRequest = {
  id: number;
  path: string;
  provider: ChatProvider;
};

type ParseResponse = {
  error?: string;
  id: number;
  result?: ChatDocument;
};

const port = parentPort;
if (!port) {
  throw new Error("The transcript parser must run in a worker thread");
}

port.on("message", async (request: ParseRequest) => {
  let response: ParseResponse;
  try {
    response = {
      id: request.id,
      result: await openChatFile(request.provider, request.path),
    };
  } catch (error) {
    response = {
      error: error instanceof Error ? error.stack ?? error.message : String(error),
      id: request.id,
    };
  }
  port.postMessage(response);
});
