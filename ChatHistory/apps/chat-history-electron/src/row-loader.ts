import type { ChatDocument, ChatRow } from "./model";

/** Batch viewport requests; discard this cache with its document. */
export class RowLoader {
  private cache = new Map<number, Promise<ChatRow>>();
  private pending = new Map<
    number,
    { resolve: (row: ChatRow) => void; reject: (error: unknown) => void }
  >();
  constructor(
    private document: ChatDocument,
    private fetchRows: (
      id: string,
      indices: number[],
      includeToolPreview?: boolean,
    ) => Promise<ChatRow[]>,
  ) {}
  get(index: number): Promise<ChatRow> {
    const row = this.document.rows[index];
    if (!row.deferred || !this.document.documentId) return Promise.resolve(row);
    let promise = this.cache.get(index);
    if (!promise) {
      promise = new Promise((resolve, reject) => {
        this.pending.set(index, { resolve, reject });
        if (this.pending.size === 1) queueMicrotask(() => this.flush());
      });
      this.cache.set(index, promise);
    }
    return promise;
  }
  async preview(index: number): Promise<string> {
    if (!this.document.documentId) return this.document.rows[index].toolPreview;
    return (await this.fetchRows(this.document.documentId, [index], true))[0].toolPreview;
  }
  private flush() {
    const pending = [...this.pending];
    this.pending.clear();
    for (let start = 0; start < pending.length; start += 256) {
      const batch = pending.slice(start, start + 256);
      void this.fetchRows(this.document.documentId!, batch.map(([index]) => index)).then((rows) => {
        if (rows.length !== batch.length) throw new Error("Incomplete viewport row response");
        batch.forEach(([, request], index) => request.resolve(rows[index]));
      }).catch((error) =>
        batch.forEach(([index, request]) => {
          this.cache.delete(index);
          request.reject(error);
        })
      );
    }
  }
}
