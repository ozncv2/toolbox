# toolbox: status and plan

_Last updated 2026-11-09. Describes release `2026.11.06` and the repository at that point._

This file records where the project stands: what has been released, how it is built, what has been
verified and what has not, the known issues, and what comes next. It is written so that anyone,
including a future maintainer starting cold, can pick the work up without the history in someone's head.

Status in one line: **`2026.11.06` is published and passed every local check. It has not yet been scanned
by any scanner other than Trivy and Grype, `oc` has not been used against a live cluster, and the CI
workflow has never run.**

---

## 1. At a glance

| | |
|---|---|
| Image | `docker.io/smtoznc/toolbox` |
| Current release | `2026.11.06`, also tagged `latest` |
| Digest | `sha256:98efe3289fca77f985ce08acba725bbacf14719e8de416e4240a7ebd8f5f1431` |
| Manifest format | Docker v2 schema 2, single platform, gzip layers, no attestations |
| Platform | `linux/amd64` only |
| Size | 930,472,545 bytes compressed (887 MiB, written as "0.87 GB" in the docs) and 2.59 GB on disk |
| Base | `ubuntu:26.04@sha256:6a06111c3b0a8600feadb270aec771dc239bf407b25625f93f44ab00e11f4d3c` |
| User | `1001:0` (`toolbox`); runs as any arbitrary UID in group 0 |
| Entrypoint | `dumb-init -- /opt/toolbox/bin/entrypoint`, default command `/bin/bash`, working directory `/workspace` |
| Source | [github.com/ozncv2/toolbox](https://github.com/ozncv2/toolbox), public, Apache-2.0 |
| Docker Hub page | Overview text is [`docs/DOCKERHUB.md`](DOCKERHUB.md), pasted by hand. Categories: Developer tools, Integration & delivery |
| How `2026.11.06` was built | Locally, on Docker Desktop on Apple Silicon, with a `docker-container` buildx builder named `toolbox`, then pushed with `docker buildx bake release` |
| CI | [`.github/workflows/build.yml`](../.github/workflows/build.yml), manual trigger only. **Never run**, and no repository secrets are set |
| Git tags and GitHub releases | None yet |
| Docker Hub pulls | 85 on 2026-11-09. Docker Hub does not show who pulled; the number includes verification pulls, scanners and mirrors |

---

## 2. What the release contains

The README lists the tools by area. This section records exact versions and where each one comes from.
Inside the image, `/opt/toolbox/share/manifest.json` records the same information, including every
apt package version.

### 2.1 Core runtimes

| Component | Version | Source |
|---|---|---|
| Ubuntu | 26.04 LTS | `ubuntu:26.04`, pinned by digest, `apt-get upgrade` at build time |
| Python (default) | 3.14.10 | python-build-standalone through `uv`, in `/opt/python/cpython-3.14.10-linux-x86_64-gnu`, linked as `/opt/python/current` |
| Python (others) | 3.13.18, 3.12.16, 3.11.18 | Same. Bytecode is stripped from these and compiled by `toolbox-python use` |
| Python 3.15 | Not included | Deliberate decision, see the decisions log |
| uv | 0.13.7 | Release binary |
| Node.js | v26.13.0 | Official tarball; `share/`, changelog and readme removed |
| npm | 12.2.2 | Replaces the npm bundled with Node, which carried a vulnerable dependency |
| Go (build only) | 1.27.3 | `golang:1.27.3`, pinned by digest, used to compile the Go tools; not in the image |

### 2.2 Go tools built from source ([`build/go-tools.lock`](../build/go-tools.lock))

All are cross-compiled from a pinned commit with `CGO_ENABLED=0`, `-trimpath`, `-buildvcs=false` and
stripped symbols. Every one gets two common upgrades: `golang.org/x/net@v0.62.0` and
`golang.org/x/crypto@v0.58.0`.

| Tool | Version | Commit | Extra changes |
|---|---|---|---|
| `oc` | `v4.16.0-secure.2` | `openshift/oc@6f88b584` | go-git v5.19.3, docker v28.5.2+incompatible, buildkit v0.34.2, containerd v1.7.36, containers/storage v1.59.1, containers/image/v5 v5.36.2; replaces runc with v1.2.9 and moby/go-archive with v0.1.0; source patch [`build/patches/oc.sh`](../build/patches/oc.sh). Tags `include_gcs,include_oss,containers_image_openpgp` |
| `kubectl` | 1.29.7 | Symlink to `oc` | `oc` embeds kubectl, so its client version is Kubernetes 1.29.7 |
| `k9s` | v0.51.0 | `558caafe` | helm.sh/helm/v3 v3.22.1 (drops containerd v1), containerd/v2 v2.2.10, brotli v1.2.8 |
| `stern` | v1.35.0 | `37fcd4cf` | none |
| `kubectx`, `kubens` | v0.11.0 | `7605ca50` | none |
| `kustomize` | v5.8.3 | `6e4452f7` | none |
| `kubeconform` | v0.8.0 | `02374e58` | none |
| `crane` | v0.22.1 | `8a72a424` | none |
| `dive` | v0.13.1 | `fe98c8a2` | none |
| `git-lfs` | v3.8.1 | `a662a6db` | none |
| `grpcurl` | v1.9.4 | `cf21d4ac` | none |
| `mlr` (Miller) | v6.22.0 | `1362c2ec` | none |
| `rclone` | v1.75.2 | `be8d6044` | brotli v1.2.8 |
| `skopeo` | v1.24.1 | `77f3d92f` | Tags `containers_image_openpgp,containers_image_docker_daemon_stub,exclude_graphdriver_btrfs` |

**About `oc`.** The separate repository
[ozncv2/openshift-oc-4.16-secure-build](https://github.com/ozncv2/openshift-oc-4.16-secure-build) publishes
`v4.16.0-secure.1`: the same `openshift/oc` commit built with Go 1.24.13 and go-git v5.13.1. That binary
was the original plan, but it failed this project's CVE gate, so toolbox builds the same commit itself
with Go 1.27.3 and the dependency upgrades above and labels the result `v4.16.0-secure.2`. That label
exists only in toolbox; the secure-build repository has not published a `secure.2` release.

### 2.3 Release binaries ([`build/tools.lock`](../build/tools.lock))

Downloaded in parallel and checked against a pinned SHA-256 (or npm SHA-512 integrity) before use.

| Tool | Version |
|---|---|
| `helm` | v4.3.1 |
| `argocd` | v3.6.1 |
| `oras` | v1.3.6 |
| `cosign` | v3.1.4 |
| `websocat` | v1.14.1 (musl) |
| `xh` | v0.26.3 (musl) |
| `yq` | v4.54.2 |
| `duckdb` | v2.0.0 |
| `gh` | v2.103.3 |
| `fzf` | v0.74.5 |
| `mongosh` | 2.14.1 (OpenSSL 3 build) |
| MongoDB database tools | 100.20.1 (Ubuntu 26.04 build): `bsondump`, `mongodump`, `mongoexport`, `mongofiles`, `mongoimport`, `mongorestore`, `mongostat`, `mongotop` |
| rsync | 3.5.2 source tarball, compiled in its own stage (see 3.1) |

### 2.4 Browser terminal

| Component | Version |
|---|---|
| xterm.js | 6.0.0 |
| Addons | fit 0.11.0, search 0.16.0, web-links 0.12.0, unicode11 0.9.0 |
| Terminado | 0.18.1 |
| Tornado | 6.6 |
| ptyprocess | 0.7.0 |

The Python packages live in a private virtual environment, `/opt/toolbox/venv`, installed with
`--require-hashes`, so projects can pin their own versions without affecting the terminal. The xterm.js
files are served from the image, so the terminal needs no CDN or internet access.

### 2.5 Ubuntu packages ([`build/apt-packages.txt`](../build/apt-packages.txt))

Base: `ca-certificates`, `dumb-init`, `libnss-wrapper`, `locales`, `bash-completion`.
General: `curl`, `wget`, `jq`, `git`, `less`, `nano`, `vim-tiny`, `zip`, `unzip`, `xz-utils`, `zstd`,
`openssl`, `procps`, `file`, `gettext-base`.
Shell: `zsh`, `tmux`, `ripgrep`, `fd-find`, `bat`, `htop`, `ncdu`, `tree`, `parallel`.
Network: `bind9-dnsutils`, `iproute2`, `traceroute`, `mtr-tiny`, `socat`, `netcat-openbsd`.
Data: `sqlite3`, `xmlstarlet`.
Database clients: `postgresql-client`, `mysql-client`, `valkey-tools`, `kcat`.

With their dependencies and the base system, the image has 212 Debian packages.
Installed with `--no-recommends`. A dpkg filter keeps documentation, man pages and translations out of
this and every later layer, except copyright files and the English and Turkish locales.
`en_US.UTF-8` and `tr_TR.UTF-8` are generated; the image defaults to `C.UTF-8`.

### 2.6 What toolbox adds ([`rootfs/`](../rootfs))

| Path | What it does |
|---|---|
| `/opt/toolbox/bin/entrypoint` | Finds a writable HOME for arbitrary UIDs, gives the UID a user name through `nss_wrapper`, adds certificates mounted in `/etc/toolbox/ca.d/`, sources `/opt/toolbox/entrypoint.d/*.sh`, then runs the command |
| `/opt/toolbox/bin/toolbox-doctor` | Runs the 90 checks in `/opt/toolbox/share/doctor-checks.tsv`; `-v` prints each result |
| `/opt/toolbox/bin/toolbox-python` | `list`, `current`, `use <version>` (root only, compiles bytecode for the selected version) |
| `/opt/toolbox/bin/toolbox-add-ca` | Validates and trusts extra CA certificates (root only) |
| `/opt/toolbox/bin/toolbox-terminal` | Starts the browser terminal (`/opt/toolbox/terminal/server.py`) |
| `/opt/toolbox/share/bashrc`, `zshrc` | Prompt with the `TOOLBOX_ENV_LABEL`, completions and aliases |
| `/opt/toolbox/share/manifest.json` | Versions of everything, generated at build time |
| `/opt/toolbox/share/licenses/`, `THIRD_PARTY_NOTICES.md` | Licences of bundled software |
| `/etc/containers/policy.json` | Signature policy for `skopeo` and `oc image`: accepts everything (see 6.9) |

`finalize.sh` also links familiar names (`kubectl` to `oc`, `fd`, `bat`, `vim`, `python3.X`), generates bash
completions from the installed binaries, creates the `toolbox` user, makes `/home/toolbox` and
`/workspace` group-writable, removes every setuid and setgid bit, and deletes caches.

---

## 3. How it is built

See the [pipeline diagram](assets/pipeline.svg) for the picture. Builds go through
[`docker-bake.hcl`](../docker-bake.hcl).

### 3.1 Stages ([`Dockerfile`](../Dockerfile))

| Stage | Base | Runs on | What it does |
|---|---|---|---|
| `fetch` | `alpine:3` (pinned) | Build host, natively | [`build/fetch-tools.sh`](../build/fetch-tools.sh): eight parallel downloads, checksum verification, unpacking. Cache mount `toolbox-downloads` |
| `gotools` | `golang:1.27.3` (pinned) | Build host, natively | [`build/build-go-tools.sh`](../build/build-go-tools.sh): clones each commit, applies patches and upgrades, cross-compiles to amd64. Cache mounts for modules and build cache |
| `rsync` | Ubuntu 26.04 | Target | [`build/build-rsync.sh`](../build/build-rsync.sh): installs `gcc`, `make`, `libc6-dev` in this stage only and builds a stripped rsync without optional libraries |
| `system` | Ubuntu 26.04 | Target | [`build/install-apt.sh`](../build/install-apt.sh): dpkg filters, upgrade, packages, locales. apt cache mounts |
| `python` | Ubuntu 26.04 | Target | [`build/install-python.sh`](../build/install-python.sh): four Pythons, removes tests, IDLE, Tk and static libraries, creates the terminal venv |
| `toolbox` | `system` | Target | Copies every stage in with `COPY --link`, adds `rootfs/`, runs [`build/finalize.sh`](../build/finalize.sh) |

On an arm64 build host, `fetch` and `gotools` run natively and only the three Ubuntu stages and the final
stage are emulated.

### 3.2 Bake targets

| Target | Output | Use |
|---|---|---|
| `default` | Loaded into the local Docker daemon as `smtoznc/toolbox:${VERSION}` | Local builds, tests, scans |
| `release` | Pushed as `${VERSION}` and `latest`; gzip level 9, Docker media types, provenance and SBOM attestations disabled | Publishing. The format is chosen so that older registries and scanners can read the image and mirroring keeps the digest |

Build arguments: `TOOLBOX_VERSION` (set from `VERSION`, written to the label, environment and manifest)
and `TOOLBOX_EXCLUDE` (comma-separated names from any lock file or the apt list to leave out; `uv` cannot be
left out). Variable `REPOSITORY` defaults to `smtoznc/toolbox`.

### 3.3 Lock file formats

- **`tools.lock`**: `kind name version checksum url members`. `kind` is `bin` (to `/usr/local/bin`), `web`
  (terminal assets) or `tree` (unpacked whole). `checksum` is `sha256:<hex>` or npm's `sha512-<base64>`.
  `members` lists files to take from the archive as `source[:dest]`, or `-` when the download is the binary itself.
- **`go-tools.lock`**: `kind name version commit repo subdir package bumps tags ldflags`. `version` may be
  `version:binary` when the command name differs (Miller's `mlr`). `bumps` entries are `module@version`
  upgrades or, with `=`, `go.mod` replaces. `{version}` and `{commit}` are substituted in `ldflags`.
  A script at `build/patches/<name>.sh` runs in the source tree before the build.

---

## 4. Verification record

### 4.1 Verified

| What | How | Result |
|---|---|---|
| Build | `docker buildx bake --builder toolbox default` | Passed, 2026-11-06 |
| Tools work as the default user | `toolbox-doctor` | 90 passed, 0 failed |
| Tools work under OpenShift-style restrictions | `toolbox-doctor` with `--user 1000770000:0 --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges` | 90 passed, 0 failed |
| Arbitrary UID gets a user name and writable HOME | `tests/smoke.sh`: `id -un` is `toolbox`, `git config --global` works | Passed |
| Browser terminal | `tests/terminal_smoke.py` over a real WebSocket: page, Content-Security-Policy, static assets, two shells with separate HOMEs, 256 colours, UTF-8 Turkish characters, a third session refused with code 1013, a cross-origin WebSocket refused with 403, HOMEs removed on close | Passed |
| Derived image | `tests/smoke.sh`: `toolbox-add-ca`, `toolbox-python use 3.12`, `pip install` with a compiled extension, `uv venv`, `npm install` | Passed |
| CVE gate | `scripts/scan.sh` with Trivy 0.76.2 and Grype v0.121.2 | Passed: no finding rated critical or scored CVSS 9.0+ except one allowlisted (section 5). 174 Trivy and 439 Grype findings of any severity |
| Published image | Pulled back from Docker Hub, digest compared, doctor (both ways), terminal and derived image rerun | Passed |
| Published image matches the repository | On 2026-11-09, the `rootfs/` layer, `THIRD_PARTY_NOTICES.md` and the tool versions in `manifest.json` were fetched from the registry and compared with commit `45c97a5` | Identical. Later commits change only the README and `docs/` |
| `oc` image commands | `oc image info` and `oc image extract` against `docker.io/library/alpine:3` | Worked. These exercise the upgraded container and Docker libraries |
| Browser terminal by eye | Opened in a real browser, ran `toolbox-python list`, `oc version`, `toolbox-doctor` | Worked; the screenshot is [`assets/terminal.png`](assets/terminal.png) |
| Docs | README on GitHub and the Docker Hub overview checked after publishing | Images and tables render |

### 4.2 Not verified yet

| What | Why it matters |
|---|---|
| **Prisma Cloud (Twistlock) or any scanner other than Trivy and Grype** | Each scanner uses its own vulnerability data. A clean Trivy and Grype result does not guarantee a clean result elsewhere. See 7.1 |
| **`oc` and `kubectl` against a live OpenShift or Kubernetes cluster** | `oc` is an unofficial build with upgraded dependencies and a source patch. Only the image commands have been exercised |
| **A real OpenShift pod** | The restrictions were simulated with Docker flags. A real `restricted-v2` SCC, a random UID from the namespace range and real volume permissions have not been tried |
| **The browser terminal behind a real authenticating proxy** | WebSocket upgrade, URL prefix, proxy timeouts and the origin check (6.10) are untested outside localhost |
| **The GitHub Actions workflow** | Never run. Runner disk space, the 90-minute timeout and the build time without a warm cache are unknown |
| The `oc` source patch path for device files | `unix.Mknod` in `archive_unix.go` only runs when an image layer contains device nodes, which normal images do not |

---

## 5. Security posture

- **Gate rule.** [`scripts/cve_gate.py`](../scripts/cve_gate.py) fails when Trivy or Grype rates a finding
  CRITICAL, or any CVSS v3 or v4 source scores it 9.0 or higher, whether or not a fix exists. Findings from
  both scanners are merged by ID, package, version and path.
- **Allowlist.** [`scripts/cve-allowlist.txt`](../scripts/cve-allowlist.txt) needs a reason for every entry and
  is only for findings that cannot apply. It holds one entry: `CVE-2026-118131` in `gpgv`, which only
  affects GnuPG for Windows. `apt` depends on `gpgv`, so every `ubuntu:26.04` image reports it.
- **Scanners run without the Docker socket.** `scan.sh` exports the image to a tar file and mounts only that,
  plus two named cache volumes (`toolbox-trivy-cache`, `toolbox-grype-cache`).
- **Results are a snapshot.** The numbers are from 2026-11-06. The digest does not change, but scanner
  databases do, so a rescan can fail later without any change to the image.
- **Blind spots.** Trivy and Grype do not inspect the Node runtime embedded in the `mongosh` executable.
  Their view into the Rust binaries (`websocat`, `xh`) and the DuckDB binary may also be limited.
  Lower-severity findings remain.
- **Hardening in the image.** No compiler toolchain, no setuid or setgid files, a non-root default user,
  and everything pinned by checksum or commit.
- **No authentication in the browser terminal**, by design. It binds to `127.0.0.1` by default and must sit
  behind an authenticating proxy.
- **Not published: signatures, SBOM, provenance.** Attestations are disabled for compatibility (3.2). A
  cosign signature is stored as a separate tag and would not change the digest (backlog, 7.3).

---

## 6. Known issues and technical debt

1. **CI publishes a different build from the one it tested.** The workflow builds and tests with
   `VERSION=ci`, then runs `bake release` with `VERSION=<date>`. The version is in an `ENV` line, so the
   `finalize.sh` layer is rebuilt for the release and the pushed digest was never itself tested or scanned.
   Fix: compute the version once at the start, build, test and scan with it, then publish with the same
   version so every layer comes from cache. This is how `2026.11.06` was released locally.
2. **A second release on the same day overwrites the dated tag.** The version is `date -u +%Y.%m.%d`. Fix:
   fail when the tag already exists, or add a counter such as `2026.11.06.2`.
3. **CI is unproven.** Disk usage on `ubuntu-latest`, the 90-minute timeout and the time to build 14 Go
   tools without a warm cache are unknown. There is no cache between runs, and the scan reports are not
   uploaded as workflow artifacts.
4. **Stale comment.** The [`Dockerfile`](../Dockerfile) still says amd64 is "the only platform oc is
   published for". `oc` is now built from source; amd64 is the only platform because of the items in 6.5.
5. **amd64 is hard-coded** in the `tools.lock` URLs, `GOARCH=amd64` in `build-go-tools.sh`, the
   `linux-x86_64-gnu` Python path in `install-python.sh`, the `x86_64-linux-gnu` `nss_wrapper` path in
   `entrypoint`, and `platforms` in `docker-bake.hcl`.
6. **`kubectl` is Kubernetes 1.29.7**, because it is the copy embedded in `oc` 4.16. Upstream supports a
   client one minor version away from the server, so this is outside the supported skew for current
   clusters, even though most commands still work.
7. **Hand-maintained numbers in the docs.** Each release has to update them by hand (checklist in 9.6):
   - README and `docs/DOCKERHUB.md`: the tag in `FROM` examples, tags table and digest, size badge, scan table and date, "Go 1.27.3", "14 Go tools".
   - `docs/assets/layers.svg`: layer sizes, total size, Go version.
   - `docs/assets/pipeline.svg`: "14 tools", "90 self-checks".
   - `docs/assets/banner.svg`: the terminal window is an illustration, not a screenshot. Its output (`Python 3.14.10`, `Client Version: v4.16.0-secure.2`, `90 passed`) comes from `2026.11.06`, and the doctor line leaves out the real `(uid=... home=...)` suffix.
   - Every PNG has to be rendered again from its SVG (9.7).
8. **The Docker Hub overview is updated by hand**: paste `docs/DOCKERHUB.md` into the repository's overview
   on Docker Hub. The short description has a 100-character limit.
9. **`/etc/containers/policy.json` accepts any image without signature checks.** This keeps `skopeo` and
   `oc image` working out of the box, but derived images that need signature verification should replace it.
10. **The browser terminal's origin check depends on the `Host` header.** The server uses Tornado's default
    `check_origin`, which rejects a WebSocket when the `Origin` host differs from the `Host` header. A proxy
    that rewrites `Host` will cause 403 errors; nginx, for example, needs `proxy_set_header Host $host`.
    Not tested behind a proxy yet (4.2).
11. **`v4.16.0-secure.2` exists only here.** The secure-build repository still publishes `secure.1`, which
    fails this gate. Decide whether that repository should publish the new recipe too, so there is one
    source of truth for the `oc` build.
12. **No `SECURITY.md`, `CONTRIBUTING.md` or `CHANGELOG.md`**, and no git tag or GitHub release for `2026.11.06`.
13. **README badges are static.** Live shields.io badges that read Docker Hub were rate-limited, so the
    README uses static badges, which must be edited by hand (6.7).

---

## 7. To-do

Ordered by priority. Nothing here runs on a schedule; builds stay manual by decision.

### 7.1 Now: before relying on the image downstream

- [ ] **Mirror the image by digest into the internal registry** (commands in section 8) and confirm the digest is unchanged.
- [ ] **Scan it with Prisma Cloud (Twistlock)** and record the results here.
  - [ ] If it reports a critical finding, find which layer and tool it belongs to and use the playbook in 9.5.
  - [ ] Pay attention to `mongosh`: Trivy and Grype do not see its embedded Node. If it is flagged, either leave it out with `TOOLBOX_EXCLUDE=mongosh` or install `mongosh` from npm so that it runs on the image's own Node.
  - [ ] Pay attention to the release binaries in 2.3: they are built with their projects' own Go versions, which can pick up new critical Go findings over time. A binary that is flagged moves to `go-tools.lock` and is built from source.
- [ ] **Test `oc` against a live OpenShift cluster** with a test account, from the image:
  - [ ] `oc login` with a token, including a cluster CA added through `toolbox-add-ca` or `/etc/toolbox/ca.d/`
  - [ ] `oc whoami`, `oc version` (client and server), `oc get`, `oc describe`, `oc apply --dry-run=server`
  - [ ] `oc logs -f`, `oc exec -it`, `oc rsh`, `oc port-forward`
  - [ ] `oc cp` and `oc rsync` (uses the image's rsync 3.5.2)
  - [ ] `oc image info` and `oc image mirror` against the internal registry with authentication
  - [ ] `oc start-build --from-dir` if builds are in use (exercises the archive code)
  - [ ] The same through `kubectl`, plus `helm list`, `k9s`, `stern`
- [ ] **Run the image as a real OpenShift pod** under the default `restricted-v2` SCC: `toolbox-doctor`, a shell through `oc rsh`, and the browser terminal behind a route or ingress with an authenticating proxy (check the WebSocket upgrade, `TOOLBOX_TERMINAL_PREFIX`, the `Host` header from 6.10 and proxy idle timeouts).
- [ ] **Run the CI workflow once** from the Actions tab. Without secrets it only builds, tests and scans, which proves CI without publishing. Then add `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` (a Docker Hub personal access token with read and write scope) when CI should publish.

### 7.2 Next: release hygiene

- [ ] Fix 6.1: publish the exact build that was tested.
- [ ] Fix 6.2: refuse to overwrite an existing dated tag.
- [ ] Upload `reports/trivy.json` and `reports/grype.json` as workflow artifacts.
- [ ] Fix the stale `Dockerfile` comment (6.4).
- [ ] Create git tag `2026.11.06` on `45c97a5` ("Add toolbox base image"), the commit the release matches (4.1), and a GitHub release with the digest.
- [ ] Add `SECURITY.md` (how to report a vulnerability) and `CHANGELOG.md`.

### 7.3 Backlog: ideas to decide on before doing

- [ ] A standalone, current `kubectl` built from source next to `oc` (6.6).
- [ ] `linux/arm64` images, after removing the hard-coded amd64 parts (6.5) and adding arm64 checksums.
- [ ] Keyless cosign signatures for releases from CI.
- [ ] Sync the Docker Hub overview from `docs/DOCKERHUB.md` in CI.
- [ ] A manual, scan-only workflow that rescans the published digest without rebuilding.
- [ ] Publish the `secure.2` recipe in the secure-build repository (6.11).

---

## 8. Using it downstream: internal registry, organisation layer, project layer

The image is meant to be the first `FROM` line, with an organisation layer and a project layer on top.

**1. Mirror by digest.** The release format keeps the digest when copied:

```bash
skopeo copy --preserve-digests \
  docker://docker.io/smtoznc/toolbox@sha256:98efe3289fca77f985ce08acba725bbacf14719e8de416e4240a7ebd8f5f1431 \
  docker://<registry>/<path>/toolbox:2026.11.06
```

```bash
skopeo inspect --format '{{.Digest}}' docker://<registry>/<path>/toolbox:2026.11.06
```

`crane copy` and `oc image mirror` work too.

**2. Scan the mirrored image** with the registry's scanner before anything is built on it (7.1).

**3. Organisation layer.** Everything specific to the organisation, and nothing about a single project:

```dockerfile
FROM <registry>/<path>/toolbox@sha256:98efe3289fca77f985ce08acba725bbacf14719e8de416e4240a7ebd8f5f1431

USER root
COPY certs/ /tmp/certs/
RUN toolbox-add-ca /tmp/certs/*.crt && rm -rf /tmp/certs

# Package mirrors for pip, uv and npm.
ENV PIP_INDEX_URL=https://<mirror>/pypi/simple \
    UV_DEFAULT_INDEX=https://<mirror>/pypi/simple \
    NPM_CONFIG_REGISTRY=https://<mirror>/npm/

# Optional startup steps, sourced by the entrypoint in order.
COPY entrypoint.d/ /opt/toolbox/entrypoint.d/

USER 1001:0
```

Removing a tool with `rm` in a derived image hides it from scanners that read the final filesystem, but the
bytes stay in the lower layer. To really drop tools, rebuild toolbox with `TOOLBOX_EXCLUDE`.

**4. Project layer.** `FROM` the organisation image, then `toolbox-python use <version>` if needed, the
project's dependencies and its code. Keep the entrypoint so that arbitrary UIDs keep working.

**5. Scan the final image as well.** Project dependencies bring their own findings.

---

## 9. Procedures

### 9.1 Prerequisites

- Docker with buildx. Docker Desktop on macOS works. Check free disk space first: the build caches, the
  image, the tar exported for scanning and both scanner databases add up, and the Docker VM disk filled up
  once during this work.
- `gh` for repository work. `python3` for the CVE gate.

### 9.2 One-time setup

```bash
docker buildx create --name toolbox --driver docker-container --bootstrap
```

This does not change the default builder; pass `--builder toolbox` to each build. Check cache usage with
`docker buildx du --builder toolbox` and reclaim it with `docker buildx prune --builder toolbox`.

### 9.3 Build, test and scan

```bash
VERSION=dev docker buildx bake --builder toolbox default
```

```bash
tests/smoke.sh smtoznc/toolbox:dev
```

```bash
scripts/scan.sh smtoznc/toolbox:dev
```

Reports land in `reports/`, which git ignores.

### 9.4 Updating a pinned dependency

- **Release binary or npm package:** change the version and URL in `tools.lock`, then the checksum:

  ```bash
  curl -fsSL <url> | shasum -a 256
  ```

  ```bash
  curl -fsSL https://registry.npmjs.org/@xterm/xterm/6.0.0 | jq -r .dist.integrity
  ```

- **Go tool:** change the version and commit in `go-tools.lock`. Find the commit behind a tag with the
  command below. For an annotated tag, the line ending in `^{}` is the commit.

  ```bash
  git ls-remote https://github.com/derailed/k9s.git 'refs/tags/v0.51.0*'
  ```

  Then rebuild and recheck whether each entry in `bumps` is still needed. Remove it once upstream catches up.
- **Base images:** update the digests in the `Dockerfile` from the `Digest:` line of:

  ```bash
  docker buildx imagetools inspect ubuntu:26.04
  ```

  Do the same for `alpine:3` and `golang:<version>`. A new Go version also changes the text in 6.7.
- **Python patch releases:** change `versions` in `build/install-python.sh`. `uv python list --all-versions`
  shows what the pinned `uv` can install. Updating `uv` itself may be needed for new Python releases.
- **apt packages:** nothing is pinned. Rebuilding picks up the latest Ubuntu security updates.

**Lessons from the `oc` upgrade, to check first when it breaks:**

- Upgrading `containers/image` pulls in a newer `docker/docker`, which moved `AuthConfig` and removed
  `pkg/system` mknod helpers. [`build/patches/oc.sh`](../build/patches/oc.sh) rewrites those two call sites.
- Newer `runc` removed packages that `oc` imports, so runc is held at v1.2.9 with a `replace`.
  `moby/go-archive` is held at v0.1.0 for an API mismatch.
- `k9s` got rid of containerd v1 only after the Helm v3.22.1 upgrade.
- `dive`'s main package is `.`, not `./cmd/dive`.
- `skopeo` removed the `containers_image_storage_stub` tag, so the tags must match what its build supports.
- Without `-buildvcs=false`, binaries record a `v0.0.0-...+dirty` pseudo-version that scanners mistake for
  an old release.
- rsync needs `--disable-idn` and the other `--disable-*` flags in `build-rsync.sh` to build without extra libraries.

### 9.5 When the CVE gate fails

Work through these in order, and rebuild and rescan after each change:

1. **Ubuntu package with a fix:** rebuild; `install-apt.sh` runs `apt-get upgrade`.
2. **Ubuntu package without a fix:** swap it for an alternative (as with `mysql-client` for MariaDB's
   client), compile a current release in its own stage (as with rsync), or remove what pulls it in (as with
   `build-essential` and `linux-libc-dev`).
3. **Go binary from a release:** update it, or move it to `go-tools.lock` and build it from source with
   current Go.
4. **Go binary built from source:** add a `bumps` entry for the vulnerable module, then a `replace` or a
   patch if the upgrade breaks the build.
5. **Node or npm package:** update Node or npm in `tools.lock`.
6. **Python package in the terminal venv:** update `build/terminal-requirements.txt` with new hashes.
7. **The finding cannot apply to this image:** add it to `scripts/cve-allowlist.txt` with a specific reason.
   Never allowlist a finding only because no fix exists.
8. **The tool is not worth it:** remove it from the lock file and the docs.

### 9.6 Release checklist

1. Update lock files and base digests as needed (9.4).
2. Pick the version: `YYYY.MM.DD`, the UTC date.
3. Build: `VERSION=<version> docker buildx bake --builder toolbox default`
4. Test: `tests/smoke.sh smtoznc/toolbox:<version>`
5. Scan: `scripts/scan.sh smtoznc/toolbox:<version>`. Note both totals and the critical count.
6. Publish with the same version, so every layer comes from cache: `docker login`, then
   `VERSION=<version> docker buildx bake --builder toolbox release`.
   Pushing from a home connection was slow and erratic once; publishing from CI avoids that.
7. Verify the published image: `docker pull`, compare the digest with the push output, run
   `toolbox-doctor` both ways and start the terminal.
8. Update the docs (6.7): `FROM` tags, tags table and digest, badges, scan table and date, layer sizes
   from `docker history`, and render the PNGs again (9.7).
9. Update this file: release, digest, size, verification record.
10. Commit and push, paste `docs/DOCKERHUB.md` into the Docker Hub overview, and create the git tag and
    GitHub release.

To release from CI instead, run the `build` workflow by hand once 6.1 and 6.2 are fixed and the secrets are set.

### 9.7 Rendering the diagrams

The SVGs in `docs/assets/` are hand-written. The README uses the SVGs directly. Docker Hub does not
render SVG, so `docs/DOCKERHUB.md` uses PNG copies through `raw.githubusercontent.com` URLs. After editing an
SVG, render the PNGs again at twice the size, with the fonts the SVGs ask for:

```bash
cd docs/assets && docker run --rm -v "$PWD:/a" alpine:3 sh -c 'apk add --no-cache rsvg-convert font-inter font-jetbrains-mono ttf-dejavu >/dev/null && cd /a && for f in banner layers pipeline terminal-flow; do rsvg-convert --zoom=2 "$f.svg" -o "$f.png"; done'
```

Open each PNG and check spacing and arrows before committing. `terminal.png` is a real screenshot of the
browser terminal; take a new one when the terminal changes.

---

## 10. Decisions log

| Decision | Reason |
|---|---|
| Independent of any organisation, published under personal accounts (GitHub `ozncv2`, Docker Hub `smtoznc`) | Usable by anyone; organisations add their own layer on top (section 8) |
| Ubuntu 26.04 LTS | The newest LTS, with current packages and fewer findings than older releases |
| Python 3.14 by default, with 3.13, 3.12 and 3.11 | Current versions for new work; older ones for projects with pinned dependencies |
| No Python 3.15 | Left out by choice: many pinned dependencies do not ship wheels for it yet |
| One rich image, no "max" tier | One image to maintain and mirror; anything heavier belongs in a project layer |
| Builds start by hand only, never on a schedule | Each release is a deliberate act; rebuild when security updates or new tools are wanted |
| CVE gate: CRITICAL from any scanner, or CVSS 9.0+ from any source, fixed or not | The strictest reading of two scanners, aimed at downstream scanners that block on critical findings |
| Rebuild Go tools from source instead of shipping release binaries | Release binaries embed older Go versions and dependencies that failed the gate |
| Build `oc` 4.16 from source with upgraded dependencies | The `secure.1` binary still failed the gate |
| rsync from source, `mysql-client` instead of MariaDB, no `build-essential`, `vim-tiny` | Each removed unpatched critical findings |
| npm upgraded past the bundled version | The bundled npm carried a vulnerable dependency |
| `linux/amd64` only | The first target environments are amd64; arm64 is in the backlog |
| gzip, Docker media types, no attestations | Readable by older registries and scanners, and digest-preserving when mirrored |
| Browser terminal without built-in authentication, bound to localhost | Authentication belongs in the proxy that each deployment already has |
| Diagrams as hand-written SVG with rendered PNGs | Text-based, reviewable in diffs, easy to update; Docker Hub needs PNG |
| Static README badges | Live Docker badges from shields.io were rate-limited |

---

## 11. Repository map

```text
Dockerfile                    multi-stage build (section 3.1)
docker-bake.hcl               default and release targets (3.2)
build/
  tools.lock                  release binaries, Node, npm, rsync source, xterm.js, pinned by checksum
  go-tools.lock               Go tools built from source, pinned by commit
  apt-packages.txt            Ubuntu packages
  terminal-requirements.txt   browser terminal Python packages, pinned by hash
  fetch-tools.sh              download, verify, unpack
  build-go-tools.sh           cross-compile Go tools
  patches/oc.sh               oc source patch for the docker/docker v28 API
  build-rsync.sh              compile rsync
  install-apt.sh              apt with docs and translations filtered out
  install-python.sh           Pythons and the terminal venv
  finalize.sh                 links, completions, user, permissions, cleanup
  write-manifest.py           /opt/toolbox/share/manifest.json
rootfs/                       files copied into the image as they are (2.6)
scripts/
  scan.sh                     Trivy and Grype on an exported tar
  cve_gate.py                 the gate rule
  cve-allowlist.txt           findings that cannot apply, with reasons
tests/
  smoke.sh                    restricted runs, terminal, derived image
  terminal_smoke.py           WebSocket test, run inside the container
.github/workflows/build.yml   manual build, test, scan and publish
docs/
  DOCKERHUB.md                Docker Hub overview text
  PLAN.md                     this file
  assets/                     SVG diagrams, rendered PNGs, terminal screenshot
README.md, THIRD_PARTY_NOTICES.md, LICENSE
```
