// The title screen lines: the game's name on row 15 and "BY <author>" on row
// 16 of the high score screen (msg_title_text / msg_author_text in
// level_tables.asm, centred by the assembler).

export const TITLE_MAX = 28;
export const AUTHOR_PREFIX = 'BY ';
export const AUTHOR_MAX = TITLE_MAX - AUTHOR_PREFIX.length;
export const DEFAULT_TITLE = 'SUPER THRUSTY MAKER';

/** Text as the game's font can show it: A-Z (upper case), 0-9, space and
 *  '.'; '-' and '_' become spaces, other characters are dropped. */
export function fontText(s: string, max: number): string {
  return s
    .toUpperCase()
    .replace(/[-_]/g, ' ')
    .replace(/[^A-Z0-9 .]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max)
    .trim();
}

/** What a name / author box keeps while typing: fontText without trimming
 *  the end (so a space can be typed between words). */
export function fontTyping(s: string, max: number): string {
  return s
    .toUpperCase()
    .replace(/[-_]/g, ' ')
    .replace(/[^A-Z0-9 .]/g, '')
    .replace(/ {2,}/g, ' ')
    .replace(/^ +/, '')
    .slice(0, max);
}

/** The title line for a game name (empty: the default title). */
export const titleText = (name: string): string => fontText(name, TITLE_MAX) || DEFAULT_TITLE;

/** The author line ('' when there is no author). */
export function authorText(author: string): string {
  const a = fontText(author, AUTHOR_MAX);
  return a ? AUTHOR_PREFIX + a : '';
}

const ascii = (s: string) => [...s].map((c) => c.charCodeAt(0));
export const titleBytes = (name: string): number[] => ascii(titleText(name));
/** No author: one space (the block cannot be empty). */
export const authorBytes = (author: string): number[] => ascii(authorText(author) || ' ');

/** Text column of the first character (as the assembler centres it). */
export const titleColumn = (text: string): number => Math.floor((40 - text.length) / 2);

const hex = (v: number) => '$' + v.toString(16).padStart(2, '0');

/** The level_tables.asm title section with these texts (the positions and
 *  length checks are in the mod's thrust.asm). */
export function titleAsm(title: number[] = titleBytes(DEFAULT_TITLE), author: number[] = authorBytes('')): string {
  return [
    '// ----------------------------------------------------------------------------',
    "// Title screen lines (high score screen): the game's name and its author",
    '// ("BY ..."; a single space for none), ASCII. Positions (row 15 and 16,',
    "// centred) are in thrust.asm. The font has A-Z (always shown in upper case),",
    "// 0-9, space and '.'; anything else shows as '.'. At most 28 characters each.",
    '// ----------------------------------------------------------------------------',
    'msg_title:',
    '    .byte <title_pos, >title_pos',
    'msg_title_text:',
    `    .byte ${title.map(hex).join(',')}`,
    'msg_title_end:',
    '    .byte $ff',
    'msg_author:',
    '    .byte <author_pos, >author_pos',
    'msg_author_text:',
    `    .byte ${author.map(hex).join(',')}`,
    'msg_author_end:',
    '    .byte $ff',
  ].join('\n');
}

/** Rebuild the title section of level_tables.asm in the current form, keeping
 *  its texts: earlier versions had no title, no author line, or carried the
 *  positions themselves (which then went stale when the layout changed). */
export function upgradeTitle(tablesAsm: string): string {
  const eol = tablesAsm.includes('\r\n') ? '\r\n' : '\n';
  const lines = tablesAsm.replace(/(\r?\n)*$/, '').split(/\r?\n/);
  const texts = (label: string): number[] | null => {
    const at = lines.findIndex((l) => l.startsWith(label + ':'));
    if (at < 0) return null;
    const vals = (lines[at + 1] ?? '').replace(/\/\/.*/, '').replace(/^\s*\.byte\s*/, '').split(',');
    const out = vals.map((v) => parseInt(v.trim().replace('$', ''), 16)).filter((v) => Number.isFinite(v));
    return out.length ? out : null;
  };
  const title = texts('msg_title_text') ?? titleBytes(DEFAULT_TITLE);
  const author = texts('msg_author_text') ?? authorBytes('');
  const related = (l: string) =>
    /^msg_(title|author)(_text|_end)?:/.test(l) || /^\.(label|errorif)\b.*(title|author)/.test(l);
  const first = lines.findIndex(related);
  if (first >= 0) {
    let last = first;
    lines.forEach((l, k) => {
      if (related(l)) last = k;
    });
    if (/^\s*\.byte\b/.test(lines[last + 1] ?? '')) last++; // the $ff after a msg_*_end label
    let start = first;
    while (start > 0 && lines[start - 1].startsWith('//')) start--;
    lines.splice(start, last - start + 1);
  }
  const fresh = titleAsm(title, author).split('\n');
  return [...lines, ...fresh].join(eol) + eol;
}
