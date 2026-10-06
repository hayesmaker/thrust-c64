// Game controls for the player: the virtual gamepad, physical gamepads and
// the pause button all end up as Thrust's keys. Thrust reads the keyboard
// only, so each control holds a key, sent to c64-ready as a key event.

export type Action = 'left' | 'right' | 'thrust' | 'shield' | 'fire' | 'pause' | 'resume' | 'abort';

/** The key each action holds: [KeyboardEvent.key, KeyboardEvent.code]. */
export const ACTION_KEYS: Record<Action, [string, string]> = {
  left: ['a', 'KeyA'],
  right: ['s', 'KeyS'],
  thrust: ['Shift', 'ShiftLeft'],
  shield: [' ', 'Space'],
  fire: ['Enter', 'Enter'],
  pause: ['F5', 'F5'],
  resume: ['F7', 'F7'],
  abort: ['Escape', 'Escape'],
};

/** Below this share of the radius from the centre, the D-pad is neutral. */
export const DPAD_DEAD = 0.25;
/** sin 22.5°: 8-way sectors */
const SECTOR = 0.383;

/** D-pad: left/right rotate, up thrusts, down shields; diagonals hold two. */
export function dpadActions(dx: number, dy: number, radius: number): Action[] {
  const len = Math.hypot(dx, dy);
  if (len < radius * DPAD_DEAD) return [];
  const ux = dx / len;
  const uy = dy / len;
  const out: Action[] = [];
  if (ux < -SECTOR) out.push('left');
  if (ux > SECTOR) out.push('right');
  if (uy < -SECTOR) out.push('thrust');
  if (uy > SECTOR) out.push('shield');
  return out;
}

/** Standard-mapping gamepad buttons (https://w3c.github.io/gamepad/#remapping). */
const BUTTONS: Partial<Record<number, Action>> = {
  0: 'thrust', // A / cross
  1: 'shield', // B / circle
  2: 'fire', // X / square
  3: 'fire', // Y / triangle
  4: 'shield', // LB
  5: 'fire', // RB
  6: 'shield', // LT
  7: 'thrust', // RT
  8: 'abort', // Back / Select: Run/Stop
  12: 'thrust', // D-pad up
  13: 'shield', // D-pad down
  14: 'left',
  15: 'right',
};
/** Start: pause / resume (a toggle, see gamepadActions) */
export const START_BUTTON = 9;
const STICK = 0.5;

/** The actions a gamepad holds (Start is reported separately as `start`). */
export function gamepadActions(buttons: readonly boolean[], axes: readonly number[]): { held: Set<Action>; start: boolean } {
  const held = new Set<Action>();
  buttons.forEach((down, i) => {
    const a = BUTTONS[i];
    if (down && a) held.add(a);
  });
  const [x = 0, y = 0] = axes;
  if (x <= -STICK) held.add('left');
  if (x >= STICK) held.add('right');
  if (y <= -STICK) held.add('thrust');
  if (y >= STICK) held.add('shield');
  return { held, start: !!buttons[START_BUTTON] };
}

/**
 * Combines what each source (a finger, a gamepad) holds and reports key
 * changes: a key goes down when the first source holds it and up when the
 * last one lets go.
 */
export class KeyMixer {
  private sources = new Map<string, Set<Action>>();
  private down = new Set<Action>();

  constructor(private send: (type: 'keydown' | 'keyup', action: Action, shift: boolean) => void) {}

  set(source: string, actions: Iterable<Action>): void {
    const s = new Set(actions);
    if (s.size) this.sources.set(source, s);
    else this.sources.delete(source);
    this.sync();
  }

  /** Press and release, for keys the game only needs to see once (pause). */
  tap(action: Action, ms = 120): void {
    const id = `tap:${action}`;
    this.set(id, [action]);
    setTimeout(() => this.set(id, []), ms);
  }

  isDown(action: Action): boolean {
    return this.down.has(action);
  }

  releaseAll(): void {
    this.sources.clear();
    this.sync();
  }

  private sync(): void {
    const want = new Set<Action>();
    for (const s of this.sources.values()) for (const a of s) want.add(a);
    // c64-ready lets go of the C64's Shift on any key down without shiftKey,
    // so thrust goes down first, every key down carries it, and it goes up last
    const order = (a: Action) => (a === 'thrust' ? 0 : 1);
    const ups = [...this.down].filter((a) => !want.has(a)).sort((a, b) => order(b) - order(a));
    const downs = [...want].filter((a) => !this.down.has(a)).sort((a, b) => order(a) - order(b));
    for (const a of ups) {
      this.down.delete(a);
      this.send('keyup', a, this.down.has('thrust'));
    }
    for (const a of downs) {
      this.down.add(a);
      this.send('keydown', a, this.down.has('thrust'));
    }
  }
}
