# Changelog: Thrust level editor

## Unreleased

* Opening a game file (or the autosave) keeps its name and author the way the
  name / author boxes would: the font's characters, upper case, at most 28 /
  25 characters. A name or author that isn't text, or a bad level number, no
  longer breaks opening the file.

## 0.3.1

* The player is always full screen and the game fills it: only ✕ (close),
  **Pad** and **Pause** remain, floating over the game, and the on-screen pad
  floats over it too. Messages fade after a few seconds. Rebuild, Restart,
  Sound and Window are gone. Tap the game to go back to full screen after
  leaving it.

## 0.3.0

* Touch screens: pinch zoom and two-finger pan; tap selects, drag moves
  relative to the finger (no jump) with a loupe showing the spot; hold a wall
  line to add a point; bigger handles and touch targets; a toolbar with undo /
  redo, fit, zoom, nudges (×8), Step / Free (Shift / Alt) and Delete. Mouse
  and keyboard work as before.
* Phones: the canvas takes most of the screen, the panel below it.
* Build & play opens the game full screen, with the buttons and help beside it
  (never over it); **Window** puts it back over the map.
* On-screen gamepad for touch screens (D-pad, Shield, Thrust, Fire), shown on
  phones and tablets; **Pad** shows or hides it.
* Gamepads: D-pad / stick rotate (up thrust, down shield), A thrust, B shield,
  X fire, Start pause, Back abort. All controls press Thrust's keys.
* **Pause / Resume** button (F5 / F7).

## 0.2.4

* New games start without a name, and Build / Build & play ask for one first, so
  games don't all come out titled "MY THRUST GAME". Games saved with that old
  default name open without a name.
* Deploy scripts take versions with or without the "v" (`0.2.4` or `v0.2.4`).

## 0.2.3

* Fix: `deploy.sh` could not find pm2 when it belongs to an nvm Node; `deploy.sh`
  now runs the deployed version's own `update.sh`.

## 0.2.2

* Link previews: description, Open Graph and Twitter card tags, and a preview
  image (`public/og-image.png`, made from `docs/og/card.html`).

## 0.2.1

* Fix: `deploy.sh` (update.sh over a plain ssh command) found neither fnm nor pm2.

## 0.2.0

* The panel shows the editor's version next to its title (the release tag, from
  `git describe` at build time).
* New games start from the original six levels (`thrusty-levels/examples/template.json`,
  served at `/api/template`) instead of the mod's draft level 0.
* `npm run mod-to-game`: write a game file from the mod's level files (`--original`:
  with the original game's levels).
* Fix: saving levels into other level files (game-to-mod, the template) wrote unedited
  walls as the target file's walls instead of the level's own.
* Hosting at thrust.hayesmaker64.com: deploy kit in `deploy/` (pm2, nginx, provisioning).
* Build server: KickAssembler can run through a sandbox wrapper (`KICKASS_JAVA`); builds
  have a time limit (`BUILD_TIMEOUT_MS`) and a queue cap (`BUILD_MAX_QUEUE`, 503 when full);
  `BUILDS_DIR` moves build output.

## 0.1.0

* First version: terrain, objects, doors and rules editing; game files; Build & play in
  the embedded c64-ready emulator.
