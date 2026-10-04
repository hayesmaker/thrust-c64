# Thrust level editor: user guide

The level editor lets you redesign the six levels of **Thrust** (Commodore 64,
Firebird 1986) in your browser: drag the cave walls into shape, place guns,
fuel and the pod, set where the ship restarts, pick gravity and colours, and
press one button to play your level in a C64 emulator.

It edits the **thrusty-levels** mod (`packages/thrusty-levels`). Your changes
end up in two source files of that mod, `levels.asm` and `level_tables.asm`,
which build into a normal C64 program (`.prg`).

![The editor: level 2 with a wall point selected](img/overview.png)

## Contents

1. [Getting started](#1-getting-started)
2. [The screen](#2-the-screen)
3. [Moving around](#3-moving-around)
4. [How Thrust levels work](#4-how-thrust-levels-work)
5. [Editing the cave walls](#5-editing-the-cave-walls)
6. [Objects: guns, fuel, pod, reactor](#6-objects-guns-fuel-pod-reactor)
7. [Restart points](#7-restart-points)
8. [Gravity and colours](#8-gravity-and-colours)
9. [Checks](#9-checks)
10. [Memory](#10-memory)
11. [Building and playing](#11-building-and-playing)
12. [Saving your work](#12-saving-your-work)
13. [Keyboard and mouse reference](#13-keyboard-and-mouse-reference)
14. [Troubleshooting](#14-troubleshooting)

---

## 1. Getting started

You need:

* **Node.js 24** or newer
* **Java** and **KickAssembler 5** at `/opt/KickAss.jar` (or set the
  `KICKASS` environment variable to its path). Only needed for building and
  playing; you can edit without it.

Start the editor:

```
cd packages/level-editor
npm install          # first time only
npm run dev
```

Open the address it prints (normally <http://localhost:5173>). The editor
opens the six levels of the mod straight away.

Prefer a fixed address? `npm run serve` builds the editor and serves it at
<http://127.0.0.1:5180>.

> The editor server can write your mod source (only when you click
> **Save to mod source**), so it only listens on your own computer.

## 2. The screen

**The map (left).** The current level, drawn the way the game draws it:
rock in the level's colour, the cave in black. On top of it:

| You see | It is |
|---------|-------|
| blue line and squares | the **left wall** and its points |
| orange line and squares | the **right wall** and its points |
| grey dot at the top | the fixed start of a wall (cannot be moved) |
| dashed line below the last point | the wall carries on straight down from there |
| dashed wall segment | an uneven slope (costs extra memory, see [5](#5-editing-the-cave-walls)) |
| coloured boxes with numbers | objects (guns, fuel, pod stand, reactor, door switches) |
| white crosses `start`, `R1`, `R2`... | restart points |
| dashed boxes | roughly what the screen shows when the ship restarts there |
| red dashed vertical line | the edge of the world: X wraps around from `$FF` to `$00` |
| orange stripes (levels 3-5) | the level's door |

Rulers show the position: **X** across the top (0-255, in hex), the **row**
down the left (hex above, decimal below). The bar at the bottom shows the
position under the mouse.

**The panel (right).** From top to bottom:

* **Level**: pick level 0-5 ("mission 1-6"), memory meters.
* **Build and play**: build the game and play it, save to the mod source.
* **Selection**: details of whatever you clicked (wall point, object or
  restart point), with fields you can type into.
* **Checks**: problems with the level. Click one to jump to the object.
* **Objects**: add objects, the list of objects.
* **Restart points**: the list, add a restart point.
* **Gravity and colours**, **Terrain tables** (the raw numbers): click the
  heading to open them.
* **Export**, **Project**, **View**, **Controls**.

## 3. Moving around

| Do | To |
|----|----|
| drag empty space | pan |
| mouse wheel | scroll up and down (Shift + wheel: sideways) |
| Ctrl + wheel, or `+` / `-` | zoom |
| `F` or the **Fit** button | fit the whole cave in view |
| `1` - `6` | switch to level 0 - 5 |

## 4. How Thrust levels work

A few facts make the editor much easier to understand.

**Two walls.** Every level is a cave between a **left wall** and a **right
wall**. Everything left of the left wall and right of the right wall is rock.
Above the planet both walls sit at the far edges, so the sky is open.

**Rows and X.** The world is 256 units wide (X `$00`-`$FF`) and wraps around:
fly off the right edge and you come back on the left. One X unit is 4 pixels
on the C64 screen. Going down, the world is measured in **rows** of 2 pixels.
Levels start around row 400 (`$190`); the surface is usually around row
420-470 and caves go down to row 800-1300. The map is drawn in the game's
proportions, so it looks like the real thing.

**Walls are made of straight pieces.** The game stores a wall as "for N rows,
move X by S each row". In the editor you simply place points and the wall runs
in straight lines between them:

* **Vertical**: a segment where X does not change.
* **The classic Thrust slope**: 1 X unit per row (about 27°).
* **Shallow slopes**: 2, 3... units per row.
* **Ledges**: a jump in one row (two points on neighbouring rows).
* **Steeper than the classic slope**: the game has no such slope; it is
  made of little steps. The editor builds the steps for you, but each step
  costs memory (see below).

**The cave must close.** Below the last point a wall goes straight down
forever. Make the walls meet at the bottom, or the cave stays open (Checks
warns about this).

## 5. Editing the cave walls

![A selected wall point; the dashed segment above it is an uneven slope](img/walls.png)

| Do | To |
|----|----|
| drag a point | move it |
| Shift + drag | move it, keeping the segment above it a clean slope (a whole number of X per row) |
| click on a wall line | add a point there (you can keep dragging) |
| click below the last point, on the dashed line | add a new last point |
| right-click a point, or select it and press Delete | remove it |
| arrow keys | nudge the selected point by 1 (Shift: by 8) |
| type in **row** / **X** in the panel | place it exactly |

Points cannot pass each other: a point always stays below the one before it
and above the one after it. The grey point at the top of each wall is fixed.

**Watch for dashed segments.** A segment whose X change does not divide evenly
by its number of rows (say 60 rows and 5 units across) is drawn **dashed**. The
game can only do it as a staircase, and every step is two more entries in the
level's tables. The panel tells you the cost, e.g. "steep: 60 rows, X +5 ...
→ 10 table entries". To avoid it, hold **Shift** while dragging, or move the
point so the segment becomes vertical or an even slope. The original levels use
almost only vertical walls, 1-per-row slopes and ledges.

**Doors (levels 3, 4, 5).** These levels have a door that opens when you shoot
a door switch. The door is part of the game's program, not of the level data:
it always appears at the same place (shown in orange stripes). Keep the left
wall where it is around the door, or the door will not fit the cave any more.

## 6. Objects: guns, fuel, pod, reactor

![A gun selected: its firing arc in red, gun settings in the panel](img/objects.png)

| Object | What it does |
|--------|--------------|
| gun up-right, gun up-left | sits on a floor, fires upwards |
| gun down-right, gun down-left | hangs from a ceiling, fires downwards |
| fuel | collect with the tractor beam |
| pod stand | where the pod sits; carry it out of the planet to finish the level |
| generator | the reactor: shooting it silences the guns for a while; hit it too often and the planet starts a countdown to explode |
| door switch R / L | opens the door (levels 3-5 only); sits against a wall |

**Add** an object with the buttons in the **Objects** section: it appears in
the middle of the map, already resting on the nearest floor. **Drag** it where
you want it.

**Snapping.** Objects snap onto the terrain the way they sit in the original
game: fuel, pod stand, reactor and upward guns rest on the floor below them,
downward guns hang from the ceiling above, door switches stick to the wall
beside them. Hold **Alt** while dragging to place freely, or turn snapping off
under **View**. **Snap to terrain** in the panel puts a selected object back
on the ground. Up/down arrow keys nudge objects without snapping.

**Guns.** Select a gun to see its firing arc (red). Set:

* **fires from**: the direction the arc starts at (up, up-right, right, ...).
* **spread**: how wide the arc is. The gun fires at random directions
  clockwise from the start direction across the spread.

Tick **firing arcs of all guns** under **View** to see every gun's arc at
once.

**Order matters.** The game has a few rules about the object list, and the
editor follows them for you when you add objects:

* **Object 0 must be the pod stand.**
* **Fuel must be among the first 12 objects** (later fuel cells do not work).
* **At most 32 objects** per level.

Use ▲ / ▼ to move the selected object in the list, or **Sort objects** (pod
stand, reactor, fuel, then the rest).

## 7. Restart points

Restart points are where the ship comes back after losing a life: the last
restart point above the deepest place it reached (if it was carrying the pod,
the next one down instead). `start` (restart point 0) is where the level
begins.

* **Drag** a cross to move it. The dashed box (roughly the screen at that
  moment) moves with it.
* **Add restart point** puts a new one in the middle of the map. Restart points
  are kept in order from top to bottom.
* Select one to type exact values. **Centre window on ship** puts the screen
  box back around the ship.
* The start position cannot be deleted.

Keep restart points in open space (not in rock) and in order from top to
bottom; Checks warns otherwise.

## 8. Gravity and colours

Open **Gravity and colours** in the panel.

* **Gravity**: bigger is stronger. The original levels use 5, 7, 9, 11, 12
  and 13 for levels 0-5.
* **Colours**: six colours from the C64 palette: the rock (and text), two
  bitmap colours, the status bar labels, the guns / pod stand / reactor, and
  the shield. The map redraws in the new colours.

## 9. Checks

The **Checks** section lists problems in the current level:

* **✖ errors**: the level will not work (e.g. object 0 is not the pod stand,
  too many objects, out of memory). Fix these.
* **! warnings**: probably a mistake (no reactor, restart point inside rock,
  cave open at the bottom, memory getting tight).
* **i notes**: worth knowing (an object floating above the ground, the
  level's door).

Click a message about an object or restart point to select it. A ✓ next to
the heading means no errors or warnings.

## 10. Memory

The C64 has little room for level data, and the meters under **Level** show how
much is used:

* **terrain + objects** (in the mod's levels area, `$1000-$1FFF`): 4096 bytes.
* **restart points** (in the main program): about 1240 bytes.

The numbers are close estimates; the build makes the final check.

![Memory getting tight](img/memory.png)

When an area gets **tight** (less than 10% free) its meter turns amber and a
banner appears above Build & play. When it is **over**, everything turns red,
Checks shows an error, and the build will fail until you remove something.

What costs memory:

| Thing | Bytes |
|-------|-------|
| each wall piece (table entry) | 2 |
| each step of an uneven (dashed) slope | 4 (two entries) |
| each object | 5 |
| each restart point | 6 |

The six original levels together use about 900 bytes, so there is plenty of
room. The quickest savings are dashed slopes: make them even with Shift-drag.

## 11. Building and playing

![Playing level 3 in the built-in emulator](img/play.png)

**Build & play** (or **Ctrl + Enter**) builds the game with your changes and
starts it in the built-in C64 emulator. It takes about a second. Nothing is
written to the mod source.

With **start the game on this level** ticked (the default), the game starts on
the level you are editing, so you do not have to play through the others.
Untick it to play from level 0 as normal.

Game keys:

| Key | Action |
|-----|--------|
| Space | start the game; shield and tractor beam |
| A / S | rotate left / right |
| Shift | thrust |
| Return | fire |
| F5 / F7 | pause / resume |
| Esc | abort the game (Run/Stop) |

While the game is shown, the editor's own keys are switched off. The buttons
above the game:

* **Rebuild**: build your latest edits and restart. Edit, rebuild, try again.
* **Restart**: run the same build again.
* **Sound off / on**.
* **Close**: back to the editor.

**Build** only builds, without playing, e.g. to check for errors. If the build
fails, the panel lists the errors with the table they are in, and the full
KickAssembler log.

After a build you can also **Download PRG** (to run in VICE or on a real C64)
or **Open in c64-ready** (the c64-ready emulator site; its address can be
changed under **View**).

## 12. Saving your work

**Autosave.** Every change is saved in your browser as you work. Close the tab
and come back: your project is still there. Undo / Redo (Ctrl+Z /
Ctrl+Shift+Z) work across all edits.

**Save to mod source.** When you are happy with a change, click **Save to mod
source…** under Build and play. The editor shows what changed ("level 0:
terrain, objects") and asks before writing `levels.asm` and
`level_tables.asm` in `packages/thrusty-levels/src`. The previous files are
copied to `packages/level-editor/.backups/` first. Then build the mod as
usual (`./packages/thrusty-levels/build.sh`) or commit it.

If those files were changed by something else since you opened them (another
editor, git), the editor refuses to overwrite them. Use **Save JSON** to keep
your work, then **Load mod source** to start from the files on disk.

**Other ways to keep or move your work (Project and Export sections):**

| Button | Does |
|--------|------|
| Save JSON / Open JSON | save or open the whole project as a file |
| Load mod source | open the mod's files from disk (replaces the current project) |
| Open .asm files | open `levels.asm` + `level_tables.asm` from anywhere (or drop them on the page) |
| Revert level | throw away your changes to the current level |
| Copy terrain .byte lines | copy the current level's wall tables, ready to paste into `levels.asm` |
| levels.asm / level_tables.asm | download the two files with your changes |

## 13. Keyboard and mouse reference

| Input | Action |
|-------|--------|
| drag point / object / restart cross | move it |
| Shift + drag point | keep an even slope |
| Alt + drag object | do not snap to the terrain |
| click a wall line | add a point |
| right-click, Delete, Backspace | delete the thing under the mouse / the selection |
| arrows (Shift: ×8) | nudge the selection |
| Esc | deselect |
| drag empty space, wheel | pan |
| Ctrl + wheel, `+`, `-` | zoom |
| `F` | fit the level |
| `1` - `6` | level 0 - 5 |
| Ctrl + Z, Ctrl + Shift + Z (or Ctrl + Y) | undo, redo |
| Ctrl + Enter | build and play |

## 14. Troubleshooting

**"no build API here" / "the editor server is not running".** Building,
playing and saving need the editor's server: start the editor with `npm run
dev` or `npm run serve` (not by opening the HTML file).

**"Restart the editor server".** The server is older than the page. Stop
`npm run dev` and start it again.

**"The mod source changed on disk since this project was loaded".** Someone
(or git) changed the mod's files after you loaded them. Save to mod source will
refuse. Save JSON if you want to keep your edits, then Load mod source.

**The build fails.** Read the error list under Build and play. Out of memory:
see [Memory](#10-memory). Anything else is usually a hand edit in the `.asm`
files; the KickAssembler log has the details.

**The memory meter shows one bar labelled "main block".** The editor does not
know the mod's levels area. Restart the editor server, then reload the page.

**Keys do nothing in the game.** Click anywhere on the page so the browser tab
has the keyboard. Thrust uses the keyboard only (no joystick); see the key
table in [Building and playing](#11-building-and-playing).

**An object floats above the ground in the game.** Select it and click
**Snap to terrain**. Checks lists objects that are not resting on the
terrain.
