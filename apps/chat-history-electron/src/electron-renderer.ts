import { initializeGrammarPack } from "./syntax-highlighting";
import { mountChatHistory } from "./renderer";

await initializeGrammarPack(await window.chatHistory.getGrammarSource());
mountChatHistory();
