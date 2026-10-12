import { closeChatDocument, openChatFile } from "./parser";
import {
  type ChatDocument,
  type ChatProvider,
  type ChatRow,
  normalizedContentDigest,
} from "./model";

export type DocumentRequest =
  | { op: "open"; provider: ChatProvider; path: string }
  | { op: "rows"; documentId: string; indices: number[]; includeToolPreview?: boolean }
  | { op: "digest"; documentId: string };

/** One active document per window. The source and deferred text remain in its worker. */
export class DocumentRegistry {
  private generation = 0;
  private active?: { id: string; document: ChatDocument };
  async request(request: DocumentRequest): Promise<ChatDocument | ChatRow[] | string> {
    if (request.op === "open") {
      const generation = ++this.generation;
      if (this.active) closeChatDocument(this.active.document);
      this.active = undefined;
      const document = await openChatFile(request.provider, request.path);
      if (generation !== this.generation) {
        closeChatDocument(document);
        throw new Error("Document open was superseded");
      }
      const id = String(generation);
      this.active = { id, document };
      return {
        ...document,
        documentId: id,
        rows: document.rows.map((row) => ({
          id: row.id,
          kind: row.kind,
          fileChanges: row.fileChanges,
          imageSources: row.imageSources,
          hasImagePlaceholder: row.hasImagePlaceholder,
          toolName: row.toolName,
          toolStatus: row.toolStatus,
          markdown: "",
          toolPreview: "",
          deferred: true,
        })),
      };
    }
    if (!this.active || this.active.id !== request.documentId) {
      throw new Error("Document is no longer open");
    }
    const document = this.active.document;
    if (request.op === "digest") return normalizedContentDigest(document.rows);
    if (
      !Array.isArray(request.indices) || request.indices.length > 256 || request.indices.some(
        (index) => !Number.isInteger(index) || index < 0 || index >= document.rows.length,
      )
    ) throw new Error("Invalid row request");
    return request.indices.map((index) => {
      const row = document.rows[index];
      return {
        id: row.id,
        kind: row.kind,
        fileChanges: row.fileChanges,
        imageSources: row.imageSources,
        hasImagePlaceholder: row.hasImagePlaceholder,
        toolName: row.toolName,
        toolStatus: row.toolStatus,
        markdown: row.markdown,
        toolPreview: request.includeToolPreview ? row.toolPreview : "",
      };
    });
  }
}
