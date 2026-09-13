import { Buffer } from "node:buffer";

/** JSON syntax is checked without unescaping unused strings or retaining their object trees. */
export class JsonRange {
  private fields?: Record<string, JsonRange>;
  private elements?: JsonRange[];
  constructor(readonly source: Buffer, readonly start: number, readonly end: number) {}
  get isString() {
    return this.source[this.start] === 34;
  }
  get isEmptyString() {
    return this.isString && this.end === this.start + 2;
  }
  string(): string {
    return this.isString ? JSON.parse(this.source.toString("utf8", this.start, this.end)) : "";
  }
  object(): Record<string, JsonRange> | undefined {
    if (this.source[this.start] !== 123) return;
    if (!this.fields) {
      const fields: Record<string, JsonRange> = Object.create(null);
      let cursor = whitespace(this.source, this.start + 1, this.end);
      while (this.source[cursor] !== 125) {
        const keyEnd = scan(this.source, cursor, this.end);
        const key = JSON.parse(this.source.toString("utf8", cursor, keyEnd));
        cursor = whitespace(this.source, whitespace(this.source, keyEnd, this.end) + 1, this.end);
        const end = scan(this.source, cursor, this.end);
        fields[key] = new JsonRange(this.source, cursor, end);
        cursor = whitespace(this.source, end, this.end);
        if (this.source[cursor] === 44) cursor = whitespace(this.source, cursor + 1, this.end);
      }
      this.fields = fields;
    }
    return this.fields;
  }
  array(): JsonRange[] | undefined {
    if (this.source[this.start] !== 91) return;
    if (!this.elements) {
      this.elements = [];
      let cursor = whitespace(this.source, this.start + 1, this.end);
      while (this.source[cursor] !== 93) {
        const end = scan(this.source, cursor, this.end);
        this.elements.push(new JsonRange(this.source, cursor, end));
        cursor = whitespace(this.source, end, this.end);
        if (this.source[cursor] === 44) cursor = whitespace(this.source, cursor + 1, this.end);
      }
    }
    return this.elements;
  }
  boolean() {
    return this.source[this.start] === 116;
  }
}

function whitespace(source: Buffer, index: number, end: number) {
  while (index < end && [32, 9, 10, 13].includes(source[index])) index++;
  return index;
}
function invalid(): never {
  throw new SyntaxError("Invalid JSON record");
}
function scan(source: Buffer, start: number, end: number, depth = 0): number {
  if (depth > 512 || start >= end) return invalid();
  const token = source[start];
  let index = start + 1;
  if (token === 34) {
    while (index < end) {
      const character = source[index++];
      if (character === 34) return index;
      if (character < 32) return invalid();
      if (character === 92) {
        const escape = source[index++];
        if (escape === 117) {
          for (let n = 0; n < 4; n++) {
            const hex = source[index++];
            if (!(hex >= 48 && hex <= 57 || hex >= 65 && hex <= 70 || hex >= 97 && hex <= 102)) {
              return invalid();
            }
          }
        } else if (![34, 92, 47, 98, 102, 110, 114, 116].includes(escape)) return invalid();
      }
    }
    return invalid();
  }
  if (token === 123 || token === 91) {
    const close = token === 123 ? 125 : 93;
    index = whitespace(source, index, end);
    if (source[index] === close) return index + 1;
    while (index < end) {
      if (token === 123) {
        if (source[index] !== 34) return invalid();
        index = whitespace(source, scan(source, index, end, depth + 1), end);
        if (source[index++] !== 58) return invalid();
        index = whitespace(source, index, end);
      }
      index = whitespace(source, scan(source, index, end, depth + 1), end);
      if (source[index] === close) return index + 1;
      if (source[index++] !== 44) return invalid();
      index = whitespace(source, index, end);
    }
    return invalid();
  }
  for (const literal of ["true", "false", "null"]) {
    if (token === literal.charCodeAt(0)) {
      for (let n = 0; n < literal.length; n++) {
        if (source[start + n] !== literal.charCodeAt(n)) return invalid();
      }
      return start + literal.length;
    }
  }
  index = start;
  if (source[index] === 45) index++;
  if (source[index] === 48) index++;
  else {
    if (!(source[index] >= 49 && source[index] <= 57)) return invalid();
    while (source[index] >= 48 && source[index] <= 57) index++;
  }
  if (source[index] === 46) {
    index++;
    if (!(source[index] >= 48 && source[index] <= 57)) return invalid();
    while (source[index] >= 48 && source[index] <= 57) index++;
  }
  if (source[index] === 101 || source[index] === 69) {
    index++;
    if (source[index] === 43 || source[index] === 45) index++;
    if (!(source[index] >= 48 && source[index] <= 57)) return invalid();
    while (source[index] >= 48 && source[index] <= 57) index++;
  }
  return index;
}

export function parseJsonRange(source: Buffer, start = 0, end = source.length) {
  start = whitespace(source, start, end);
  const valueEnd = scan(source, start, end);
  if (whitespace(source, valueEnd, end) !== end) return invalid();
  return new JsonRange(source, start, valueEnd);
}

export type DeferredText = string | { decode(): string; nonempty: boolean };
export function textValue(value: unknown): DeferredText {
  if (value instanceof JsonRange) {
    return { decode: () => value.string(), nonempty: value.isString && !value.isEmptyString };
  }
  return typeof value === "string" ? value : "";
}
export function decodeText(value: DeferredText) {
  return typeof value === "string" ? value : value.decode();
}
export function hasText(value: DeferredText) {
  return typeof value === "string" ? value.length > 0 : value.nonempty;
}
export function deferText(decode: () => string, nonempty = true): DeferredText {
  return { decode, nonempty };
}
export function isStringValue(value: unknown) {
  return typeof value === "string" || value instanceof JsonRange && value.isString;
}
