// How objects look: the game's own sprites, in the level's colours or in one
// colour per object type.

import { PALETTE } from '../c64';
import type { Colours } from '../model/level';
import { SPRITE_FIRST, SPRITE_H, SPRITE_W, SPRITES } from '../model/sprites';

/** One hardware sprite of an object. `game` is its colour in the game. */
interface Part {
  frame: number;
  game: (c: Colours) => number;
  type: string;
}

const YELLOW = () => 7;
const OBJECTS = (c: Colours) => c.objects;

/** Sprites per object type, as plot_object_sprite draws them. The pod sits
 *  on its stand in the mc3 colour (pod_colour). */
const PARTS: Part[][] = [
  [{ frame: 0x22, game: OBJECTS, type: '#ff5c5c' }],
  [{ frame: 0x23, game: OBJECTS, type: '#ff5c5c' }],
  [{ frame: 0x24, game: OBJECTS, type: '#ff5c5c' }],
  [{ frame: 0x25, game: OBJECTS, type: '#ff5c5c' }],
  [{ frame: 0x2e, game: YELLOW, type: '#ffd84a' }],
  [
    { frame: 0x28, game: (c) => c.mc3, type: '#e8d4ff' },
    { frame: 0x29, game: OBJECTS, type: '#b07cff' },
  ],
  [
    { frame: 0x2a, game: YELLOW, type: '#ff9a3c' },
    { frame: 0x2b, game: OBJECTS, type: '#ffc98f' },
  ],
  [{ frame: 0x2c, game: YELLOW, type: '#ff8ad8' }],
  [{ frame: 0x2d, game: YELLOW, type: '#ff8ad8' }],
];

/** The parts of an object: sprite frame and CSS colour. */
export function objectParts(type: number, colours: Colours, gameColours: boolean): { frame: number; colour: string }[] {
  return (PARTS[type] ?? []).map((p) => ({
    frame: p.frame,
    // a black sprite would vanish on the black background
    colour: gameColours ? PALETTE[p.game(colours) || 1] : p.type,
  }));
}

/** Swatch colour of an object type: its main (last) part. */
export function swatchColour(type: number, colours: Colours, gameColours: boolean): string {
  return objectParts(type, colours, gameColours).at(-1)?.colour ?? '#aaa';
}

/** Visible extent of an object's sprites from its top-left (X units, rows).
 *  A sprite pixel is 1/4 unit wide and 1/2 row high. */
export interface Bounds {
  x0: number;
  y0: number;
  x1: number;
  y1: number;
}

function frameBounds(frame: number): Bounds | null {
  const lines = SPRITES[frame - SPRITE_FIRST];
  let x0 = SPRITE_W;
  let x1 = -1;
  let y0 = SPRITE_H;
  let y1 = -1;
  lines.forEach((bits, y) => {
    for (let x = 0; x < SPRITE_W; x++)
      if (bits & (1 << (SPRITE_W - 1 - x))) {
        x0 = Math.min(x0, x);
        x1 = Math.max(x1, x);
        y0 = Math.min(y0, y);
        y1 = Math.max(y1, y);
      }
  });
  return x1 < 0 ? null : { x0: x0 / 4, y0: y0 / 2, x1: (x1 + 1) / 4, y1: (y1 + 1) / 2 };
}

export const OBJ_BOUNDS: Bounds[] = PARTS.map((parts) =>
  parts
    .map((p) => frameBounds(p.frame))
    .reduce<Bounds>(
      (a, b) => (b ? { x0: Math.min(a.x0, b.x0), y0: Math.min(a.y0, b.y0), x1: Math.max(a.x1, b.x1), y1: Math.max(a.y1, b.y1) } : a),
      { x0: Infinity, y0: Infinity, x1: -Infinity, y1: -Infinity },
    ),
);

/** Sprite width and height in X units and rows. */
export const SPRITE_UNITS = SPRITE_W / 4;
export const SPRITE_ROWS = SPRITE_H / 2;

const cache = new Map<string, HTMLCanvasElement>();

/** A sprite frame as a 24x21 canvas in one colour (cached). */
export function spriteImage(frame: number, colour: string): HTMLCanvasElement {
  const key = `${frame}:${colour}`;
  let cv = cache.get(key);
  if (cv) return cv;
  cv = document.createElement('canvas');
  cv.width = SPRITE_W;
  cv.height = SPRITE_H;
  const c = cv.getContext('2d')!;
  c.fillStyle = colour;
  SPRITES[frame - SPRITE_FIRST].forEach((bits, y) => {
    for (let x = 0; x < SPRITE_W; x++) if (bits & (1 << (SPRITE_W - 1 - x))) c.fillRect(x, y, 1, 1);
  });
  cache.set(key, cv);
  return cv;
}
