# Changelog: Thrust level editor

## Unreleased

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
