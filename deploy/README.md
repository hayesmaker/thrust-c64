# Deploying the level editor

The editor runs at **https://thrust.hayesmaker64.com** on the DigitalOcean droplet:
nginx serves the built app from `packages/level-editor/dist/` and proxies `/api/` to
the Node build server (pm2 app `thrust-level-editor`, `127.0.0.1:5180`), which runs
KickAssembler in a bubblewrap sandbox.

Nothing in this folder is secret. The server address and your user name live only in
`~/.ssh/config` on your machine; the server clones the public repo over HTTPS, so it
needs no GitHub key.

| File | Runs | Does |
|---|---|---|
| `provision.sh` | server, once, with sudo | Java 21, bubblewrap, KickAssembler 5.25 at `/opt/KickAss.jar`, nginx site |
| `update.sh <ref>` | server | fetch, check out a tag or branch, `npm ci`, build, test, `pm2 reload` |
| `deploy.sh <ref>` | your machine | `ssh thrust-host …/update.sh <ref>` |
| `release.sh <version>` | your machine | test, bump the version, commit, tag `v<version>` |
| `ecosystem.config.cjs` | pm2 | the app, its port and build limits |
| `nginx/thrust.hayesmaker64.com.conf` | nginx | static files, `/api/` proxy, build rate limit |
| `kickass-sandbox.sh` | build server | runs KickAssembler with only `/usr`, the jar and the build folder visible |

## First deploy

**1. DNS.** Add an A record `thrust` → the droplet's IP to `hayesmaker64.com` (DigitalOcean:
Networking → Domains, or wherever that domain's DNS lives). Wait until
`dig +short thrust.hayesmaker64.com` shows the IP.

**2. SSH alias** on your machine, in `~/.ssh/config`:

```
Host thrust-host
    HostName <droplet IP>
    User hayesmaker
```

Node: the editor uses its own Node (24, from `packages/level-editor/.node-version`);
`update.sh` installs it with fnm (or nvm) and points pm2 at it for this app only, so
c64cade keeps its Node. `ssh thrust-host node -v` saying "command not found" is normal:
fnm only loads in a login shell, and `update.sh` loads it itself.

**3. Merge and push** this branch to master on GitHub.

**4. Clone on the server** (`ssh thrust-host`):

```
sudo mkdir -p /srv/thrust-c64 && sudo chown $USER: /srv/thrust-c64
git clone https://github.com/hayesmaker/thrust-c64.git /srv/thrust-c64
cd /srv/thrust-c64
```

**5. Provision** (still on the server):

```
sudo ./deploy/provision.sh
```

It downloads KickAssembler from theweb.dk and checks it is 5.25 (the version you build
with). If theweb.dk has moved on to a newer version, it stops and tells you to upload
yours: on your machine `scp /opt/KickAss.jar thrust-host:/tmp/`, then on the server
`sudo ./deploy/provision.sh /tmp/KickAss.jar`. It also checks that KickAssembler runs in
the sandbox (see "Sandbox fails" below if not) and installs the nginx site.

**6. First build and start** (on the server, as your normal user, the one that runs pm2):

```
./deploy/update.sh master
```

Then http://thrust.hayesmaker64.com should show the editor. If pm2 isn't set to start at
boot already (it is if c64cade survives reboots), run `pm2 startup` once and do what it prints.

**7. HTTPS:**

```
sudo certbot --nginx -d thrust.hayesmaker64.com
```

**8. Check that Build & play works** at https://thrust.hayesmaker64.com.

## Releases

1. Add a `## 0.2.0` section to `packages/level-editor/CHANGELOG.md` (leaving it uncommitted is fine).
2. `./deploy/release.sh 0.2.0`: runs the tests, sets the version, commits, tags `v0.2.0`.
3. `git push origin master v0.2.0`
4. `./deploy/deploy.sh v0.2.0`
5. Optional: a GitHub release with the mod attached:
   `gh release create v0.2.0 packages/thrusty-levels/build/thrusty-levels.prg --notes-from-tag`

Roll back: `./deploy/deploy.sh v0.1.0`. To try a branch on the live site:
`./deploy/deploy.sh some-branch` (it must be pushed).

`update.sh` builds into `dist.new` and runs every test (KickAssembler through the
sandbox) before it touches anything live. If a step fails, it restores the checkout and
the running version stays up. Edit nothing in `/srv/thrust-c64` by hand: it refuses to
deploy over local changes.

## Changing the nginx site later

`provision.sh` installs the site only once, because certbot edits the installed copy at
`/etc/nginx/sites-available/thrust.hayesmaker64.com`. After changing
`deploy/nginx/…conf`, copy the change into that file by hand, then
`sudo nginx -t && sudo systemctl reload nginx`.

## Limits (ecosystem.config.cjs)

| Variable | Value | |
|---|---|---|
| `BUILD_TIMEOUT_MS` | 30000 | a build is stopped after this (normal builds take about a second) |
| `BUILD_MAX_QUEUE` | 8 | builds run one at a time; more than this waiting get "busy" (503) |
| nginx `limit_req` | 10/min, burst 5 | builds per IP address; more get 429 |
| Java heap | 256 MB | `-Xmx` in `kickass-sandbox.sh` |

After changing `ecosystem.config.cjs`, deploy again (`--update-env` applies it).

## Why the sandbox

Anyone can post assembler source to `/api/build`. KickAssembler's script language can
read files (`LoadBinary`, `.import`) and write them (`.file`, `.segmentout`), and
`.print` output comes back in the build log. Without the sandbox a visitor could read or
write anything your user can. `kickass-sandbox.sh` runs Java with only `/usr`, the jar and
that build's folder visible, with no network and an empty environment. If bubblewrap
doesn't work, builds fail rather than run without the sandbox.

To see it working, Build & play in the editor with this line added to a level file:
`.print LoadBinary("/home/hayesmaker/.bashrc").getSize()`. The build log should say the
file can't be found, not print a number.

### Sandbox fails

Ubuntu 23.10 and later can stop unprivileged programs from using user namespaces, which
bubblewrap needs. Check with `sysctl kernel.apparmor_restrict_unprivileged_userns`. If it
is 1 and `provision.sh`'s sandbox check fails, allow bwrap with an AppArmor profile:

```
sudo tee /etc/apparmor.d/bwrap >/dev/null <<'P'
abi <abi/4.0>,
include <tunables/global>
profile bwrap /usr/bin/bwrap flags=(unconfined) {
  userns,
  include if exists <local/bwrap>
}
P
sudo apparmor_parser -r /etc/apparmor.d/bwrap
sudo ./deploy/provision.sh
```

## Troubleshooting

* `pm2 logs thrust-level-editor`: server output
* `pm2 describe thrust-level-editor`: the env it runs with
* `curl -s http://127.0.0.1:5180/api/source | head -c 200`: the API answers, bypassing nginx
* `sudo tail /var/log/nginx/error.log`
* Build files of the last 12 builds: `/tmp/thrust-level-editor/builds/`
