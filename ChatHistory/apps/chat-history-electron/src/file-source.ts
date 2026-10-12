import { Buffer } from "node:buffer";
import { closeSync, fstatSync, openSync, readSync } from "node:fs";

const blockSize = 64 * 1024;
const maxBlocks = 8;
const handles = new FinalizationRegistry<number>((fd) => closeSync(fd));

/** Standard positional reads in the parser worker; at most 512 KiB of source cache. */
export class FileSource {
  readonly length: number;
  private fd: number;
  private blocks = new Map<number, Buffer>();
  private currentStart = -1;
  private current: Buffer = Buffer.alloc(0);
  constructor(path: string) {
    this.fd = openSync(path, "r");
    try { this.length = fstatSync(this.fd).size; }
    catch (error) { closeSync(this.fd); throw error; }
    handles.register(this, this.fd, this);
  }
  get byteLength() { return this.length; }
  at(index: number): number | undefined {
    if (index < 0 || index >= this.length) return undefined;
    if (index < this.currentStart || index >= this.currentStart + this.current.length) {
      if (this.fd < 0) throw new Error("Document source is closed");
      const start = Math.floor(index / blockSize) * blockSize;
      let block = this.blocks.get(start);
      if (!block) {
        block = Buffer.allocUnsafe(Math.min(blockSize, this.length - start));
        let count = 0;
        while (count < block.length) {
          const n = readSync(this.fd, block, count, block.length - count, start + count);
          if (!n) throw new Error("Transcript changed or was truncated while open");
          count += n;
        }
        if (this.blocks.size === maxBlocks) this.blocks.delete(this.blocks.keys().next().value!);
        this.blocks.set(start, block);
      }
      this.currentStart = start;
      this.current = block;
    }
    return this.current[index - this.currentStart];
  }
  readBytes(start: number, end: number): Buffer {
    if (this.fd < 0) throw new Error("Document source is closed");
    if (start < 0 || end < start || end > this.length) throw new RangeError("Invalid source range");
    if (start >= this.currentStart && end <= this.currentStart + this.current.length) {
      return this.current.subarray(start - this.currentStart, end - this.currentStart);
    }
    const bytes = Buffer.allocUnsafe(end - start);
    let count = 0;
    while (count < bytes.length) {
      const n = readSync(this.fd, bytes, count, bytes.length - count, start + count);
      if (!n) throw new Error("Transcript changed or was truncated while open");
      count += n;
    }
    return bytes;
  }
  toString(encoding: BufferEncoding, start = 0, end = this.length): string {
    return this.readBytes(start, end).toString(encoding);
  }
  lineRanges(): number[] {
    const ranges: number[] = [];
    let start = 0;
    for (let position = 0; position < this.length; position += blockSize) {
      this.at(position);
      const block = this.current;
      for (let index = block.indexOf(10); index !== -1; index = block.indexOf(10, index + 1)) {
        let end = position + index;
        if (end > start && this.at(end - 1) === 13) end--;
        if (end > start) ranges.push(start, end);
        start = position + index + 1;
      }
    }
    let end = this.length;
    if (end > start && this.at(end - 1) === 13) end--;
    if (end > start) ranges.push(start, end);
    return ranges;
  }
  close() {
    if (this.fd < 0) return;
    closeSync(this.fd);
    this.fd = -1;
    handles.unregister(this);
    this.blocks.clear();
    this.current = Buffer.alloc(0);
    this.currentStart = -1;
  }
}
export type ByteSource = Buffer | FileSource;
