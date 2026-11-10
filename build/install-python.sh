#!/usr/bin/env bash
set -euo pipefail

all_versions=(3.14.10 3.13.18 3.12.16 3.11.18)
default_minor=3.14

# The other versions can be left out by name (python3.13, ...). The default one stays: it runs the terminal.
versions=()
for version in "${all_versions[@]}"; do
    minor=${version%.*}
    if [[ "$minor" == "$default_minor" || ",${TOOLBOX_EXCLUDE:-}," != *",python$minor,"* ]]; then
        versions+=("$version")
    fi
done

export UV_PYTHON_INSTALL_DIR=/opt/python
uv python install --no-bin "${versions[@]}"

for version in "${versions[@]}"; do
    minor=${version%.*}
    root=/opt/python/cpython-$version-linux-x86_64-gnu
    stdlib=$root/lib/python$minor

    ln -sfn "${root##*/}" "/opt/python/$minor"

    # uv marks its Pythons as externally managed; here they are meant to take pip installs.
    rm -f "$stdlib/EXTERNALLY-MANAGED"

    # Parts of the standard library that a headless image never uses.
    rm -rf "$stdlib/test" "$stdlib/idlelib" "$stdlib/tkinter" "$stdlib/turtledemo" "$stdlib/turtle.py" \
        "$stdlib"/lib-dynload/_tkinter* "$stdlib"/config-*/*.a \
        "$root"/lib/libtcl* "$root"/lib/libtk* "$root"/lib/tcl* "$root"/lib/tk* "$root"/lib/itcl* \
        "$root"/lib/thread* "$root"/bin/idle* "$root"/share

    # Bytecode is kept only for the default Python; toolbox-python compiles the one a project selects.
    if [[ "$minor" != "$default_minor" ]]; then
        find "$root" -type d -name __pycache__ -prune -exec rm -rf {} +
    fi
done

ln -sfn "$default_minor" /opt/python/current

uv venv --python "/opt/python/$default_minor/bin/python3" /opt/toolbox/venv
uv pip install --python /opt/toolbox/venv/bin/python --require-hashes --no-compile \
    --requirement /build/terminal-requirements.txt

# Tornado ships its own test suite, including a private key for its TLS tests. The terminal never
# imports it, and image scanners report every private key they find. Removed here, in the stage that
# produces the venv, so the key never reaches a layer of the final image.
rm -rf "/opt/toolbox/venv/lib/python$default_minor/site-packages/tornado/test"
