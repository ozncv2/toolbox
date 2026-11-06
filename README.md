# toolbox

A project-independent Ubuntu 26.04 base image for `linux/amd64`, with multiple Python
versions, Node, Kubernetes and OpenShift tools, database and network clients and a browser
terminal. Use it as the `FROM` of your own images and add only what your project needs.

- Runs as a non-root user, and as any arbitrary UID on a read-only root filesystem with no
  capabilities, which is how OpenShift runs containers.
- Every download is pinned by version and checksum. Tools whose release binaries embed
  vulnerable Go versions or modules are rebuilt from pinned source commits.
- Each release must pass a gate that rejects critical vulnerabilities (see [Security](#security)).

```bash
docker run --rm -it smtoznc/toolbox:latest
```

## What's inside

| Area | Tools |
|---|---|
| Python | 3.14 (default), 3.13, 3.12, 3.11, `pip`, `uv` |
| JavaScript | Node 26 LTS, `npm` |
| Kubernetes | `oc` 4.16, `kubectl`, `helm`, `kustomize`, `k9s`, `stern`, `kubectx`, `kubens`, `argocd`, `kubeconform` |
| Containers | `skopeo`, `crane`, `oras`, `cosign`, `dive` |
| Databases | `psql`, `pg_dump`, `mysql`, `mysqldump`, `valkey-cli`, `mongosh`, MongoDB database tools, `kcat`, `sqlite3`, `duckdb` |
| Data | `jq`, `yq`, `mlr`, `xmlstarlet`, `rclone` |
| Network | `curl`, `wget`, `dig`, `ip`, `traceroute`, `mtr`, `socat`, `nc`, `grpcurl`, `websocat`, `xh` |
| Shell | `bash`, `zsh`, `tmux`, `nano`, `vim` (tiny), `fzf`, `rg`, `fd`, `bat`, `htop`, `ncdu`, `tree`, `rsync`, `parallel`, `less` |
| Other | `git`, `git-lfs`, `gh`, `openssl`, `zip`, `unzip`, `xz`, `zstd`, `file`, `envsubst` |
| Browser terminal | xterm.js 6 with fit, search, web links and Unicode 11 addons, Terminado |

`toolbox-doctor` runs every tool and reports failures. Exact versions are in
`/opt/toolbox/share/manifest.json`.

There is no C compiler or kernel headers: `linux-libc-dev` reports unpatched critical kernel
CVEs. If you need to compile native code, do it in a builder stage of your own image.

## Building on it

```dockerfile
FROM smtoznc/toolbox:<version>
USER root
COPY certs/ /tmp/certs/
RUN toolbox-add-ca /tmp/certs/*.crt && rm -rf /tmp/certs
RUN toolbox-python use 3.12
COPY requirements.txt /tmp/requirements.txt
RUN pip install -r /tmp/requirements.txt
COPY app/ /opt/app/
USER 1001:0
CMD ["python", "/opt/app/main.py"]
```

Pin images by version or digest. Keep the entrypoint when you can: it prepares HOME, the user
name and extra certificates for arbitrary UIDs, then runs your command under `dumb-init`.

| Command | Purpose |
|---|---|
| `toolbox-python list`, `current`, `use <version>` | Show or select the Python behind `python`, `python3` and `pip`. `use` needs root. |
| `toolbox-add-ca <file>...` | Trust extra CA certificates for the system, Python, pip, uv and Node. Needs root. |
| `toolbox-terminal` | Start the browser terminal. |
| `toolbox-doctor [-v]` | Check that every tool works for the current user. |

| Location | Purpose |
|---|---|
| `/opt/toolbox/entrypoint.d/*.sh` | Sourced by the entrypoint, in order. Add your own startup steps here. |
| `/etc/toolbox/ca.d/*.crt` | Certificates mounted at run time are added to the trust bundle. |
| `/workspace` | Default working directory, writable by arbitrary UIDs in group 0. |

## Browser terminal

Each WebSocket connection gets its own shell and a private temporary HOME, removed when the
connection closes.

**The terminal has no authentication.** Anyone who reaches it gets a shell with the container's
permissions. Keep the default localhost bind and put an authenticating reverse proxy in front.

| Variable | Default | Purpose |
|---|---|---|
| `TOOLBOX_TERMINAL_BIND` | `127.0.0.1` | Listen address |
| `TOOLBOX_TERMINAL_PORT` | `8888` | Listen port |
| `TOOLBOX_TERMINAL_PREFIX` | none | URL prefix, for example `/console` |
| `TOOLBOX_TERMINAL_TITLE` | `Toolbox` | Page title |
| `TOOLBOX_TERMINAL_SHELL` | `/bin/bash` | Shell to start |
| `TOOLBOX_TERMINAL_MAX_SESSIONS` | `16` | Concurrent sessions |
| `TOOLBOX_TERMINAL_IDLE_SECONDS` | `0` | Close sessions without input for this long; `0` disables it |
| `TOOLBOX_TERMINAL_EPHEMERAL_HOME` | `true` | Give each session its own temporary HOME |
| `TOOLBOX_ENV_LABEL` | none | Environment label in the header and prompt |
| `TOOLBOX_ENV_TONE` | `neutral` | Label color: `neutral`, `warning` or `danger` |

Liveness and readiness probes can use `/healthz`.

## Building

```bash
docker buildx create --name toolbox --driver docker-container --bootstrap
```

```bash
VERSION=dev docker buildx bake --builder toolbox default
```

```bash
tests/smoke.sh smtoznc/toolbox:dev
```

```bash
scripts/scan.sh smtoznc/toolbox:dev
```

Pass `--set '*.args.TOOLBOX_EXCLUDE=k9s,duckdb'` to leave out tools by their name in
`build/tools.lock`, `build/go-tools.lock` or `build/apt-packages.txt`. Do not exclude the base
packages at the top of `build/apt-packages.txt`.

Downloads and Go builds run natively, so only the apt and Python steps are emulated when
building on an arm64 machine. All of these steps have cache mounts.

To publish, run the `build` workflow by hand from the Actions tab, after adding the
`DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` repository secrets. It builds, tests and scans the
image, and pushes `YYYY.MM.DD` and `latest` only if all of that passes. Nothing is built on a
schedule, so rerun it when you want the latest Ubuntu security updates and bump versions in
the lock files when you want newer tools.

## Security

`scripts/scan.sh` scans with Trivy and Grype, and `scripts/cve_gate.py` fails the build when
either one rates a finding CRITICAL or any source scores it CVSS 9.0 or higher, whether or not
a fix exists. Findings that cannot apply to this image are listed with a reason in
`scripts/cve-allowlist.txt`. Passing the gate does not guarantee another scanner agrees, because
they use different data. `mongosh` bundles its own Node runtime, which these scanners do not
inspect.

`oc` here is an unofficial build: OpenShift's 4.16 source, with a newer Go, newer dependencies
and a small patch in `build/patches/oc.sh`. It is not a Red Hat release. Test it against your
own cluster before relying on it.

## License

The files in this repository are under the [Apache License 2.0](LICENSE). The image also contains
third-party software under its own licences: see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
