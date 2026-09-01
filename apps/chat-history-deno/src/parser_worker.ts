import type {
  ChatDocument,
  ChatProvider,
} from "../../chat-history-electron/src/model";
import { openChatFile } from "../../chat-history-electron/src/parser";

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

globalThis.onmessage = async (event: MessageEvent<ParseRequest>) => {
  const request = event.data;
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
  globalThis.postMessage(response);
};
