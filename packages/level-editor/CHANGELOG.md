# Changelog: Thrust level editor

## Unreleased

* Hosting at thrust.hayesmaker64.com: deploy kit in `deploy/` (pm2, nginx, provisioning).
* Build server: KickAssembler can run through a sandbox wrapper (`KICKASS_JAVA`); builds
  have a time limit (`BUILD_TIMEOUT_MS`) and a queue cap (`BUILD_MAX_QUEUE`, 503 when full);
  `BUILDS_DIR` moves build output.

## 0.1.0

* First version: terrain, objects, doors and rules editing; game files; Build & play in
  the embedded c64-ready emulator.
