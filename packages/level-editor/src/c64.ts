// C64 palette (same values as tools/render.py).
export const PALETTE = [
  '#000000', '#ffffff', '#883932', '#67b6bd', '#8b3f96', '#55a049', '#40318d', '#bfce72',
  '#8b5429', '#574200', '#b86962', '#505050', '#787878', '#94e089', '#7869c4', '#9f9f9f',
];

export const PALETTE_RGB: [number, number, number][] = PALETTE.map((h) => [
  parseInt(h.slice(1, 3), 16),
  parseInt(h.slice(3, 5), 16),
  parseInt(h.slice(5, 7), 16),
]);

/** Map colours per object type (as tools/levelview.py). */
export const OBJ_COLOUR = [2, 2, 2, 2, 7, 5, 14, 4, 4];

export const hex2 = (v: number) => '$' + (v & 0xff).toString(16).padStart(2, '0');
export const hex3 = (v: number) => '$' + v.toString(16).padStart(3, '0');
