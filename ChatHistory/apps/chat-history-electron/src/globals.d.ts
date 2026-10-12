import type { ChatHistoryApi } from "./model";

declare global {
  interface Window {
    chatHistory: ChatHistoryApi;
  }
}

export {};
