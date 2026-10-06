import { describe, expect, it, vi } from 'vitest';
import { type Action, KeyMixer, START_BUTTON, dpadActions, gamepadActions } from '../src/editor/controls';

describe('game controls', () => {
  it('maps the D-pad to rotate, thrust and shield, 8 ways', () => {
    expect(dpadActions(0, 0, 60)).toEqual([]);
    expect(dpadActions(10, 0, 60)).toEqual([]); // inside the dead zone
    expect(dpadActions(-50, 0, 60)).toEqual(['left']);
    expect(dpadActions(50, 5, 60)).toEqual(['right']);
    expect(dpadActions(0, -50, 60)).toEqual(['thrust']);
    expect(dpadActions(0, 50, 60)).toEqual(['shield']);
    expect(dpadActions(-40, -40, 60)).toEqual(['left', 'thrust']);
    expect(dpadActions(40, 40, 60)).toEqual(['right', 'shield']);
  });

  it('maps standard gamepad buttons and the left stick', () => {
    const buttons = (...down: number[]) => Array.from({ length: 17 }, (_, i) => down.includes(i));
    expect([...gamepadActions(buttons(0), [0, 0]).held]).toEqual(['thrust']);
    expect([...gamepadActions(buttons(1, 2), [0, 0]).held].sort()).toEqual(['fire', 'shield']);
    expect([...gamepadActions(buttons(14), []).held]).toEqual(['left']);
    expect([...gamepadActions(buttons(), [0.8, 0]).held]).toEqual(['right']);
    expect([...gamepadActions(buttons(), [-0.3, 0.2]).held]).toEqual([]);
    expect([...gamepadActions(buttons(), [0, -0.9]).held]).toEqual(['thrust']);
    expect(gamepadActions(buttons(START_BUTTON), []).start).toBe(true);
    expect(gamepadActions(buttons(START_BUTTON), []).held.size).toBe(0);
  });

  it('holds a key while any source holds it', () => {
    const log: string[] = [];
    const m = new KeyMixer((type, a) => log.push(`${type} ${a}`));
    m.set('finger1', ['fire']);
    m.set('gamepad', ['fire', 'left']);
    m.set('finger1', []);
    expect(log).toEqual(['keydown fire', 'keydown left']);
    m.set('gamepad', []);
    expect(log.slice(2).sort()).toEqual(['keyup fire', 'keyup left']);
    expect(m.isDown('fire')).toBe(false);
  });

  it('keeps Shift (thrust) held across other keys', () => {
    const log: [string, Action, boolean][] = [];
    const m = new KeyMixer((type, a, shift) => log.push([type, a, shift]));
    m.set('a', ['left', 'thrust']);
    expect(log).toEqual([
      ['keydown', 'thrust', true],
      ['keydown', 'left', true],
    ]);
    log.length = 0;
    m.releaseAll();
    expect(log).toEqual([
      ['keyup', 'left', true],
      ['keyup', 'thrust', false],
    ]);
  });

  it('taps a key down and up', () => {
    vi.useFakeTimers();
    const log: string[] = [];
    const m = new KeyMixer((type, a) => log.push(`${type} ${a}`));
    m.tap('pause');
    expect(log).toEqual(['keydown pause']);
    vi.advanceTimersByTime(200);
    expect(log).toEqual(['keydown pause', 'keyup pause']);
    vi.useRealTimers();
  });
});
