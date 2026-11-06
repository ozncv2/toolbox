#!/usr/bin/env bash
# Downloads, verifies and unpacks everything listed in tools.lock, in parallel.
# Usage: fetch-tools.sh <lockfile> <cache-dir> <output-dir>
set -euo pipefail

lock=$1
export CACHE=$2 OUT=$3
mkdir -p "$CACHE" "$OUT/bin" "$OUT/web" "$OUT/node" "$OUT/rsync-src" "$OUT/licenses"

verify() {
    local file=$1 checksum=$2 actual expected
    case "$checksum" in
        sha256:*)
            expected=${checksum#sha256:}
            actual=$(sha256sum "$file" | cut -d' ' -f1)
            ;;
        sha512-*)
            expected=$(printf '%s' "${checksum#sha512-}" | base64 -d | od -An -tx1 | tr -d ' \n')
            actual=$(sha512sum "$file" | cut -d' ' -f1)
            ;;
        *)
            echo "unknown checksum format: $checksum" >&2
            return 1
            ;;
    esac
    [[ "$actual" == "$expected" ]]
}

unpack() {
    local archive=$1 url=$2 dest=$3
    case "$url" in
        *.tar.gz | *.tgz) tar -xzf "$archive" --no-same-owner -C "$dest" ;;
        *.tar.xz) tar -xJf "$archive" --no-same-owner -C "$dest" ;;
        *.zip) unzip -q "$archive" -d "$dest" ;;
        *)
            echo "unsupported archive: $url" >&2
            return 1
            ;;
    esac
}

fetch_one() {
    local kind=$1 name=$2 version=$3 checksum=$4 url=$5 members=$6
    local archive="$CACHE/$name-$version-${url##*/}"

    if [[ ! -f "$archive" ]] || ! verify "$archive" "$checksum"; then
        curl --fail --silent --show-error --location --retry 3 --output "$archive.tmp.$$" "$url"
        mv "$archive.tmp.$$" "$archive"
    fi
    if ! verify "$archive" "$checksum"; then
        rm -f "$archive"
        echo "checksum mismatch: $name $version" >&2
        return 1
    fi

    if [[ "$kind" == tree ]]; then
        mkdir -p "$OUT/$name"
        tar -xf "$archive" --no-same-owner --strip-components=1 -C "$OUT/$name"
        return 0
    fi

    if [[ "$members" == - ]]; then
        install -m 0755 "$archive" "$OUT/bin/$name"
        return 0
    fi

    local work mode member source dest found
    work=$(mktemp -d)
    unpack "$archive" "$url" "$work"

    mode=0755
    [[ "$kind" == web ]] && mode=0644
    IFS=, read -ra list <<<"$members"
    for member in "${list[@]}"; do
        source=${member%%:*}
        dest=${member##*:}
        found=$(find "$work" -type f -name "$source" | head -n 1)
        if [[ -z "$found" ]]; then
            echo "$name: $source not found in archive" >&2
            return 1
        fi
        install -m "$mode" "$found" "$OUT/$kind/$dest"
    done

    if [[ "$kind" == bin ]]; then
        mkdir -p "$OUT/licenses/$name"
        find "$work" -type f \( -iname 'LICENSE*' -o -iname 'NOTICE*' -o -iname 'COPYING*' \) \
            -exec cp {} "$OUT/licenses/$name/" \;
    fi
    rm -rf "$work"
}
export -f verify unpack fetch_one

selected() {
    # uv installs Python during the build, so it cannot be left out.
    local excluded=",${TOOLBOX_EXCLUDE:-},"
    grep -Ev '^[[:space:]]*(#|$)' "$lock" | while read -r kind name rest; do
        if [[ "$name" == uv || "$excluded" != *",$name,"* ]]; then
            printf '%s %s %s\n' "$kind" "$name" "$rest"
        fi
    done
}

selected | xargs -P 8 -L 1 bash -c 'set -euo pipefail; fetch_one "$@"' _

# The npm bundled with Node lags behind and carries a vulnerable dependency.
if [[ -d "$OUT/npm" && -d "$OUT/node/lib" ]]; then
    rm -rf "$OUT/node/lib/node_modules/npm"
    mv "$OUT/npm" "$OUT/node/lib/node_modules/npm"
    chmod 0755 "$OUT"/node/lib/node_modules/npm/bin/*-cli.js
fi
rm -rf "$OUT/npm" "$OUT/node/share" "$OUT/node/CHANGELOG.md" "$OUT/node/README.md"
