import { describe, expect, it } from 'vitest';
import { OBJ_BOUNDS, objectParts, swatchColour } from '../src/editor/look';
import { OBJ_SIZE, ObjType } from '../src/model/level';
import { SNAP } from '../src/model/objects';

const COLOURS = { terrain: 2, mc1: 9, mc3: 8, status: 1, objects: 5, shield: 14 };

describe('object look', () => {
  it('has a sprite for every object type', () => {
    expect(OBJ_BOUNDS).toHaveLength(OBJ_SIZE.length);
    for (const b of OBJ_BOUNDS) expect(b.x1).toBeGreaterThan(b.x0);
  });

  it('shows snapped floor objects flush on the floor', () => {
    for (const type of [ObjType.Fuel, ObjType.PodStand, ObjType.Generator]) {
      // snapObject puts the top at floor - height - gap
      const floorFromTop = OBJ_SIZE[type][1] + SNAP[type].gap;
      expect(OBJ_BOUNDS[type].y1, `type ${type}`).toBe(floorFromTop);
    }
  });

  it('uses the level colours in game mode and one colour per type otherwise', () => {
    // fuel is always yellow in the game
    expect(objectParts(ObjType.Fuel, { ...COLOURS, objects: 0 }, true)[0].colour).toBe(objectParts(ObjType.Fuel, COLOURS, true)[0].colour);
    // gun, pod stand and generator dome all take the level's objects colour
    expect(new Set([0, 5, 6].map((t) => swatchColour(t, COLOURS, true))).size).toBe(1);
    expect(new Set([0, 4, 5, 6, 7].map((t) => swatchColour(t, COLOURS, false))).size).toBe(5);
  });
});
