// Minimal KickAssembler source reader/writer for labelled `.byte` tables.
//
// A block is a `label:` line followed by consecutive `.byte` lines. Values are
// numbers ($hex, %bin, decimal) or kept as raw expression strings such as
// `<(level_2_reset_data+3)`. Writing a block only rewrites lines whose values
// changed; everything else in the file (comments, code) is left untouched.

export type AsmValue = number | string;

interface BlockLine {
  index: number; // line number in the file
  values: AsmValue[];
}

export interface AsmBlock {
  label: string;
  lines: BlockLine[];
}

export interface AsmDoc {
  lines: string[];
  eol: string;
  blocks: Map<string, AsmBlock>;
}

const LABEL_RE = /^([A-Za-z_]\w*):\s*(\/\/.*)?$/;
const BYTE_RE = /^(\s*)\.byte\s+(.*)$/;

function stripComment(s: string): string {
  const i = s.indexOf('//');
  return i < 0 ? s : s.slice(0, i);
}

export function parseValue(tok: string): AsmValue {
  const t = tok.trim();
  if (/^\$[0-9a-fA-F]+$/.test(t)) return parseInt(t.slice(1), 16);
  if (/^%[01]+$/.test(t)) return parseInt(t.slice(1), 2);
  if (/^\d+$/.test(t)) return parseInt(t, 10);
  return t;
}

export function formatValue(v: AsmValue): string {
  return typeof v === 'number' ? '$' + (v & 0xff).toString(16).padStart(2, '0') : v;
}

export function parseAsm(text: string): AsmDoc {
  const eol = text.includes('\r\n') ? '\r\n' : '\n';
  const lines = text.split(/\r?\n/);
  const blocks = new Map<string, AsmBlock>();
  let current: AsmBlock | null = null;
  lines.forEach((line, index) => {
    const lm = LABEL_RE.exec(line);
    if (lm) {
      current = { label: lm[1], lines: [] };
      blocks.set(lm[1], current);
      return;
    }
    const bm = BYTE_RE.exec(line);
    if (bm && current) {
      const payload = stripComment(bm[2]).trim();
      const values = payload ? payload.split(',').map(parseValue) : [];
      current.lines.push({ index, values });
      return;
    }
    if (line.trim() !== '' || (current && current.lines.length > 0)) current = null;
  });
  return { lines, eol, blocks };
}

export function serializeAsm(doc: AsmDoc): string {
  return doc.lines.join(doc.eol);
}

export function blockValues(doc: AsmDoc, label: string): AsmValue[] {
  const b = doc.blocks.get(label);
  if (!b) throw new Error(`label not found: ${label}`);
  return b.lines.flatMap((l) => l.values);
}

export function blockBytes(doc: AsmDoc, label: string): number[] {
  return blockValues(doc, label).map((v) => {
    if (typeof v !== 'number') throw new Error(`${label}: expression "${v}" where a number was expected`);
    return v;
  });
}

const sameValues = (a: AsmValue[], b: AsmValue[]) =>
  a.length === b.length && a.every((v, i) => (typeof v === 'number' ? v === b[i] : String(v) === String(b[i])));

export interface WriteOptions {
  /** Values per line when the block layout has to change. Default: keep a
   *  one-line block on one line, otherwise 16. */
  perLine?: number;
}

/** Replace a block's values. Returns true if the file changed. */
export function writeBlock(doc: AsmDoc, label: string, values: AsmValue[], opts: WriteOptions = {}): boolean {
  const b = doc.blocks.get(label);
  if (!b) throw new Error(`label not found: ${label}`);
  const old = b.lines.flatMap((l) => l.values);
  if (sameValues(old, values)) return false;
  const indent = (BYTE_RE.exec(doc.lines[b.lines[0].index]) ?? ['', '    '])[1];
  const fmt = (vs: AsmValue[]) => `${indent}.byte ${vs.map(formatValue).join(',')}`;

  // same layout: rewrite only the lines that changed
  const sizes = b.lines.map((l) => l.values.length);
  if (values.length === old.length && opts.perLine === undefined) {
    let pos = 0;
    for (const l of b.lines) {
      const nv = values.slice(pos, pos + l.values.length);
      pos += l.values.length;
      if (!sameValues(l.values, nv)) {
        doc.lines[l.index] = fmt(nv);
        l.values = nv;
      }
    }
    return true;
  }

  const per = opts.perLine ?? (sizes.length === 1 ? Math.max(values.length, 1) : 16);
  const chunks: AsmValue[][] = [];
  for (let i = 0; i < values.length; i += per) chunks.push(values.slice(i, i + per));
  const first = b.lines[0].index;
  const removed = b.lines.length;
  doc.lines.splice(first, removed, ...chunks.map(fmt));
  b.lines = chunks.map((vs, k) => ({ index: first + k, values: vs }));
  const shift = chunks.length - removed;
  if (shift !== 0) {
    for (const other of doc.blocks.values())
      if (other !== b) for (const l of other.lines) if (l.index > first) l.index += shift;
  }
  return true;
}
