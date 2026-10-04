// Export: terrain `.byte` lines for one level, and file downloads.

import { formatValue } from '../model/asm';
import { type Level, wallTables } from '../model/level';

export function terrainAsm(l: Level): string {
  const L = wallTables(l.left);
  const R = wallTables(l.right);
  const block = (s: string, vals: number[]) =>
    `terrain_data_level_${l.index}_${s}:\n    .byte ${vals.map(formatValue).join(',')}`;
  return [block('A', L.counts), block('B', L.steps), block('C', R.counts), block('D', R.steps)].join('\n') + '\n';
}

export function download(name: string, text: string, type = 'text/plain'): void {
  const url = URL.createObjectURL(new Blob([text], { type }));
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
