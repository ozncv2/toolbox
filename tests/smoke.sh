#!/usr/bin/env bash
# Exercises an image the way it is used: as an arbitrary UID on a read-only root
# filesystem with no capabilities, as a browser terminal, and as a base for another image.
# Usage: tests/smoke.sh <image>
set -euo pipefail

image=$1
root=$(cd "$(dirname "$0")/.." && pwd)
restricted=(--user 1000770000:0 --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges)
container=toolbox-smoke-$$
derived=toolbox-smoke-derived-$$

cleanup() {
    docker rm -f "$container" >/dev/null 2>&1 || true
    docker image rm -f "$derived" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "== doctor as the default user"
docker run --rm "$image" toolbox-doctor

echo "== doctor as an arbitrary UID, read-only, no capabilities"
docker run --rm "${restricted[@]}" "$image" toolbox-doctor

echo "== user name and HOME for an arbitrary UID"
docker run --rm "${restricted[@]}" "$image" bash -c '
    test "$(id -un)" = toolbox
    test -w "$HOME"
    git config --global user.name test
    git config --global user.name >/dev/null'

echo "== browser terminal"
docker run -d --name "$container" "${restricted[@]}" \
    -e TOOLBOX_TERMINAL_PREFIX=/console \
    -e TOOLBOX_TERMINAL_MAX_SESSIONS=2 \
    -e TOOLBOX_ENV_LABEL=SMOKE \
    "$image" toolbox-terminal >/dev/null
docker exec -i "$container" /opt/toolbox/venv/bin/python - <"$root/tests/terminal_smoke.py"
docker rm -f "$container" >/dev/null

echo "== derived image: Python selection, pip, uv, npm, extra CA"
docker build --quiet --platform linux/amd64 -t "$derived" - >/dev/null <<EOF
FROM $image
USER root
RUN openssl req -x509 -newkey rsa:2048 -nodes -subj /CN=toolbox-smoke-ca -days 1 \
      -keyout /tmp/key.pem -out /tmp/toolbox-smoke-ca.crt \
    && toolbox-add-ca /tmp/toolbox-smoke-ca.crt \
    && rm /tmp/key.pem /tmp/toolbox-smoke-ca.crt
RUN toolbox-python use 3.12
RUN pip install six markupsafe
RUN uv venv /tmp/uv-venv && uv pip install --python /tmp/uv-venv/bin/python six && rm -rf /tmp/uv-venv
RUN cd /tmp && npm install --no-audit --no-fund --silent left-pad && rm -rf /tmp/node_modules /tmp/package*.json
USER 1001:0
EOF
docker run --rm "$derived" bash -c '
    python --version | grep -q "^Python 3\.12\."
    python -c "import six, markupsafe._speedups"
    grep -qs . /usr/local/share/ca-certificates/toolbox-smoke-ca.crt
    test -e /etc/ssl/certs/toolbox-smoke-ca.pem'

echo "smoke tests passed"
